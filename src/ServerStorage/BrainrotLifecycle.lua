-- BrainrotLifecycle (ModuleScript in ServerStorage)
-- Single source of truth for brainrot lifecycle states.
-- Owns: BrainrotLifecycleState attribute, Brainrot/PlacedBrainrot tags,
-- PlacedBy/PlacedOnBase ownership attrs, lifecycle BindableEvents.
--
-- Callers (Spawner / Pickup / Delivery / SaveService) only call transition();
-- they never set the tags/state attributes directly.
--
-- States:
--   Spawned   — exists in workspace, prompt-pickable
--   Carried   — welded above a player's head
--   Dropped   — back in workspace after E or trap
--   Placed    — on a base, generates income
--   Destroyed — terminal (player died, server cleanup)

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")

local STATE_ATTR = "BrainrotLifecycleState"
local BRAINROT_TAG = "Brainrot"
local PLACED_TAG = "PlacedBrainrot"

local BrainrotLifecycle = {}

local States = {
	Spawned = "Spawned",
	Carried = "Carried",
	Dropped = "Dropped",
	Placed = "Placed",
	Destroyed = "Destroyed",
}
BrainrotLifecycle.States = States

-- Allowed transitions. Key `false` = no prior state (fresh clone).
-- Placed → Carried — игрок забирает свой placed-брейнрот с базы (E на TakeBackPrompt),
-- чтобы освободить слот под более доходного.
local ALLOWED = {
	[false]            = { [States.Spawned]   = true, [States.Placed]    = true },
	[States.Spawned]   = { [States.Carried]   = true, [States.Destroyed] = true },
	[States.Carried]   = { [States.Dropped]   = true, [States.Placed]    = true, [States.Destroyed] = true },
	[States.Dropped]   = { [States.Carried]   = true, [States.Destroyed] = true },
	[States.Placed]    = { [States.Carried]   = true, [States.Destroyed] = true },
	[States.Destroyed] = {},
}

------------------------------------------------------------------------
-- BindableEvent lookup (lazy — folder is created at runtime by Pickup)
------------------------------------------------------------------------

local eventsFolder
local function getEvent(name)
	if not eventsFolder then
		eventsFolder = ServerStorage:WaitForChild("BrainrotEvents", 10)
		if not eventsFolder then return nil end
	end
	return eventsFolder:FindFirstChild(name)
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------

function BrainrotLifecycle.getState(model)
	if not model or typeof(model) ~= "Instance" then return nil end
	local s = model:GetAttribute(STATE_ATTR)
	if s then return s end
	-- Fallback for legacy instances (placed via old code, or freshly tagged by Spawner before this module ran)
	if CollectionService:HasTag(model, PLACED_TAG) then return States.Placed end
	if CollectionService:HasTag(model, BRAINROT_TAG) then return States.Spawned end
	return nil
end

local function applyTagsForState(model, state)
	if state == States.Placed then
		if CollectionService:HasTag(model, BRAINROT_TAG) then CollectionService:RemoveTag(model, BRAINROT_TAG) end
		if not CollectionService:HasTag(model, PLACED_TAG) then CollectionService:AddTag(model, PLACED_TAG) end
	elseif state == States.Spawned or state == States.Carried or state == States.Dropped then
		if CollectionService:HasTag(model, PLACED_TAG) then CollectionService:RemoveTag(model, PLACED_TAG) end
		if not CollectionService:HasTag(model, BRAINROT_TAG) then CollectionService:AddTag(model, BRAINROT_TAG) end
	elseif state == States.Destroyed then
		if CollectionService:HasTag(model, BRAINROT_TAG) then CollectionService:RemoveTag(model, BRAINROT_TAG) end
		if CollectionService:HasTag(model, PLACED_TAG) then CollectionService:RemoveTag(model, PLACED_TAG) end
	end
end

local function fireEventForTransition(model, toState, context)
	context = context or {}
	if toState == States.Carried then
		local e = getEvent("Picked"); if e then e:Fire(model, context.player) end
	elseif toState == States.Dropped then
		local e = getEvent("Dropped"); if e then e:Fire(model, context.player) end
	elseif toState == States.Placed then
		local e = getEvent("Placed"); if e then e:Fire(model, context.base, context.player) end
	elseif toState == States.Destroyed then
		local e = getEvent("Destroyed"); if e then e:Fire(model, context.reason) end
	end
end

-- Transition `model` to `toState`. `context` carries side data needed by lifecycle bookkeeping:
--   {player = Player, base = BasePart, reason = string}
-- Returns (true) on success or (false, errMsg) if the transition isn't allowed.
function BrainrotLifecycle.transition(model, toState, context)
	if not model or typeof(model) ~= "Instance" then
		return false, "model is not an Instance"
	end
	if not States[toState] then
		return false, "unknown target state: " .. tostring(toState)
	end

	local fromState = BrainrotLifecycle.getState(model)
	local allowedSet = ALLOWED[fromState or false]
	if not allowedSet or not allowedSet[toState] then
		return false, ("invalid transition %s -> %s"):format(tostring(fromState), tostring(toState))
	end

	model:SetAttribute(STATE_ATTR, toState)
	applyTagsForState(model, toState)

	if toState == States.Placed then
		local base = context and context.base
		local player = context and context.player
		if base then model:SetAttribute("PlacedOnBase", base.Name) end
		if player then model:SetAttribute("PlacedBy", player.Name) end
	end

	fireEventForTransition(model, toState, context)
	return true
end

return BrainrotLifecycle
