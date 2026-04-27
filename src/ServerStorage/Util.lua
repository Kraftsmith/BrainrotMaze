-- Util (ModuleScript in ServerStorage)
-- Shared helpers for server scripts.

local Util = {}

-- Names of top-level areas to detect player location
local NAMED_AREAS = {
	"common maze", "Rare Maze", "Epic Maze", "Legendary maze",
	"Rainbow maze", "secret maze (soon)", "lobby maze",
	"bazapl1", "bazapl2", "bazapl3", "bazapl4",
}

-- Cached list of spawn platforms (they live inside Workspace.Model, expensive to scan repeatedly)
local spawnPlatformsCache = nil
local function getSpawnPlatforms()
	if spawnPlatformsCache then return spawnPlatformsCache end
	spawnPlatformsCache = {}
	for _, d in workspace:GetDescendants() do
		if d:IsA("Model") and d.Name:lower():find("spawn platform") then
			table.insert(spawnPlatformsCache, d)
		end
	end
	return spawnPlatformsCache
end

local function isInsideXZ(pos, cf, size)
	local diff = pos - cf.Position
	return math.abs(diff.X) < size.X/2 and math.abs(diff.Z) < size.Z/2
end

-- Returns string "<zoneName> @ (X, Y, Z)" describing where the player is.
-- If player has no character or no zone match, returns just coords or status.
function Util.locationOf(player)
	if not player then return "no-player" end
	local char = player.Character
	if not char then return "no-character" end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return "no-hrp" end

	local pos = hrp.Position
	local posStr = string.format("(%.0f, %.0f, %.0f)", pos.X, pos.Y, pos.Z)

	local zone = nil
	for _, name in NAMED_AREAS do
		local m = workspace:FindFirstChild(name)
		if m and m:IsA("Model") then
			local cf, size = m:GetBoundingBox()
			if isInsideXZ(pos, cf, size) then
				zone = name
				break
			end
		end
	end

	if not zone then
		for _, plat in getSpawnPlatforms() do
			if plat.Parent then
				local cf, size = plat:GetBoundingBox()
				if isInsideXZ(pos, cf, size) then
					zone = plat.Name
					break
				end
			end
		end
	end

	return zone and (zone .. " @ " .. posStr) or posStr
end

return Util
