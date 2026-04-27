-- PlayerData (ModuleScript in ServerStorage)
-- In-memory per-player state. Future: backed by DataStore (separate task).
-- Single source of truth for upgrade levels and other per-player values.

local Players = game:GetService("Players")

local PlayerData = {}

-- [player] = {speedLvl, carryLvl, baseLvl, ...}
local data = {}

local DEFAULTS = {
	speedLvl = 1,
	carryLvl = 1,
	baseLvl  = 1,
}

local changedEvent = Instance.new("BindableEvent")
PlayerData.Changed = changedEvent.Event -- fires (player, key, oldValue, newValue)

local function ensure(player)
	if not data[player] then
		data[player] = table.clone(DEFAULTS)
	end
	return data[player]
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
	changedEvent:Fire(player, key, old, value)
end

Players.PlayerRemoving:Connect(function(p)
	data[p] = nil
end)

return PlayerData
