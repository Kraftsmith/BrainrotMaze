-- BrainrotState (ModuleScript in ServerStorage)
-- Shared mutable carrying state. Used by both BrainrotPickup and BrainrotDelivery.
--   per-player list of {model = Model, anchor = Part}, ordered by pickup time.
--   stack: top = last picked up.

local BrainrotState = {}
local carrying = {}
local CARRYING_ATTR = "CarryingBrainrot"

local function refreshAttr(player)
	local list = carrying[player]
	player:SetAttribute(CARRYING_ATTR, list ~= nil and #list > 0)
end

function BrainrotState.add(player, entry)
	local list = carrying[player] or {}
	table.insert(list, entry)
	carrying[player] = list
	refreshAttr(player)
end

function BrainrotState.popTop(player)
	local list = carrying[player]
	if not list or #list == 0 then return nil end
	local top = table.remove(list)
	if #list == 0 then carrying[player] = nil end
	refreshAttr(player)
	return top
end

function BrainrotState.popAll(player)
	local list = carrying[player] or {}
	carrying[player] = nil
	refreshAttr(player)
	return list
end

function BrainrotState.count(player)
	local list = carrying[player]
	return list and #list or 0
end

return BrainrotState
