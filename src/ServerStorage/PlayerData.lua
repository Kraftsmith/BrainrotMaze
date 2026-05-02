-- PlayerData (ModuleScript in ServerStorage)
-- In-memory per-player state. Future: backed by DataStore (separate task).
-- Single source of truth for upgrade levels, coins, and other per-player values.
--
-- `leaderstats.Coins` IntValue is a read-only mirror — Roblox UI needs it,
-- but PlayerData owns the value. All coin mutations go through addCoins/setCoins.

local Players = game:GetService("Players")

local PlayerData = {}

-- [player] = {coins, speedLvl, carryLvl, baseLvl, carrying = {entry, ...}, ...}
local data = {}

local DEFAULTS = {
	coins    = 0,
	speedLvl = 1,
	carryLvl = 1,
	baseLvl  = 1,
}

local CARRYING_ATTR = "CarryingBrainrot"

local changedEvent = Instance.new("BindableEvent")
PlayerData.Changed = changedEvent.Event -- fires (player, key, oldValue, newValue)

local function ensure(player)
	if not data[player] then
		local d = table.clone(DEFAULTS)
		-- ephemeral fields, не сохраняются в DataStore
		d.carrying = {}        -- стек переноски, top = последний подобранный
		d.placed = {}          -- размещённые на базе модели
		d.lastDelivery = 0     -- timestamp последней доставки (debounce)
		data[player] = d
	end
	return data[player]
end

local function refreshCarryAttr(player, count)
	player:SetAttribute(CARRYING_ATTR, count > 0)
end

local function ensureLeaderstats(player)
	local ls = player:FindFirstChild("leaderstats")
	if not ls then
		ls = Instance.new("Folder")
		ls.Name = "leaderstats"
		ls.Parent = player
	end
	local coins = ls:FindFirstChild("Coins")
	if not coins then
		coins = Instance.new("IntValue")
		coins.Name = "Coins"
		coins.Parent = ls
	end
	return coins
end

local function mirrorCoins(player, value)
	local coins = ensureLeaderstats(player)
	coins.Value = value
end

function PlayerData.get(player)
	return ensure(player)
end

function PlayerData.getValue(player, key)
	return ensure(player)[key]
end

function PlayerData.setValue(player, key, value)
	local d = ensure(player)
	local old = d[key]
	if old == value then return end
	d[key] = value
	if key == "coins" then
		mirrorCoins(player, value)
	end
	changedEvent:Fire(player, key, old, value)
end

function PlayerData.getCoins(player)
	return ensure(player).coins
end

function PlayerData.setCoins(player, value)
	PlayerData.setValue(player, "coins", value)
end

function PlayerData.addCoins(player, delta)
	if delta == 0 then return end
	local d = ensure(player)
	PlayerData.setValue(player, "coins", d.coins + delta)
end

------------------------------------------------------------------------
-- Atomic compound mutation. Mutator получает профиль и меняет поля in-place.
-- После запуска: для каждого изменившегося scalar-поля фаерится Changed,
-- coins зеркалится в leaderstats. Возвращает то, что вернул мутатор.
--
-- Используется для транзакций, где надо менять несколько полей вместе и решать
-- успешна ли операция (например, покупка апгрейда: проверить баланс, списать
-- коины, повысить уровень — всё или ничего).
------------------------------------------------------------------------

local TRACKED_KEYS = {"coins", "speedLvl", "carryLvl", "baseLvl"}

function PlayerData.update(player, mutator)
	local d = ensure(player)
	local before = {}
	for _, k in TRACKED_KEYS do before[k] = d[k] end

	local results = table.pack(mutator(d))

	for _, k in TRACKED_KEYS do
		local newVal = d[k]
		local oldVal = before[k]
		if newVal ~= oldVal then
			if k == "coins" then mirrorCoins(player, newVal) end
			changedEvent:Fire(player, k, oldVal, newVal)
		end
	end

	return table.unpack(results, 1, results.n)
end

------------------------------------------------------------------------
-- Carry stack (ephemeral)
-- entry = {model = Model, anchor = Part}, top of stack = last picked up.
------------------------------------------------------------------------

function PlayerData.pushCarry(player, entry)
	local d = ensure(player)
	table.insert(d.carrying, entry)
	refreshCarryAttr(player, #d.carrying)
end

function PlayerData.popCarryTop(player)
	local d = ensure(player)
	if #d.carrying == 0 then return nil end
	local top = table.remove(d.carrying)
	refreshCarryAttr(player, #d.carrying)
	return top
end

function PlayerData.popCarryAll(player)
	local d = ensure(player)
	local list = d.carrying
	d.carrying = {}
	refreshCarryAttr(player, 0)
	return list
end

function PlayerData.countCarry(player)
	return #ensure(player).carrying
end

-- Удалить и вернуть entry на индексе idx (1-based) из carry-стека. nil если вне диапазона.
-- Используется для случайной сдачи в слот: math.random(1, countCarry()) → removeCarryAt.
function PlayerData.removeCarryAt(player, idx)
	local d = ensure(player)
	if idx < 1 or idx > #d.carrying then return nil end
	local entry = table.remove(d.carrying, idx)
	refreshCarryAttr(player, #d.carrying)
	return entry
end

------------------------------------------------------------------------
-- Placed brainrots (ephemeral, в DataStore сохраняется отдельно SaveService через тег PLACED_TAG)
------------------------------------------------------------------------

function PlayerData.getPlaced(player)
	return ensure(player).placed
end

function PlayerData.addPlaced(player, model)
	table.insert(ensure(player).placed, model)
end

function PlayerData.addPlacedIfNew(player, model)
	local d = ensure(player)
	if not table.find(d.placed, model) then
		table.insert(d.placed, model)
	end
end

-- Удалить модель из placed-списка (например, при take-back с базы обратно в carry).
function PlayerData.removePlaced(player, model)
	local d = ensure(player)
	local idx = table.find(d.placed, model)
	if idx then table.remove(d.placed, idx) end
end

-- Удаляет из списка модели с пустым parent / разрушенные. Лениво вызывается на чтение.
function PlayerData.prunePlaced(player)
	local d = ensure(player)
	local alive = {}
	for _, m in d.placed do
		if m and m.Parent then table.insert(alive, m) end
	end
	d.placed = alive
end

------------------------------------------------------------------------
-- Delivery debounce
------------------------------------------------------------------------

function PlayerData.getLastDelivery(player)
	return ensure(player).lastDelivery
end

function PlayerData.setLastDelivery(player, t)
	ensure(player).lastDelivery = t
end

------------------------------------------------------------------------
-- Base ownership lookup
-- Centralizes the player→base lookup that 3+ scripts duplicated.
-- TODO: bases-service-абстракция (kanbn) — переехать в отдельный BasesService,
-- если/когда понадобится больше операций над базами (по списку, по индексу и т.п.).
------------------------------------------------------------------------

local BASE_NAMES = {"bazapl1", "bazapl2", "bazapl3", "bazapl4"}

function PlayerData.getBase(player)
	for _, name in BASE_NAMES do
		local base = workspace:FindFirstChild(name)
		if base and base:GetAttribute("Owner") == player.Name then
			return base
		end
	end
	return nil
end

local function setupPlayer(player)
	ensure(player)
	mirrorCoins(player, data[player].coins)
end

Players.PlayerAdded:Connect(setupPlayer)
for _, p in Players:GetPlayers() do setupPlayer(p) end

Players.PlayerRemoving:Connect(function(p)
	data[p] = nil
end)

return PlayerData
