-- TeleportPortals (Script in ServerScriptService)
-- Bidirectional teleport pair: stepping on either tagged part teleports the player to the paired one.
-- Tags:
--   BaseTeleport — the part on the player base.
--   MazeTeleport — the part in the entry of maze 1.
-- Spec: see Game Design/Main Game Design.md § Телепорт.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local TAG_BASE = "BaseTeleport"
local TAG_MAZE = "MazeTeleport"
local FRONT_OFFSET = 4    -- studs in front of the destination pad — keeps the player out of the pad's collision so we don't infinite-loop on Touched
local CHARACTER_HEIGHT = 3
local DEBOUNCE = 1.5      -- per-player cooldown so a single step doesn't fire dozens of Touched events

local lastFired = {}      -- [player] = os.clock()

local function getDestinationFor(touched)
	if CollectionService:HasTag(touched, TAG_BASE) then
		return CollectionService:GetTagged(TAG_MAZE)[1]
	elseif CollectionService:HasTag(touched, TAG_MAZE) then
		return CollectionService:GetTagged(TAG_BASE)[1]
	end
	return nil
end

local function tryTeleport(player, fromPad)
	local now = os.clock()
	if lastFired[player] and now - lastFired[player] < DEBOUNCE then return end
	lastFired[player] = now

	local dest = getDestinationFor(fromPad)
	if not dest then
		warn(("[TeleportPortals] no paired pad for %s"):format(fromPad:GetFullName()))
		return
	end

	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- Spawn the player IN FRONT of the destination pad (along its LookVector), at floor level
	-- (pad bottom + character height/2). Avoids landing inside the pad's collision and re-triggering Touched.
	local destCF = dest.CFrame
	local front = destCF.LookVector
	local bottomY = destCF.Position.Y - dest.Size.Y/2
	local spawnPos = destCF.Position + front * FRONT_OFFSET
	hrp.CFrame = CFrame.new(
		Vector3.new(spawnPos.X, bottomY + CHARACTER_HEIGHT, spawnPos.Z),
		Vector3.new(spawnPos.X, bottomY + CHARACTER_HEIGHT, spawnPos.Z) + front -- face away from pad
	)
	print(("[TeleportPortals] %s: %s -> %s"):format(player.Name, fromPad.Name, dest.Name))
end

local function bindPad(p)
	if not p:IsA("BasePart") then return end
	p.Touched:Connect(function(other)
		local char = other:FindFirstAncestorOfClass("Model")
		if not char then return end
		if not char:FindFirstChildOfClass("Humanoid") then return end
		local player = Players:GetPlayerFromCharacter(char)
		if player then tryTeleport(player, p) end
	end)
end

for _, p in CollectionService:GetTagged(TAG_BASE) do bindPad(p) end
for _, p in CollectionService:GetTagged(TAG_MAZE) do bindPad(p) end
CollectionService:GetInstanceAddedSignal(TAG_BASE):Connect(bindPad)
CollectionService:GetInstanceAddedSignal(TAG_MAZE):Connect(bindPad)

Players.PlayerRemoving:Connect(function(p) lastFired[p] = nil end)

print("[TeleportPortals] ready")
