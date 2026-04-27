-- MazeTrapsServer (Script in ServerScriptService)
-- For each MazeTrap-tagged model: cycle Active on/off, on Touched while active fire TrapHit.
-- Tier multiplier: higher-tier mazes have shorter Period (more dangerous).

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

local Util = require(ServerStorage:WaitForChild("Util"))

local TRAP_TAG = "MazeTrap"
local HITBOX_TAG = "TrapHitbox"
local DEBOUNCE = 1.5 -- seconds between trap hits per player

local trapHitEvent = ServerStorage:WaitForChild("BrainrotEvents"):WaitForChild("TrapHit")

-- per-player last hit timestamp
local lastHit = {}

local function getTier(trap)
	local p = trap.Parent
	while p and p ~= workspace do
		local t = p:GetAttribute("Tier")
		if t then return t end
		p = p.Parent
	end
	return 2 -- default tier if not found
end

local function setActive(trap, active)
	trap:SetAttribute("Active", active)
	local trapType = trap:GetAttribute("TrapType")

	for _, d in trap:GetDescendants() do
		-- Toggle hitbox CanTouch (only fires Touched when active)
		if d:IsA("BasePart") and CollectionService:HasTag(d, HITBOX_TAG) then
			d.CanTouch = active
		end

		-- FireJet: toggle Beam + ParticleEmitter
		if trapType == "FireJet" then
			if d:IsA("Beam") or d:IsA("ParticleEmitter") then
				d.Enabled = active
			end
		end

		-- Spikes: visible always but pop bright red+neon when active
		if trapType == "Spikes" and d:IsA("BasePart") and d.Name == "Spike" then
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

local function bindTrap(trap)
	if trap:GetAttribute("_Bound") then return end
	trap:SetAttribute("_Bound", true)

	local period = trap:GetAttribute("Period") or 3
	local activeDur = trap:GetAttribute("ActiveDuration") or 1
	local tier = getTier(trap)
	local effectivePeriod = period / (1 + math.max(0, tier - 2) * 0.2)

	for _, d in trap:GetDescendants() do
		if d:IsA("BasePart") and CollectionService:HasTag(d, HITBOX_TAG) then
			d.Touched:Connect(function(hit)
				if not trap:GetAttribute("Active") then return end
				local char = hit:FindFirstAncestorOfClass("Model")
				if not char then return end
				if not char:FindFirstChildOfClass("Humanoid") then return end
				local player = Players:GetPlayerFromCharacter(char)
				if not player then return end

				local now = os.clock()
				local last = lastHit[player]
				if last and now - last < DEBOUNCE then return end
				lastHit[player] = now

				trapHitEvent:Fire(player)
				print(("[MazeTrapsServer] %s tripped %s @ %s"):format(
					player.Name, trap:GetAttribute("TrapType") or "?", Util.locationOf(player)
				))

				-- Play sound (first found Sound in trap)
				for _, s in trap:GetDescendants() do
					if s:IsA("Sound") then s:Play(); break end
				end
			end)
		end
	end

	-- Activation cycle
	setActive(trap, false)
	task.spawn(function()
		while trap.Parent do
			local idle = math.max(0.1, effectivePeriod - activeDur)
			task.wait(idle)
			if not trap.Parent then break end
			setActive(trap, true)
			task.wait(activeDur)
			if not trap.Parent then break end
			setActive(trap, false)
		end
	end)
end

for _, t in CollectionService:GetTagged(TRAP_TAG) do bindTrap(t) end
CollectionService:GetInstanceAddedSignal(TRAP_TAG):Connect(bindTrap)

Players.PlayerRemoving:Connect(function(p) lastHit[p] = nil end)

print(("[MazeTrapsServer] ready, %d traps active"):format(#CollectionService:GetTagged(TRAP_TAG)))
