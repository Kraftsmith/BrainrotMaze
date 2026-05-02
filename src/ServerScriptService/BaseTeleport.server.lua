-- BaseTeleport (Script in ServerScriptService)
-- Pad-based teleport между базой и началом 1-го лабиринта.
-- Spec: Game Design/Main Game Design.md § Телепорт
--
-- Tags:
--   BaseTeleport — парт на каждой базе (bazapl1..4 потомок). Игрок наступил → переносится на MazeTeleport.
--   MazeTeleport — парт в начале 1-го лабиринта. Игрок наступил → переносится на BaseTeleport своей базы.
--
-- Двунаправленная пара. Дебаунс 2 сек на игрока — чтобы не залупиться, когда после телепорта стоишь на парном парте.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local BASE_TAG = "BaseTeleport"
local MAZE_TAG = "MazeTeleport"
local BASE_NAMES = {"bazapl1", "bazapl2", "bazapl3", "bazapl4"}
local DEBOUNCE = 2 -- seconds
local LIFT = 3 -- студы над паром, чтобы персонаж не клипился внутрь

local lastTeleport = {} -- [player] = clock

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

local function findMazeTeleport()
	for _, p in CollectionService:GetTagged(MAZE_TAG) do
		if p:IsA("BasePart") and p:IsDescendantOf(Workspace) then
			return p
		end
	end
	return nil
end

-- BaseTeleport на конкретной базе игрока (Owner attribute).
-- Если у игрока ещё нет базы (BaseManager не успел) — вернётся nil.
local function findOwnerBaseTeleport(player)
	for _, name in BASE_NAMES do
		local base = Workspace:FindFirstChild(name)
		if base and base:GetAttribute("Owner") == player.Name then
			for _, descendant in base:GetDescendants() do
				if descendant:IsA("BasePart") and CollectionService:HasTag(descendant, BASE_TAG) then
					return descendant
				end
			end
		end
	end
	return nil
end

local function teleportPlayer(player, destPart)
	local char = player.Character
	if not char then return false end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return false end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	hrp.CFrame = destPart.CFrame + Vector3.new(0, destPart.Size.Y/2 + LIFT, 0)
	return true
end

------------------------------------------------------------------------
-- Touch handling
------------------------------------------------------------------------

local function onTouched(pad, hit, fromTag)
	local char = hit:FindFirstAncestorOfClass("Model")
	if not char then return end
	if not char:FindFirstChildOfClass("Humanoid") then return end
	local player = Players:GetPlayerFromCharacter(char)
	if not player then return end

	local now = os.clock()
	local last = lastTeleport[player]
	if last and now - last < DEBOUNCE then return end

	local dest
	if fromTag == BASE_TAG then
		dest = findMazeTeleport()
		if not dest then
			warn(("[BaseTeleport] %s touched BaseTeleport but no MazeTeleport found in Workspace"):format(player.Name))
			return
		end
	elseif fromTag == MAZE_TAG then
		dest = findOwnerBaseTeleport(player)
		if not dest then
			warn(("[BaseTeleport] %s touched MazeTeleport but their base/BaseTeleport not found"):format(player.Name))
			return
		end
	else
		return
	end

	lastTeleport[player] = now
	if teleportPlayer(player, dest) then
		print(("[BaseTeleport] %s: %s → %s"):format(
			player.Name, pad:GetFullName(), dest:GetFullName()
		))
	end
end

local function bindPad(pad, fromTag)
	if not pad:IsA("BasePart") then return end
	pad.Touched:Connect(function(hit) onTouched(pad, hit, fromTag) end)
end

------------------------------------------------------------------------
-- Wire up — existing tagged parts + future ones via signal
------------------------------------------------------------------------

for _, p in CollectionService:GetTagged(BASE_TAG) do bindPad(p, BASE_TAG) end
for _, p in CollectionService:GetTagged(MAZE_TAG) do bindPad(p, MAZE_TAG) end

CollectionService:GetInstanceAddedSignal(BASE_TAG):Connect(function(p) bindPad(p, BASE_TAG) end)
CollectionService:GetInstanceAddedSignal(MAZE_TAG):Connect(function(p) bindPad(p, MAZE_TAG) end)

Players.PlayerRemoving:Connect(function(p) lastTeleport[p] = nil end)

print(("[BaseTeleport] ready (BaseTeleport=%d, MazeTeleport=%d, debounce=%ds)"):format(
	#CollectionService:GetTagged(BASE_TAG),
	#CollectionService:GetTagged(MAZE_TAG),
	DEBOUNCE
))
