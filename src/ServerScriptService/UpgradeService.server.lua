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

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

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
	local base = PlayerData.getBase(player)
	if not base then return end
	local lvl = PlayerData.getValue(player, "baseLvl")
	local cap = UpgradeConfig.getEffect("baseCap", lvl) or 10
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
	-- Гейт покупок до загрузки профиля (см. SaveService): защищает от трат на дефолтных коинах,
	-- которые позже затёрлись бы загруженным профилем.
	if not player:GetAttribute("ProfileLoaded") then
		return false, "profile not loaded"
	end

	local key
	if track == "speed" then key = "speedLvl"
	elseif track == "carry" then key = "carryLvl"
	elseif track == "baseCap" then key = "baseLvl"
	else return false, "unknown track" end

	local maxLvl = UpgradeConfig.getMaxLevel(track)

	-- Атомарно: проверка лимита, баланса, списание + повышение уровня. Мутатор возвращает
	-- (ok, nextLvl|errMsg, cost). Если ok=false — поля профиля не меняются (мы их не трогали).
	local ok, resultOrErr, cost = PlayerData.update(player, function(p)
		local nextLvl = p[key] + 1
		if nextLvl > maxLvl then return false, "max level" end
		local price = UpgradeConfig.getCost(track, nextLvl)
		if p.coins < price then
			return false, ("not enough coins (%d / %d)"):format(p.coins, price)
		end
		p.coins = p.coins - price
		p[key] = nextLvl
		return true, nextLvl, price
	end)

	if not ok then return false, resultOrErr end

	applyAll(player)

	local newValue = UpgradeConfig.getEffect(track, resultOrErr)
	print(("[UpgradeService] %s bought %s lvl %d (value=%s, cost=%d)"):format(
		player.Name, track, resultOrErr, tostring(newValue), cost
	))
	return true, resultOrErr
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
			if PlayerData.getBase(player) then
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

-- Re-apply effects when PlayerData changes (e.g., SaveService loaded profile, или /upgrade-команда).
PlayerData.Changed:Connect(function(player, key)
	if key == "speedLvl" then
		applySpeed(player)
		syncAttributes(player)
	elseif key == "baseLvl" then
		applyBaseCapacity(player)
		syncAttributes(player)
	elseif key == "carryLvl" then
		-- carry эффект читается на каждом пикапе (BrainrotPickup), отдельный apply не нужен
		syncAttributes(player)
	end
end)

------------------------------------------------------------------------
-- Test chat commands (for use until Shop UI exists)
------------------------------------------------------------------------

local function bindChat(player)
	player.Chatted:Connect(function(msg)
		local track = msg:match("^/upgrade%s+(%w+)")
		if not track then return end
		track = track:lower()
		if track == "base" or track == "basecap" then track = "baseCap" end
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
	if track == "base" or track == "basecap" then track = "baseCap" end
	if track ~= "speed" and track ~= "carry" and track ~= "baseCap" then return end
	tryUpgrade(player, track)
end)

print("[UpgradeService] ready (chat /upgrade <track> + Shop UI via PurchaseUpgrade RemoteEvent)")
