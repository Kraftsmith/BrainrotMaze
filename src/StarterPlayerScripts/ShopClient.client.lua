-- ShopClient (LocalScript in StarterPlayerScripts)
-- Toggleable shop UI for upgrades. Reads upgrade levels from player attributes
-- (synced by UpgradeService) and Coins from leaderstats.
-- On Buy click: fires PurchaseUpgrade RemoteEvent — server validates and applies.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")

local UpgradeConfig = require(ReplicatedStorage:WaitForChild("UpgradeConfig"))
local purchaseEvent = ReplicatedStorage:WaitForChild("PurchaseUpgrade")

local player = Players.LocalPlayer

-- formatRow(lvl, maxLvl, currentValue, nextValue, cost) -> (detailText, buyBtnText)
-- Per-track display. baseCap отрисовывается как "купи слот", а не "купи уровень" —
-- семантика трека = +1 слот за покупку, см. Game Design/Base.md.
local function defaultFormat(_, _, currentValue, nextValue, cost, desc)
	return ("%s\nlvl: %s → %s"):format(desc, tostring(currentValue), tostring(nextValue)),
		("Buy\n💰 %d"):format(cost)
end

local function maxFormat(lvl, maxLvl, currentValue, _, _, desc)
	return ("%s\nLevel %d/%d (max) · Value: %s"):format(desc, lvl, maxLvl, tostring(currentValue)),
		"MAX"
end

local function slotsFormat(_, _, currentValue, _, cost, _)
	return ("Slots: %d / 30"):format(currentValue),
		("Buy +1 slot\n💰 %d"):format(cost)
end

local function slotsMaxFormat(_, _, currentValue, _, _, _)
	return ("Slots: %d / 30 (max)"):format(currentValue),
		"MAX"
end

local TRACKS = {
	{key = "speed",   levelAttr = "speedLvl", icon = "🏃", name = "Speed",     desc = "How fast your character moves",
		format = defaultFormat, maxFormat = maxFormat},
	{key = "carry",   levelAttr = "carryLvl", icon = "📦", name = "Max Carry", desc = "Brainrots you can carry at once",
		format = defaultFormat, maxFormat = maxFormat},
	{key = "baseCap", levelAttr = "baseLvl",  icon = "🏠", name = "Base Slots", desc = "+1 placement slot on your base",
		format = slotsFormat, maxFormat = slotsMaxFormat},
}

-- VIP GamePass — должен совпадать с VipService.VIP_GAMEPASS_ID на сервере.
-- TODO: заменить на реальный ID из Roblox Creator Hub.
local VIP_GAMEPASS_ID = 0
local VIP_PRICE_ROBUX = 67

------------------------------------------------------------------------
-- UI construction
------------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ShopGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

-- Toggle button (always visible)
local toggleBtn = Instance.new("TextButton")
toggleBtn.Name = "Toggle"
toggleBtn.Size = UDim2.new(0, 130, 0, 50)
toggleBtn.Position = UDim2.new(1, -140, 0, 100)
toggleBtn.BackgroundColor3 = Color3.fromRGB(60, 130, 220)
toggleBtn.BorderSizePixel = 0
toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = 18
toggleBtn.Text = "🛒 Shop [B]"
toggleBtn.Parent = screenGui

local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 6)
toggleCorner.Parent = toggleBtn

-- Main shop frame
local frame = Instance.new("Frame")
frame.Name = "ShopFrame"
frame.Size = UDim2.new(0, 420, 0, 470)
frame.Position = UDim2.new(0.5, -210, 0.5, -235)
frame.BackgroundColor3 = Color3.fromRGB(28, 30, 40)
frame.BorderSizePixel = 0
frame.Visible = false
frame.Parent = screenGui

local frameCorner = Instance.new("UICorner")
frameCorner.CornerRadius = UDim.new(0, 10)
frameCorner.Parent = frame

local frameStroke = Instance.new("UIStroke")
frameStroke.Color = Color3.fromRGB(90, 90, 110)
frameStroke.Thickness = 2
frameStroke.Parent = frame

-- Header bar
local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 44)
header.BackgroundColor3 = Color3.fromRGB(60, 130, 220)
header.BorderSizePixel = 0
header.Parent = frame

local headerCorner = Instance.new("UICorner")
headerCorner.CornerRadius = UDim.new(0, 10)
headerCorner.Parent = header

-- Mask the bottom corners of header
local headerMask = Instance.new("Frame")
headerMask.Size = UDim2.new(1, 0, 0.5, 0)
headerMask.Position = UDim2.new(0, 0, 0.5, 0)
headerMask.BackgroundColor3 = header.BackgroundColor3
headerMask.BorderSizePixel = 0
headerMask.Parent = header

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 1, 0)
title.BackgroundTransparency = 1
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.Font = Enum.Font.GothamBold
title.TextSize = 22
title.Text = "🛒 UPGRADE SHOP"
title.Parent = header

local closeBtn = Instance.new("TextButton")
closeBtn.Name = "Close"
closeBtn.Size = UDim2.new(0, 36, 0, 36)
closeBtn.Position = UDim2.new(1, -42, 0, 4)
closeBtn.BackgroundTransparency = 1
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 24
closeBtn.Text = "✕"
closeBtn.Parent = header

-- Coins display
local coinsLabel = Instance.new("TextLabel")
coinsLabel.Name = "Coins"
coinsLabel.Size = UDim2.new(1, -20, 0, 30)
coinsLabel.Position = UDim2.new(0, 10, 0, 52)
coinsLabel.BackgroundTransparency = 1
coinsLabel.TextColor3 = Color3.fromRGB(255, 215, 60)
coinsLabel.Font = Enum.Font.GothamBold
coinsLabel.TextSize = 20
coinsLabel.TextXAlignment = Enum.TextXAlignment.Left
coinsLabel.Text = "💰 0"
coinsLabel.Parent = frame

-- Items container
local itemsContainer = Instance.new("Frame")
itemsContainer.Name = "Items"
itemsContainer.Size = UDim2.new(1, -20, 1, -100)
itemsContainer.Position = UDim2.new(0, 10, 0, 90)
itemsContainer.BackgroundTransparency = 1
itemsContainer.Parent = frame

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 8)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = itemsContainer

-- Build item rows
local itemRows = {}
for i, track in TRACKS do
	local row = Instance.new("Frame")
	row.Name = track.key
	row.LayoutOrder = i
	row.Size = UDim2.new(1, 0, 0, 80)
	row.BackgroundColor3 = Color3.fromRGB(45, 48, 60)
	row.BorderSizePixel = 0
	row.Parent = itemsContainer

	local rowCorner = Instance.new("UICorner")
	rowCorner.CornerRadius = UDim.new(0, 6)
	rowCorner.Parent = row

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(0.55, -10, 0, 28)
	nameLabel.Position = UDim2.new(0, 12, 0, 8)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 17
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Text = track.icon .. "  " .. track.name
	nameLabel.Parent = row

	local detailLabel = Instance.new("TextLabel")
	detailLabel.Name = "Detail"
	detailLabel.Size = UDim2.new(0.55, -10, 0, 36)
	detailLabel.Position = UDim2.new(0, 12, 0, 38)
	detailLabel.BackgroundTransparency = 1
	detailLabel.TextColor3 = Color3.fromRGB(180, 185, 200)
	detailLabel.Font = Enum.Font.Gotham
	detailLabel.TextSize = 13
	detailLabel.TextXAlignment = Enum.TextXAlignment.Left
	detailLabel.TextYAlignment = Enum.TextYAlignment.Top
	detailLabel.TextWrapped = true
	detailLabel.Text = "..."
	detailLabel.Parent = row

	local btn = Instance.new("TextButton")
	btn.Name = "Buy"
	btn.Size = UDim2.new(0.4, -10, 0, 60)
	btn.Position = UDim2.new(0.6, 0, 0.5, -30)
	btn.BackgroundColor3 = Color3.fromRGB(80, 200, 100)
	btn.BorderSizePixel = 0
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 14
	btn.Text = "..."
	btn.Parent = row

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 5)
	btnCorner.Parent = btn

	btn.MouseButton1Click:Connect(function()
		purchaseEvent:FireServer(track.key)
	end)

	itemRows[track.key] = {row = row, detail = detailLabel, btn = btn, track = track}
end

------------------------------------------------------------------------
-- VIP Base row (Robux GamePass — отдельная логика, не часть TRACKS)
------------------------------------------------------------------------

local vipRow = Instance.new("Frame")
vipRow.Name = "vipBase"
vipRow.LayoutOrder = 99 -- последний
vipRow.Size = UDim2.new(1, 0, 0, 80)
vipRow.BackgroundColor3 = Color3.fromRGB(60, 50, 30)
vipRow.BorderSizePixel = 0
vipRow.Parent = itemsContainer

local vipCorner = Instance.new("UICorner")
vipCorner.CornerRadius = UDim.new(0, 6)
vipCorner.Parent = vipRow

local vipStroke = Instance.new("UIStroke")
vipStroke.Color = Color3.fromRGB(255, 215, 60)
vipStroke.Thickness = 2
vipStroke.Parent = vipRow

local vipName = Instance.new("TextLabel")
vipName.Size = UDim2.new(0.55, -10, 0, 28)
vipName.Position = UDim2.new(0, 12, 0, 8)
vipName.BackgroundTransparency = 1
vipName.TextColor3 = Color3.fromRGB(255, 215, 60)
vipName.Font = Enum.Font.GothamBold
vipName.TextSize = 17
vipName.TextXAlignment = Enum.TextXAlignment.Left
vipName.Text = "👑  VIP Base"
vipName.Parent = vipRow

local vipDetail = Instance.new("TextLabel")
vipDetail.Size = UDim2.new(0.55, -10, 0, 36)
vipDetail.Position = UDim2.new(0, 12, 0, 38)
vipDetail.BackgroundTransparency = 1
vipDetail.TextColor3 = Color3.fromRGB(220, 200, 150)
vipDetail.Font = Enum.Font.Gotham
vipDetail.TextSize = 12
vipDetail.TextXAlignment = Enum.TextXAlignment.Left
vipDetail.TextYAlignment = Enum.TextYAlignment.Top
vipDetail.TextWrapped = true
vipDetail.Text = "Custom base visual + ×2 income from all brainrots"
vipDetail.Parent = vipRow

local vipBtn = Instance.new("TextButton")
vipBtn.Name = "Buy"
vipBtn.Size = UDim2.new(0.4, -10, 0, 60)
vipBtn.Position = UDim2.new(0.6, 0, 0.5, -30)
vipBtn.BackgroundColor3 = Color3.fromRGB(220, 170, 40)
vipBtn.BorderSizePixel = 0
vipBtn.TextColor3 = Color3.fromRGB(40, 30, 10)
vipBtn.Font = Enum.Font.GothamBold
vipBtn.TextSize = 14
vipBtn.Text = "..."
vipBtn.Parent = vipRow

local vipBtnCorner = Instance.new("UICorner")
vipBtnCorner.CornerRadius = UDim.new(0, 5)
vipBtnCorner.Parent = vipBtn

vipBtn.MouseButton1Click:Connect(function()
	if player:GetAttribute("VipBase") then return end -- уже куплено
	if VIP_GAMEPASS_ID <= 0 then
		warn("[ShopClient] VIP_GAMEPASS_ID не настроен — обнови константу после создания GamePass")
		return
	end
	MarketplaceService:PromptGamePassPurchase(player, VIP_GAMEPASS_ID)
end)

------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------

local function getCoins()
	local ls = player:FindFirstChild("leaderstats")
	local coins = ls and ls:FindFirstChild("Coins")
	return coins and coins.Value or 0
end

local function refresh()
	local coinsValue = getCoins()
	coinsLabel.Text = string.format("💰 %d", coinsValue)

	for _, item in itemRows do
		local lvl = player:GetAttribute(item.track.levelAttr) or 1
		local maxLvl = UpgradeConfig.getMaxLevel(item.track.key)
		local currentValue = UpgradeConfig.getEffect(item.track.key, lvl)

		local desc = item.track.desc or ""
		if lvl >= maxLvl then
			item.detail.Text, item.btn.Text = item.track.maxFormat(lvl, maxLvl, currentValue, nil, nil, desc)
			item.btn.BackgroundColor3 = Color3.fromRGB(80, 80, 90)
			item.btn.AutoButtonColor = false
			item.btn.Active = false
		else
			local nextValue = UpgradeConfig.getEffect(item.track.key, lvl + 1)
			local cost = UpgradeConfig.getCost(item.track.key, lvl + 1)
			item.detail.Text, item.btn.Text = item.track.format(lvl, maxLvl, currentValue, nextValue, cost, desc)
			item.btn.Active = true
			if coinsValue >= cost then
				item.btn.BackgroundColor3 = Color3.fromRGB(80, 200, 100)
				item.btn.AutoButtonColor = true
			else
				item.btn.BackgroundColor3 = Color3.fromRGB(150, 80, 80)
				item.btn.AutoButtonColor = false
			end
		end
	end

	-- VIP row
	if player:GetAttribute("VipBase") then
		vipBtn.Text = "✓ Active"
		vipBtn.BackgroundColor3 = Color3.fromRGB(140, 110, 30)
		vipBtn.AutoButtonColor = false
		vipBtn.Active = false
	else
		vipBtn.Text = string.format("Buy\nR$ %d", VIP_PRICE_ROBUX)
		vipBtn.BackgroundColor3 = Color3.fromRGB(220, 170, 40)
		vipBtn.AutoButtonColor = true
		vipBtn.Active = true
	end
end

------------------------------------------------------------------------
-- Open / close + live updates
------------------------------------------------------------------------

local function setOpen(open)
	frame.Visible = open
	if open then refresh() end
end

toggleBtn.MouseButton1Click:Connect(function() setOpen(not frame.Visible) end)
closeBtn.MouseButton1Click:Connect(function() setOpen(false) end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.B then
		setOpen(not frame.Visible)
	end
end)

-- Live refresh on coin change + level change
local function watchCoins()
	local ls = player:FindFirstChild("leaderstats")
	local coins = ls and ls:FindFirstChild("Coins")
	if coins then
		coins:GetPropertyChangedSignal("Value"):Connect(function()
			if frame.Visible then refresh() end
		end)
	end
end
watchCoins()
player.ChildAdded:Connect(function(c)
	if c.Name == "leaderstats" then
		c.ChildAdded:Connect(function(c2)
			if c2.Name == "Coins" then watchCoins() end
		end)
	end
end)

for _, t in TRACKS do
	player:GetAttributeChangedSignal(t.levelAttr):Connect(function()
		if frame.Visible then refresh() end
	end)
end

-- VIP attribute changes (после покупки GamePass или /vip on|off)
player:GetAttributeChangedSignal("VipBase"):Connect(function()
	if frame.Visible then refresh() end
end)

print("[ShopClient] ready (toggle: button or [B])")
