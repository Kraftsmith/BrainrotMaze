-- VipService (Script in ServerScriptService)
-- Spec: Game Design/Base.md § VIP Base
--
-- Проверяет владение VIP GamePass на каждом заходе. Сохраняет результат в атрибутах:
--   player.VipBase = bool  — для UI и чек-логики.
--   base.Vip       = bool  — для BaseSwap (выбор vipbase{lvl}) и BrainrotDelivery (×2 income).
--
-- Также пропагирует Vip на базу, когда BaseManager проставляет Owner.
-- Чат-команда `/vip on|off` — тестовая, для проверки визуала и бонуса без реальной покупки.

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local PlayerData = require(ServerStorage:WaitForChild("PlayerData"))

-- TODO: заменить на реальный ID из Roblox Creator Hub после создания GamePass за 67 R$.
-- Пока 0 — pcall к UserOwnsGamePassAsync возвращает false, никто не получает VIP автоматически.
-- Тестировать можно через `/vip on` в чате.
local VIP_GAMEPASS_ID = 0

local BASE_NAMES = {"bazapl1", "bazapl2", "bazapl3", "bazapl4"}

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

local function setVip(player, owns)
	player:SetAttribute("VipBase", owns)
	local base = PlayerData.getBase(player)
	if base then
		base:SetAttribute("Vip", owns)
	end
	print(("[VipService] %s VipBase=%s%s"):format(
		player.Name, tostring(owns), base and (" → "..base.Name) or " (no base yet)"
	))
end

local function checkOwnership(player)
	if VIP_GAMEPASS_ID <= 0 then return false end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, VIP_GAMEPASS_ID)
	end)
	if not ok then
		warn(("[VipService] UserOwnsGamePassAsync failed for %s: %s"):format(player.Name, tostring(owns)))
		return false
	end
	return owns == true
end

------------------------------------------------------------------------
-- Player lifecycle
------------------------------------------------------------------------

local function onPlayerAdded(player)
	local owns = checkOwnership(player)
	setVip(player, owns)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in Players:GetPlayers() do task.spawn(onPlayerAdded, p) end

------------------------------------------------------------------------
-- Base ownership change → propagate Vip attribute
-- (BaseManager выставляет Owner; мы реагируем и копируем VipBase игрока на базу.)
------------------------------------------------------------------------

local function bindBase(base)
	base:GetAttributeChangedSignal("Owner"):Connect(function()
		local ownerName = base:GetAttribute("Owner")
		if not ownerName or ownerName == "" then
			base:SetAttribute("Vip", false)
			return
		end
		local owner = Players:FindFirstChild(ownerName)
		if owner then
			base:SetAttribute("Vip", owner:GetAttribute("VipBase") == true)
		end
	end)
end

for _, name in BASE_NAMES do
	local base = Workspace:FindFirstChild(name)
	if base then bindBase(base) end
end

------------------------------------------------------------------------
-- Mid-session GamePass purchase
------------------------------------------------------------------------

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
	if passId ~= VIP_GAMEPASS_ID then return end
	if wasPurchased then
		setVip(player, true)
		print(("[VipService] %s bought VIP GamePass mid-session"):format(player.Name))
	end
end)

------------------------------------------------------------------------
-- Test chat command: /vip on | /vip off
------------------------------------------------------------------------

local function bindChat(player)
	player.Chatted:Connect(function(msg)
		local arg = msg:match("^/vip%s+(%w+)")
		if not arg then return end
		arg = arg:lower()
		if arg == "on" then
			setVip(player, true)
		elseif arg == "off" then
			setVip(player, false)
		end
	end)
end

Players.PlayerAdded:Connect(bindChat)
for _, p in Players:GetPlayers() do bindChat(p) end

print(("[VipService] ready (gamepass id=%d)"):format(VIP_GAMEPASS_ID))
