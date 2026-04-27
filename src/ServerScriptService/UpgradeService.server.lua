-- UpgradeService (Script in ServerScriptService)
-- Applies upgrade effects to player + base on join/spawn/upgrade.
-- For testing without Shop UI: chat commands `/upgrade speed`, `/upgrade carry`, `/upgrade base`.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerData = require(ServerStorage:WaitForChild("PlayerData"))
local UpgradeConfig = require(ReplicatedStorage:WaitForChild("UpgradeConfig"))

-- Lazy-create RemoteEvent for client purchase requests
local purchaseEvent = ReplicatedStorage:FindFirstChild("PurchaseUpgrade")
if not purchaseEvent then
	purchaseEvent = Instance.new("RemoteEvent")
	purchaseEvent.Name = "PurchaseUpgrade"
	purchaseEvent.Parent = ReplicatedStorage
end

local BASE_NAMES = {"bazapl1", "bazapl2", "bazapl3", "bazapl4"}

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

local function findPlayerBase(player)
	for _, name in BASE_NAMES do
		local base = workspace:FindFirstChild(name)
		if base and base:GetAttribute("Owner") == player.Name then
			return base
		end
	end
	return nil
end

local function applySpeed(player)
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local lvl = PlayerData.getValue(player, "speedLvl")
	local speed = UpgradeConfig.getEffect("speed", lvl) or 16
	hum.WalkSpeed = speed
end

local function applyBaseCapacity(player)
	local base = findPlayerBase(player)
	if not base then return end
	local lvl = PlayerData.getValue(player, "baseLvl")
	local cap = UpgradeConfig.getEffect("baseCap", lvl) or 4
	base:SetAttribute("Capacity", cap)
end

-- Sync PlayerData levels to player attributes (so client UI sees them)
local function syncAttributes(player)
	player:SetAttribute("speedLvl", PlayerData.getValue(player, "speedLvl"))
	player:SetAttribute("carryLvl", PlayerData.getValue(player, "carryLvl"))
	player:SetAttribute("baseLvl", PlayerData.getValue(player, "baseLvl"))
end

local function applyAll(player)
	applySpeed(player)
	applyBaseCapacity(player)
	syncAttributes(player)
end

------------------------------------------------------------------------
-- Upgrade purchase
-- track: "speed" | "carry" | "baseCap"
------------------------------------------------------------------------

local function tryUpgrade(player, track)
	local key
	if track == "speed" then key = "speedLvl"
	elseif track == "carry" then key = "carryLvl"
	elseif track == "baseCap" then key = "baseLvl"
	else return false, "unknown track" end

	local current = PlayerData.getValue(player, key)
	local nextLvl = current + 1
	if nextLvl > UpgradeConfig.getMaxLevel(track) then
		return false, "max level"
	end
	local cost = UpgradeConfig.getCost(track, nextLvl)

	local ls = player:FindFirstChild("leaderstats")
	local coins = ls and ls:FindFirstChild("Coins")
	if not coins or coins.Value < cost then
		return false, ("not enough coins (%d / %d)"):format(coins and coins.Value or 0, cost)
	end

	coins.Value = coins.Value - cost
	PlayerData.setValue(player, key, nextLvl)
	applyAll(player)

	local newValue = UpgradeConfig.getEffect(track, nextLvl)
	print(("[UpgradeService] %s bought %s lvl %d (value=%s, cost=%d)"):format(
		player.Name, track, nextLvl, tostring(newValue), cost
	))
	return true, nextLvl
end

------------------------------------------------------------------------
-- Player lifecycle
------------------------------------------------------------------------

local function setupCharacter(player, char)
	char:WaitForChild("Humanoid", 10)
	applySpeed(player)
end

local function setupPlayer(player)
	syncAttributes(player) -- initial set so client UI has values immediately

	-- Apply speed to current character if exists
	if player.Character then
		setupCharacter(player, player.Character)
	end
	player.CharacterAdded:Connect(function(c) setupCharacter(player, c) end)

	-- Wait briefly for BaseManager to assign base, then apply capacity
	task.spawn(function()
		for _ = 1, 10 do
			if findPlayerBase(player) then
				applyBaseCapacity(player)
				return
			end
			task.wait(0.5)
		end
		warn(("[UpgradeService] %s no base assigned after 5s"):format(player.Name))
	end)
end

Players.PlayerAdded:Connect(setupPlayer)
for _, p in Players:GetPlayers() do task.spawn(setupPlayer, p) end

------------------------------------------------------------------------
-- Test chat commands (for use until Shop UI exists)
------------------------------------------------------------------------

local function bindChat(player)
	player.Chatted:Connect(function(msg)
		local track = msg:match("^/upgrade%s+(%w+)")
		if not track then return end
		track = track:lower()
		if track == "base" then track = "baseCap" end
		local ok, result = tryUpgrade(player, track)
		if not ok then
			print(("[UpgradeService] %s /upgrade %s FAILED: %s"):format(player.Name, track, tostring(result)))
		end
	end)
end

Players.PlayerAdded:Connect(bindChat)
for _, p in Players:GetPlayers() do bindChat(p) end

------------------------------------------------------------------------
-- Client purchase requests
------------------------------------------------------------------------

purchaseEvent.OnServerEvent:Connect(function(player, track)
	if type(track) ~= "string" then return end
	track = track:lower()
	if track == "base" then track = "baseCap" end
	if track ~= "speed" and track ~= "carry" and track ~= "baseCap" then return end
	tryUpgrade(player, track)
end)

print("[UpgradeService] ready (chat /upgrade <track> + Shop UI via PurchaseUpgrade RemoteEvent)")
