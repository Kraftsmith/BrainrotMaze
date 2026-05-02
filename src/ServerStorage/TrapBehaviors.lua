-- TrapBehaviors (ModuleScript in ServerStorage)
-- Handler-table per TrapType. Each handler binds one trap-model:
--   - читает свои атрибуты с модели,
--   - вешает Touched на hitbox-парты,
--   - запускает свой цикл (или reactive trigger) в task.spawn.
--
-- Спека: Game Design/Labyrinths.md § 4.1–4.5.
-- Эффект единый: ctx.fireHit(player) — debounce + TrapHit + sound + log.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local TrapBehaviors = {}

local HITBOX_TAG = "TrapHitbox"

------------------------------------------------------------------------
-- Shared helpers
------------------------------------------------------------------------

local function getTier(trap)
	local p = trap.Parent
	while p and p ~= workspace do
		local t = p:GetAttribute("Tier")
		if t then return t end
		p = p.Parent
	end
	return 2 -- default (Rare)
end

-- Множитель Period от тира лабиринта: T1 ×1.5 (медленно — обучение), T2 = базовая, дальше +20%/тир.
local function tierPeriodFactor(tier)
	if tier <= 1 then return 1.5 end
	return 1 / (1 + (tier - 2) * 0.2)
end

-- Перебрать все hitbox-парты с тегом TrapHitbox внутри trap.
local function forEachHitbox(trap, fn)
	for _, d in trap:GetDescendants() do
		if d:IsA("BasePart") and CollectionService:HasTag(d, HITBOX_TAG) then
			fn(d)
		end
	end
end

local function getPlayerFromHit(hit)
	local char = hit:FindFirstAncestorOfClass("Model")
	if not char then return nil end
	if not char:FindFirstChildOfClass("Humanoid") then return nil end
	return Players:GetPlayerFromCharacter(char)
end

local function playSound(trap)
	for _, s in trap:GetDescendants() do
		if s:IsA("Sound") then s:Play(); return end
	end
end

------------------------------------------------------------------------
-- Spikes (резкие шипы из пола) — periodic
------------------------------------------------------------------------

TrapBehaviors.Spikes = function(trap, ctx)
	local period = trap:GetAttribute("Period") or 3
	local activeDur = trap:GetAttribute("ActiveDuration") or 1
	local effectivePeriod = period * tierPeriodFactor(ctx.tier)

	local function paintSpikes(active)
		for _, d in trap:GetDescendants() do
			if d:IsA("BasePart") and d.Name == "Spike" then
				if active then
					d.Transparency = 0
					d.Color = Color3.fromRGB(255, 60, 60)
					d.Material = Enum.Material.Neon
				else
					d.Transparency = 0.4
					d.Color = Color3.fromRGB(180, 180, 180)
					d.Material = Enum.Material.Metal
				end
			end
		end
	end

	local function setActive(active)
		trap:SetAttribute("Active", active)
		forEachHitbox(trap, function(p) p.CanTouch = active end)
		paintSpikes(active)
	end

	forEachHitbox(trap, function(hb)
		hb.Touched:Connect(function(hit)
			if not trap:GetAttribute("Active") then return end
			local player = getPlayerFromHit(hit)
			if not player then return end
			if ctx.fireHit(player, trap) then playSound(trap) end
		end)
	end)

	setActive(false)
	task.spawn(function()
		while trap.Parent do
			local idle = math.max(0.1, effectivePeriod - activeDur)
			task.wait(idle)
			if not trap.Parent then break end
			setActive(true)
			task.wait(activeDur)
			if not trap.Parent then break end
			setActive(false)
		end
	end)
end

------------------------------------------------------------------------
-- FireJet (огненная струя из стены) — periodic
------------------------------------------------------------------------

TrapBehaviors.FireJet = function(trap, ctx)
	local period = trap:GetAttribute("Period") or 2.5
	local activeDur = trap:GetAttribute("ActiveDuration") or 0.8
	local effectivePeriod = period * tierPeriodFactor(ctx.tier)

	local function setActive(active)
		trap:SetAttribute("Active", active)
		forEachHitbox(trap, function(p) p.CanTouch = active end)
		for _, d in trap:GetDescendants() do
			if d:IsA("Beam") or d:IsA("ParticleEmitter") then
				d.Enabled = active
			end
		end
	end

	forEachHitbox(trap, function(hb)
		hb.Touched:Connect(function(hit)
			if not trap:GetAttribute("Active") then return end
			local player = getPlayerFromHit(hit)
			if not player then return end
			if ctx.fireHit(player, trap) then playSound(trap) end
		end)
	end)

	setActive(false)
	task.spawn(function()
		while trap.Parent do
			local idle = math.max(0.1, effectivePeriod - activeDur)
			task.wait(idle)
			if not trap.Parent then break end
			setActive(true)
			task.wait(activeDur)
			if not trap.Parent then break end
			setActive(false)
		end
	end)
end

------------------------------------------------------------------------
-- FloorDrop (проваливающийся пол) — REACTIVE trigger
-- Touched игроком → telegraph (warmup) → исчезает (CanCollide=false, Transparency=1)
-- → ждёт RestoreDelay → возвращается. Hit-эффект — на момент пропадания, для всех
-- стоящих над плиткой игроков (а не только триггернувшего).
------------------------------------------------------------------------

local FLOORDROP_VERTICAL_REACH = 6 -- студы выше плитки, в которые ловит игрока (для "стоящих над")

local function playersAboveTile(tile)
	local pos = tile.Position
	local size = tile.Size
	local result = {}
	for _, player in Players:GetPlayers() do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local rel = hrp.Position - pos
			if math.abs(rel.X) <= size.X/2 + 1
				and math.abs(rel.Z) <= size.Z/2 + 1
				and rel.Y > 0 and rel.Y < FLOORDROP_VERTICAL_REACH then
				table.insert(result, player)
			end
		end
	end
	return result
end

TrapBehaviors.FloorDrop = function(trap, ctx)
	local warmup = trap:GetAttribute("WarmupDelay") or 0.4
	local restoreDelay = trap:GetAttribute("RestoreDelay") or 2

	-- Состояние per-tile, чтобы каждая плитка работала независимо если их несколько в одной trap-модели.
	forEachHitbox(trap, function(tile)
		local origColor = tile.Color
		local origMaterial = tile.Material
		local origTransparency = tile.Transparency
		local triggered = false

		tile.Touched:Connect(function(hit)
			if triggered then return end
			local player = getPlayerFromHit(hit)
			if not player then return end
			triggered = true
			trap:SetAttribute("Active", true)
			playSound(trap)

			-- Telegraph: цвет/материал меняем, но плитка ещё держит
			tile.Color = Color3.fromRGB(255, 180, 60)
			tile.Material = Enum.Material.CrackedLava
			task.wait(warmup)

			-- Drop: проваливаемся
			tile.CanCollide = false
			tile.Transparency = 1
			for _, p in playersAboveTile(tile) do
				ctx.fireHit(p, trap)
			end

			-- Restore
			task.wait(restoreDelay)
			tile.CanCollide = true
			tile.Transparency = origTransparency
			tile.Color = origColor
			tile.Material = origMaterial
			trap:SetAttribute("Active", false)
			triggered = false
		end)
	end)

	trap:SetAttribute("Active", false)
end

------------------------------------------------------------------------
-- Bind dispatch
------------------------------------------------------------------------

-- Возвращает true если binding прошёл; false если TrapType неизвестен.
function TrapBehaviors.bind(trap, ctx)
	if trap:GetAttribute("_Bound") then return true end
	trap:SetAttribute("_Bound", true)

	local trapType = trap:GetAttribute("TrapType")
	local handler = TrapBehaviors[trapType]
	if not handler then
		warn(("[TrapBehaviors] неизвестный TrapType=%s на %s"):format(tostring(trapType), trap:GetFullName()))
		return false
	end

	ctx.tier = getTier(trap)
	handler(trap, ctx)
	return true
end

return TrapBehaviors
