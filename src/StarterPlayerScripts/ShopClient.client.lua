-- ShopClient (LocalScript in StarterPlayerScripts)
-- Toggleable shop UI for upgrades. Reads upgrade levels from player attributes
-- (synced by UpgradeService) and Coins from leaderstats.
-- On Buy click: fires PurchaseUpgrade RemoteEvent — server validates and applies.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local UpgradeConfig = require(ReplicatedStorage:WaitForChild("UpgradeConfig"))
local purchaseEvent = ReplicatedStorage:WaitForChild("PurchaseUpgrade")

local player = Players.LocalPlayer

local TRACKS = {
	{key = "speed",   levelAttr = "speedLvl", icon = "🏃", name = "Скорость"},
	{key = "carry",   levelAttr = "carryLvl", icon = "📦", name = "Переноска"},
	{key = "baseCap", levelAttr = "baseLvl",  icon = "🏠", name = "База"},
}

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
toggleBtn.Text = "🛒 Магазин [B]"
toggleBtn.Parent = screenGui

local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 6)
toggleCorner.Parent = toggleBtn

-- Main shop frame
local frame = Instance.new("Frame")
frame.Name = "ShopFrame"
frame.Size = UDim2.new(0, 420, 0, 380)
frame.Position = UDim2.new(0.5, -210, 0.5, -190)
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
title.Text = "🛒 МАГАЗИН АПГРЕЙДОВ"
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

		if lvl >= maxLvl then
			item.detail.Text = string.format("Уровень %d/%d (макс)\nЗначение: %s", lvl, maxLvl, tostring(currentValue))
			item.btn.Text = "МАКС"
			item.btn.BackgroundColor3 = Color3.fromRGB(80, 80, 90)
			item.btn.AutoButtonColor = false
			item.btn.Active = false
		else
			local nextValue = UpgradeConfig.getEffect(item.track.key, lvl + 1)
			local cost = UpgradeConfig.getCost(item.track.key, lvl + 1)
			item.detail.Text = string.format("lvl %d → %d\n%s → %s", lvl, lvl + 1, tostring(currentValue), tostring(nextValue))
			item.btn.Text = string.format("Купить\n💰 %d", cost)
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

print("[ShopClient] ready (toggle: button or [B])")
