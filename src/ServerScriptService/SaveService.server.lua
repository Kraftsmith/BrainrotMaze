-- SaveService (Script in ServerScriptService)
-- Phase A+B: persists coins + upgrade levels + placed brainrots per player via DataStore.
-- Spec: Game Design/User Session.md
--
-- Schema:
--   v1: {schemaVersion=1, coins, speedLvl, carryLvl, baseLvl}
--   v2: + placedBrainrots = {{name, cframe={12 components, RELATIVE to base pivot}}, ...}
--   v3: baseLvl semantics — per-slot apgrades (UpgradeConfig.baseCap, lvl 1..21 = 10..30 слотов).
--       Старые baseLvl 1/2/3 мигрируются в 1/11/21 — тот же cap (10/20/30), тот же визуал.
--
-- Триггеры сейва: PlayerRemoving, BindToClose, autosave каждые 180 сек.
-- Загрузка: на PlayerAdded. При сбое DataStore в Studio — fallback (дефолты, no-save). На live — кик.
-- Гейт покупок: атрибут `ProfileLoaded` на игроке. UpgradeService отказывает в покупке, пока не выставлен.
-- Рехидрация placed-брейнротов: клонируем шаблоны из ServerStorage.BrainrotTemplates, ставим тег
-- PlacedBrainrot — BrainrotDelivery подхватывает через GetInstanceAddedSignal и регистрирует в placed[base].
-- Chat-команда /resetbase (только в Studio): стирает свой профиль + кикает для fresh start.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local IS_STUDIO = RunService:IsStudio()

local PLACED_TAG = "PlacedBrainrot"
local BRAINROT_TAG = "Brainrot"

local PlayerData = require(ServerStorage:WaitForChild("PlayerData"))
local BrainrotLifecycle = require(ServerStorage:WaitForChild("BrainrotLifecycle"))

local STORE_NAME = "PlayerData_v1"
local SCHEMA_VERSION = 3 -- v1 = coins+lvls, v2 = +placedBrainrots, v3 = baseLvl per-slot semantics
local AUTOSAVE_INTERVAL = 180
local SAVE_RETRY_DELAYS = {1, 2, 4} -- exponential backoff
local SHUTDOWN_TIMEOUT = 25

local store = DataStoreService:GetDataStore(STORE_NAME)

-- per-player session state: [player] = {loaded = bool, joinedAt = clock}
local sessions = {}

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

local function keyFor(player)
	return ("player_%d"):format(player.UserId)
end

local function fmtSnapshot(s)
	if not s then return "<nil>" end
	return ("{coins=%s, speed=%s, carry=%s, base=%s, placed=%d, schema=%s}"):format(
		tostring(s.coins), tostring(s.speedLvl), tostring(s.carryLvl), tostring(s.baseLvl),
		s.placedBrainrots and #s.placedBrainrots or 0, tostring(s.schemaVersion)
	)
end

-- Снимаем placed-брейнротов в формате {name, cframe} с CFrame **относительно базы**
-- (чтобы при возврате на другой слот bazapl1..4 они оказались на правильных местах).
local function snapshotPlaced(player)
	local list = {}
	local base = PlayerData.getBase(player)
	if not base then return list end
	local basePivot = base:GetPivot()
	for _, model in CollectionService:GetTagged(PLACED_TAG) do
		if model:GetAttribute("PlacedBy") == player.Name and model.Parent then
			local relCF = basePivot:ToObjectSpace(model:GetPivot())
			table.insert(list, {
				name = model.Name,
				cframe = {relCF:GetComponents()},
			})
		end
	end
	return list
end

-- Восстанавливает брейнротов из снимка на текущей базе игрока.
-- Запускается в task.spawn после applySnapshot, ждёт назначения базы (BaseManager).
local function rehydratePlaced(player, list)
	if not list or #list == 0 then return end
	local templates = ServerStorage:FindFirstChild("BrainrotTemplates")
	if not templates then
		warn("[SaveService] BrainrotTemplates не найдены в ServerStorage — рехидрация placed-брейнротов пропущена")
		return
	end

	-- Ждём до 10 секунд назначения базы (BaseManager делает это на PlayerAdded — может прийти позже SaveService)
	local base
	for _ = 1, 20 do
		base = PlayerData.getBase(player)
		if base then break end
		task.wait(0.5)
	end
	if not base then
		warn(("[SaveService] %s база не назначена за 10s — placed-брейнроты НЕ восстановлены (%d шт.)"):format(
			player.Name, #list
		))
		return
	end

	local basePivot = base:GetPivot()
	local restored, skipped = 0, 0

	for _, entry in list do
		local template = templates:FindFirstChild(entry.name)
		if not template then
			print(("[Session] skipped unknown brainrot '%s' for player %s"):format(entry.name, player.Name))
			skipped += 1
			continue
		end

		local clone = template:Clone()
		for _, p in clone:GetDescendants() do
			if p:IsA("BasePart") then
				p.Anchored = true
				p.CanCollide = false
				p.Massless = false
			end
			if p:IsA("ProximityPrompt") then
				p.Enabled = false
			end
		end

		-- Templates aren't tagged, but be defensive in case a future template ships with one.
		CollectionService:RemoveTag(clone, BRAINROT_TAG)

		clone.Parent = base
		if entry.cframe and #entry.cframe == 12 then
			local relCF = CFrame.new(table.unpack(entry.cframe))
			clone:PivotTo(basePivot * relCF)
		end

		-- Lifecycle: nil -> Placed (sets PlacedBrainrot tag, PlacedBy/PlacedOnBase attributes,
		-- fires Placed BindableEvent — BrainrotDelivery's GetInstanceAddedSignal then registers it).
		local ok, err = BrainrotLifecycle.transition(clone, BrainrotLifecycle.States.Placed, {base = base, player = player})
		if not ok then
			warn(("[SaveService] failed to transition rehydrated %s to Placed: %s"):format(entry.name, tostring(err)))
		end
		restored += 1
	end

	print(("[SaveService] %s rehydrated %d placed brainrots (skipped %d) on %s"):format(
		player.Name, restored, skipped, base.Name
	))
end

-- pcallRetry с подробным логом по каждой попытке.
local function pcallRetry(label, fn)
	local lastErr
	for attempt = 0, #SAVE_RETRY_DELAYS do
		local startedAt = os.clock()
		local ok, result = pcall(fn)
		local ms = math.floor((os.clock() - startedAt) * 1000)
		if ok then
			if attempt > 0 then
				print(("[SaveService] %s ok on attempt %d (%dms)"):format(label, attempt + 1, ms))
			end
			return true, result
		end
		lastErr = result
		warn(("[SaveService] %s attempt %d/%d FAILED (%dms): %s"):format(
			label, attempt + 1, #SAVE_RETRY_DELAYS + 1, ms, tostring(result)
		))
		if attempt < #SAVE_RETRY_DELAYS then
			local delay = SAVE_RETRY_DELAYS[attempt + 1]
			print(("[SaveService] %s retrying in %ds..."):format(label, delay))
			task.wait(delay)
		end
	end
	return false, lastErr
end

local function buildSnapshot(player)
	return {
		schemaVersion = SCHEMA_VERSION,
		coins = PlayerData.getCoins(player),
		speedLvl = PlayerData.getValue(player, "speedLvl"),
		carryLvl = PlayerData.getValue(player, "carryLvl"),
		baseLvl = PlayerData.getValue(player, "baseLvl"),
		placedBrainrots = snapshotPlaced(player),
	}
end

-- Миграция между schema-версиями. Вызывается при загрузке.
local function migrate(profile)
	if not profile then return profile end
	local v = profile.schemaVersion or 1
	if v < 2 then
		profile.placedBrainrots = profile.placedBrainrots or {}
		profile.schemaVersion = 2
	end
	if v < 3 then
		-- v2→v3: старые 3 уровня (10/20/30 слотов) → per-slot шкала (lvl 1..21).
		-- 1→1, 2→11, 3→21 сохраняет прежний cap и визуал; ≥4 не существовало в v2.
		local old = profile.baseLvl or 1
		local mapping = {[1] = 1, [2] = 11, [3] = 21}
		profile.baseLvl = mapping[old] or old
		profile.schemaVersion = 3
	end
	return profile
end

local function applySnapshot(player, profile)
	if not profile then return end

	local v = profile.schemaVersion or 0
	if v ~= SCHEMA_VERSION then
		warn(("[SaveService] schema mismatch for %s: got %d, want %d (no migration yet — applying as-is)"):format(
			player.Name, v, SCHEMA_VERSION
		))
	end

	-- setValue фаерит PlayerData.Changed; UpgradeService слушает уровни, leaderstats.Coins зеркалится изнутри PlayerData.
	PlayerData.setValue(player, "speedLvl", profile.speedLvl or 1)
	PlayerData.setValue(player, "carryLvl", profile.carryLvl or 1)
	PlayerData.setValue(player, "baseLvl", profile.baseLvl or 1)
	PlayerData.setCoins(player, profile.coins or 0)
end

------------------------------------------------------------------------
-- Load / Save
------------------------------------------------------------------------

local function loadProfile(player)
	return pcallRetry(("LOAD %s"):format(player.Name), function()
		return store:GetAsync(keyFor(player))
	end)
end

local function saveSnapshot(player, snapshot, reason)
	local label = ("SAVE %s [%s]"):format(player.Name, reason)
	local ok, err = pcallRetry(label, function()
		store:SetAsync(keyFor(player), snapshot)
		return true
	end)
	if ok then
		print(("[SaveService] %s SAVED %s"):format(reason, fmtSnapshot(snapshot)))
	else
		warn(("[SaveService] %s SAVE FAILED for %s: %s"):format(reason, player.Name, tostring(err)))
	end
	return ok, err
end

local function saveProfileFor(player, reason)
	local sess = sessions[player]
	if not sess or not sess.loaded then return false, "not loaded" end
	if sess.noSave then return false, "no-save mode (Studio fallback)" end
	local snapshot = buildSnapshot(player)
	return saveSnapshot(player, snapshot, reason or "manual")
end

------------------------------------------------------------------------
-- Player lifecycle
------------------------------------------------------------------------

local function onPlayerAdded(player)
	if sessions[player] then return end
	sessions[player] = {loaded = false, joinedAt = os.clock()}
	print(("[SaveService] PlayerAdded %s (UserId=%d) — starting load"):format(player.Name, player.UserId))

	local startedAt = os.clock()
	local ok, profile = loadProfile(player)
	local loadMs = math.floor((os.clock() - startedAt) * 1000)

	if not sessions[player] then
		print(("[SaveService] %s left during load (%dms) — abort"):format(player.Name, loadMs))
		return
	end

	if not ok then
		warn(("[SaveService] %s LOAD FATAL after %dms: %s"):format(player.Name, loadMs, tostring(profile)))

		if IS_STUDIO then
			-- Studio-fallback: не кикаем, играем с дефолтами, но сейвы выключаем чтобы не затирать.
			-- Скорее всего у тебя выключен Game Settings → Security → Allow API Services.
			warn(("[SaveService] %s — Studio fallback: дефолты, БЕЗ СЕЙВОВ в этой сессии. Включи Game Settings → Security → Allow API Services чтобы тестировать сохранение."):format(player.Name))
			sessions[player].loaded = true
			sessions[player].noSave = true
			player:SetAttribute("ProfileLoaded", true)
			return
		end

		sessions[player] = nil
		player:Kick("Failed to load your progress. Please try again in a minute.")
		return
	end

	profile = migrate(profile)
	applySnapshot(player, profile)
	sessions[player].loaded = true
	player:SetAttribute("ProfileLoaded", true)

	if profile then
		print(("[SaveService] LOADED %s in %dms — %s"):format(player.Name, loadMs, fmtSnapshot(profile)))
		-- Рехидрация placed-брейнротов в фоне (ждёт назначения базы)
		if profile.placedBrainrots and #profile.placedBrainrots > 0 then
			task.spawn(rehydratePlaced, player, profile.placedBrainrots)
		end
	else
		print(("[SaveService] LOADED %s in %dms — fresh player, defaults"):format(player.Name, loadMs))
	end
end

local function onPlayerRemoving(player)
	local sess = sessions[player]
	sessions[player] = nil
	print(("[SaveService] PlayerRemoving %s (loaded=%s)"):format(player.Name, sess and tostring(sess.loaded) or "<no session>"))

	if not sess or not sess.loaded then
		print(("[SaveService] %s left before profile loaded — SKIP SAVE (защита от затирания)"):format(player.Name))
		return
	end
	if sess.noSave then
		print(("[SaveService] %s left in Studio no-save mode — SKIP SAVE"):format(player.Name))
		return
	end

	local snapshot = buildSnapshot(player)
	saveSnapshot(player, snapshot, "leave")
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, p in Players:GetPlayers() do task.spawn(onPlayerAdded, p) end

------------------------------------------------------------------------
-- Autosave
------------------------------------------------------------------------

task.spawn(function()
	while true do
		task.wait(AUTOSAVE_INTERVAL)
		local online = #Players:GetPlayers()
		if online == 0 then
			print("[SaveService] autosave tick — 0 online, skip")
		else
			print(("[SaveService] autosave tick — %d online"):format(online))
			for _, player in Players:GetPlayers() do
				local ok, err = saveProfileFor(player, "autosave")
				if not ok and err == "not loaded" then
					print(("[SaveService] autosave skip %s (profile not loaded)"):format(player.Name))
				end
			end
		end
	end
end)

------------------------------------------------------------------------
-- Server shutdown
------------------------------------------------------------------------

game:BindToClose(function()
	local toSave = {}
	for _, player in Players:GetPlayers() do
		local sess = sessions[player]
		if sess and sess.loaded then
			table.insert(toSave, player)
		end
	end

	print(("[SaveService] BindToClose — %d players to save (timeout %ds)"):format(#toSave, SHUTDOWN_TIMEOUT))
	if #toSave == 0 then return end

	local pending = #toSave
	for _, player in toSave do
		task.spawn(function()
			saveProfileFor(player, "shutdown")
			pending -= 1
		end)
	end

	local deadline = os.clock() + SHUTDOWN_TIMEOUT
	while pending > 0 and os.clock() < deadline do
		task.wait(0.5)
	end
	if pending > 0 then
		warn(("[SaveService] BindToClose timeout — %d players NOT saved"):format(pending))
	else
		print("[SaveService] BindToClose all saved")
	end
end)

------------------------------------------------------------------------
-- /resetbase chat command — обнуляет всё: профиль в DataStore, placed-брейнроты в workspace,
-- carry-стек. Кикает игрока для гарантированно чистой загрузки.
--   1. session.noSave=true — защита от перезаписи на kick'е/autosave'е/BindToClose.
--   2. Уничтожаем все PlacedBrainrot-модели игрока в workspace (иначе после рейджоина они
--      висят как "призраки" — модели есть, в PlayerData.placed их нет, дохода не дают).
--   3. Чистим carry-стек (popCarryAll).
--   4. RemoveAsync из DataStore.
--   5. Kick → перезаход → SaveService не находит ключ → дефолтный профиль.
--
-- Доступ: Studio (любой) ИЛИ UserId в RESET_ALLOWLIST (тестовые аккаунты разработчика).
-- На live серверах для рандомных игроков команда отказывает.
--
-- Регистрируем через TextChatService.TextChatCommand (новый чат) И Player.Chatted (legacy chat).
------------------------------------------------------------------------

-- Разрешённые на live UserId. Добавляй сюда тестовые/админские аккаунты.
local RESET_ALLOWLIST = {
	[3507055395] = true,  -- MikhailSorokin (owner)
	[8603885583] = true,  -- kaczka2371 (тестовый)
}

local function resetProfile(player)
	print(("[SaveService] >>> /resetbase START for %s (UserId=%d, IS_STUDIO=%s, allowed=%s)"):format(
		player.Name, player.UserId, tostring(IS_STUDIO), tostring(RESET_ALLOWLIST[player.UserId] == true)))
	if not IS_STUDIO and not RESET_ALLOWLIST[player.UserId] then
		warn(("[SaveService] /resetbase from %s (UserId=%d) DENIED — not in allowlist"):format(
			player.Name, player.UserId))
		return
	end
	local sess = sessions[player]
	if sess then sess.noSave = true end -- блокируем autosave/PlayerRemoving пока всё не обнулим
	print(("[SaveService] step 1: destroying placed brainrots…"))

	-- 1. Уничтожить placed-брейнротов игрока.
	local destroyedCount = 0
	for _, model in CollectionService:GetTagged(PLACED_TAG) do
		if model:GetAttribute("PlacedBy") == player.Name then
			model:Destroy()
			destroyedCount += 1
		end
	end
	print(("[SaveService] step 1 done: destroyed %d placed brainrots"):format(destroyedCount))

	-- 2. Уничтожить брейнротов в carry-стеке (welded к голове).
	print(("[SaveService] step 2: clearing carry stack…"))
	local carryList = PlayerData.popCarryAll(player)
	local carryDestroyed = 0
	for _, entry in carryList do
		if entry.anchor then entry.anchor:Destroy() end
		if entry.model then
			BrainrotLifecycle.transition(entry.model, BrainrotLifecycle.States.Destroyed, {reason = "reset"})
			entry.model:Destroy()
			carryDestroyed += 1
		end
	end
	print(("[SaveService] step 2 done: destroyed %d carried brainrots"):format(carryDestroyed))

	-- 3. Сбросить in-memory PlayerData. setValue фаерит PlayerData.Changed →
	--    UpgradeService.applySpeed/applyBaseCapacity/syncAttributes отрабатывают:
	--    WalkSpeed → 16, base.Capacity → 10, player.attributes (для shop UI) синкаются.
	print(("[SaveService] step 3: zeroing in-memory PlayerData (coins/speed/carry/base)…"))
	PlayerData.setCoins(player, 0)
	PlayerData.setValue(player, "speedLvl", 1)
	PlayerData.setValue(player, "carryLvl", 1)
	PlayerData.setValue(player, "baseLvl", 1)
	print(("[SaveService] step 3 done: in-memory reset (coins=%d, speedLvl=%s, carryLvl=%s, baseLvl=%s)"):format(
		PlayerData.getCoins(player),
		tostring(PlayerData.getValue(player, "speedLvl")),
		tostring(PlayerData.getValue(player, "carryLvl")),
		tostring(PlayerData.getValue(player, "baseLvl"))))

	-- 4. Сохранить обнулённый снапшот в DataStore — overwrite старого профиля.
	--    Используем SetAsync (через saveSnapshot) вместо RemoveAsync: тот же эффект на load
	--    (applySnapshot выставит дефолты), но проще логировать и retry.
	print(("[SaveService] step 4: saving zeroed snapshot to DataStore…"))
	if sess then sess.noSave = false end
	local snapshot = buildSnapshot(player)
	local ok, err = saveSnapshot(player, snapshot, "reset")

	print(("[SaveService] %s reset complete — destroyed %d placed + %d carried, in-memory zeroed, DataStore=%s"):format(
		player.Name, destroyedCount, carryDestroyed, ok and "saved" or "FAILED"
	))
	if not ok then
		warn(("[SaveService] %s DataStore wipe failed (%s) — in-memory ОБНУЛЁН но старый профиль может вернуться при ребуте сервера"):format(
			player.Name, tostring(err)))
	end
end

-- Регистрируем handler в зависимости от режима чата. Оба пути одновременно дают двойной
-- вызов resetProfile в новом чате (Player.Chatted всё равно фаерится для /команд).
local TextChatService = game:GetService("TextChatService")
local useNewChat = TextChatService.ChatVersion == Enum.ChatVersion.TextChatService

if useNewChat then
	local existing = TextChatService:FindFirstChild("ResetBaseCommand")
	if existing then existing:Destroy() end -- защита от старой инстанции из прошлого Play-сеанса
	local resetCmd = Instance.new("TextChatCommand")
	resetCmd.Name = "ResetBaseCommand"
	resetCmd.PrimaryAlias = "/resetbase"
	resetCmd.Triggered:Connect(function(textSource)
		print(("[SaveService] /resetbase TextChatCommand.Triggered fired (UserId=%d)"):format(textSource.UserId))
		local player = Players:GetPlayerByUserId(textSource.UserId)
		if player then
			resetProfile(player)
		else
			warn(("[SaveService] /resetbase: no Player object for UserId=%d"):format(textSource.UserId))
		end
	end)
	resetCmd.Parent = TextChatService
	print("[SaveService] TextChatCommand /resetbase registered")
else
	-- Legacy chat — fallback через Player.Chatted.
	local function bindResetChat(player)
		player.Chatted:Connect(function(msg)
			if msg:lower():match("^/resetbase%s*$") then
				resetProfile(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(bindResetChat)
	for _, p in Players:GetPlayers() do bindResetChat(p) end
end

print(("[SaveService] ready (studio=%s, autosave every %ds, retry delays %s)"):format(
	tostring(IS_STUDIO),
	AUTOSAVE_INTERVAL,
	table.concat(SAVE_RETRY_DELAYS, "s/") .. "s"
))
