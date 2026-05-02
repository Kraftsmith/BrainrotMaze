-- InventoryClient (LocalScript in StarterPlayerScripts)
-- Spec: Game Design/Inventory.md, Tasks/Inventory.md.
-- Показывает placed-брейнротов на базе игрока: группировка по rarity, count + per-row income,
-- шапка <placed>/<capacity> slots · +<sum>/sec total.
--
-- Источник данных — теги PlacedBrainrot и атрибуты на моделях/базе. Никаких RemoteEvent'ов.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")

local BrainrotConfig = require(ReplicatedStorage:WaitForChild("BrainrotConfig"))

local PLACED_TAG = "PlacedBrainrot"
local BASE_NAMES = {"bazapl1", "bazapl2", "bazapl3", "bazapl4"}

local player = Players.LocalPlayer

------------------------------------------------------------------------
-- UI construction
------------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "InventoryGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

-- Toggle button (Y=160 → под Shop'ом, который на Y=100)
local toggleBtn = Instance.new("TextButton")
toggleBtn.Name = "Toggle"
toggleBtn.Size = UDim2.new(0, 130, 0, 50)
toggleBtn.Position = UDim2.new(1, -140, 0, 160)
toggleBtn.BackgroundColor3 = Color3.fromRGB(80, 130, 200)
toggleBtn.BorderSizePixel = 0
toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = 18
toggleBtn.Text = "🗂 Inventory [I]"
toggleBtn.Parent = screenGui

local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 6)
toggleCorner.Parent = toggleBtn

-- Main frame
local frame = Instance.new("Frame")
frame.Name = "InventoryFrame"
frame.Size = UDim2.new(0, 420, 0, 500)
frame.Position = UDim2.new(0.5, -210, 0.5, -250)
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

-- Header
local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 44)
header.BackgroundColor3 = Color3.fromRGB(80, 130, 200)
header.BorderSizePixel = 0
header.Parent = frame

local headerCorner = Instance.new("UICorner")
headerCorner.CornerRadius = UDim.new(0, 10)
headerCorner.Parent = header

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
title.Text = "🗂 INVENTORY"
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

-- Summary line
local summaryLabel = Instance.new("TextLabel")
summaryLabel.Name = "Summary"
summaryLabel.Size = UDim2.new(1, -20, 0, 26)
summaryLabel.Position = UDim2.new(0, 10, 0, 52)
summaryLabel.BackgroundTransparency = 1
summaryLabel.TextColor3 = Color3.fromRGB(220, 220, 235)
summaryLabel.Font = Enum.Font.GothamBold
summaryLabel.TextSize = 16
summaryLabel.TextXAlignment = Enum.TextXAlignment.Left
summaryLabel.Text = "0 / ?? slots · +0/sec total"
summaryLabel.Parent = frame

-- Empty-state label (shown when 0 placed)
local emptyLabel = Instance.new("TextLabel")
emptyLabel.Name = "Empty"
emptyLabel.Size = UDim2.new(1, -20, 0, 80)
emptyLabel.Position = UDim2.new(0, 10, 0.5, -40)
emptyLabel.BackgroundTransparency = 1
emptyLabel.TextColor3 = Color3.fromRGB(160, 160, 180)
emptyLabel.Font = Enum.Font.Gotham
emptyLabel.TextSize = 16
emptyLabel.Text = "Empty.\nPlace a brainrot to start earning."
emptyLabel.TextWrapped = true
emptyLabel.Visible = false
emptyLabel.Parent = frame

-- Items scroll container
local itemsContainer = Instance.new("ScrollingFrame")
itemsContainer.Name = "Items"
itemsContainer.Size = UDim2.new(1, -20, 1, -100)
itemsContainer.Position = UDim2.new(0, 10, 0, 90)
itemsContainer.BackgroundTransparency = 1
itemsContainer.BorderSizePixel = 0
itemsContainer.ScrollBarThickness = 6
itemsContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
itemsContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y
itemsContainer.Parent = frame

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = itemsContainer

------------------------------------------------------------------------
-- Own base resolution + per-base subscriptions
------------------------------------------------------------------------

local ownBase = nil
local baseConnections = {} -- attribute-changed connections on current ownBase

local function findOwnBase()
	for _, name in BASE_NAMES do
		local b = workspace:FindFirstChild(name)
		if b and b:GetAttribute("Owner") == player.Name then
			return b
		end
	end
	return nil
end

------------------------------------------------------------------------
-- Snapshot collection
------------------------------------------------------------------------

local function vipMulFor(base)
	if base and base:GetAttribute("Vip") == true then return 2 end
	return 1
end

local function collectInventory()
	local capacity = ownBase and ownBase:GetAttribute("Capacity") or nil
	local mul = vipMulFor(ownBase)

	-- key = name → {name, rarity, perItem, count}
	local byName = {}
	local placedCount = 0
	local totalIncome = 0

	for _, m in CollectionService:GetTagged(PLACED_TAG) do
		if m:IsA("Model") and m.Parent and m:GetAttribute("PlacedBy") == player.Name then
			placedCount += 1
			local nm = m.Name
			local entry = byName[nm]
			if not entry then
				local perItem = BrainrotConfig.getIncome(m) * mul
				entry = {
					name = nm,
					rarity = m:GetAttribute("Rarity") or BrainrotConfig.defaultRarity,
					perItem = perItem,
					count = 0,
				}
				byName[nm] = entry
			end
			entry.count += 1
			totalIncome += entry.perItem
		end
	end

	-- group by rarity
	local groups = {}
	for _, entry in byName do
		local g = groups[entry.rarity]
		if not g then
			g = {totalIncome = 0, items = {}}
			groups[entry.rarity] = g
		end
		table.insert(g.items, entry)
		g.totalIncome += entry.perItem * entry.count
	end

	return {
		capacity = capacity,
		placed = placedCount,
		totalIncome = totalIncome,
		groups = groups,
	}
end

------------------------------------------------------------------------
-- Render
------------------------------------------------------------------------

local function clearItems()
	for _, child in itemsContainer:GetChildren() do
		if child ~= layout then child:Destroy() end
	end
end

local function makeGroupHeader(rarity, layoutOrder)
	local row = Instance.new("Frame")
	row.Name = "GroupHeader_" .. rarity
	row.LayoutOrder = layoutOrder
	row.Size = UDim2.new(1, 0, 0, 28)
	row.BackgroundColor3 = BrainrotConfig.rarityColor[rarity] or Color3.fromRGB(120, 120, 130)
	row.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = row

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -16, 1, 0)
	label.Position = UDim2.new(0, 10, 0, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(20, 20, 30)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = string.upper(rarity)
	label.Parent = row

	row.Parent = itemsContainer
	return row
end

local function makeItemRow(entry, layoutOrder)
	local row = Instance.new("Frame")
	row.Name = "Item_" .. entry.name
	row.LayoutOrder = layoutOrder
	row.Size = UDim2.new(1, 0, 0, 32)
	row.BackgroundColor3 = Color3.fromRGB(45, 48, 60)
	row.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = row

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(0.55, -10, 1, 0)
	nameLabel.Position = UDim2.new(0, 12, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextColor3 = Color3.fromRGB(235, 235, 245)
	nameLabel.Font = Enum.Font.Gotham
	nameLabel.TextSize = 14
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Text = entry.name
	nameLabel.Parent = row

	local countLabel = Instance.new("TextLabel")
	countLabel.Size = UDim2.new(0.15, 0, 1, 0)
	countLabel.Position = UDim2.new(0.55, 0, 0, 0)
	countLabel.BackgroundTransparency = 1
	countLabel.TextColor3 = Color3.fromRGB(200, 200, 215)
	countLabel.Font = Enum.Font.GothamBold
	countLabel.TextSize = 14
	countLabel.Text = ("× %d"):format(entry.count)
	countLabel.Parent = row

	local incomeLabel = Instance.new("TextLabel")
	incomeLabel.Size = UDim2.new(0.3, -8, 1, 0)
	incomeLabel.Position = UDim2.new(0.7, 0, 0, 0)
	incomeLabel.BackgroundTransparency = 1
	incomeLabel.TextColor3 = Color3.fromRGB(255, 215, 60)
	incomeLabel.Font = Enum.Font.GothamBold
	incomeLabel.TextSize = 14
	incomeLabel.TextXAlignment = Enum.TextXAlignment.Right
	incomeLabel.Text = ("+%d/s"):format(entry.perItem * entry.count)
	incomeLabel.Parent = row

	row.Parent = itemsContainer
	return row
end

local function render()
	local snap = collectInventory()

	local capStr = snap.capacity and tostring(snap.capacity) or "??"
	summaryLabel.Text = ("%d / %s slots · +%d/sec total"):format(snap.placed, capStr, snap.totalIncome)

	clearItems()

	if snap.placed == 0 then
		emptyLabel.Visible = true
		itemsContainer.Visible = false
		return
	end

	emptyLabel.Visible = false
	itemsContainer.Visible = true

	local order = 0
	for _, rarity in BrainrotConfig.rarityOrder do
		local g = snap.groups[rarity]
		if g and #g.items > 0 then
			order += 1
			makeGroupHeader(rarity, order)

			-- sort within group: perItem desc, then name asc
			table.sort(g.items, function(a, b)
				if a.perItem ~= b.perItem then return a.perItem > b.perItem end
				return a.name < b.name
			end)

			for _, entry in g.items do
				order += 1
				makeItemRow(entry, order)
			end
		end
	end
end

------------------------------------------------------------------------
-- Debounced scheduler + subscriptions
------------------------------------------------------------------------

local pendingRender = false
local function scheduleRender()
	if pendingRender or not frame.Visible then return end
	pendingRender = true
	task.defer(function()
		pendingRender = false
		if frame.Visible then render() end
	end)
end

local function detachBaseConnections()
	for _, c in baseConnections do c:Disconnect() end
	table.clear(baseConnections)
end

local function attachBaseConnections(base)
	if not base then return end
	table.insert(baseConnections, base:GetAttributeChangedSignal("Capacity"):Connect(scheduleRender))
	table.insert(baseConnections, base:GetAttributeChangedSignal("Vip"):Connect(scheduleRender))
end

local function refreshOwnBase()
	local newBase = findOwnBase()
	if newBase ~= ownBase then
		detachBaseConnections()
		ownBase = newBase
		attachBaseConnections(ownBase)
	end
	scheduleRender()
end

-- Owner attribute changes on every bazapl_ — refresh kept ref + render
for _, name in BASE_NAMES do
	local b = workspace:FindFirstChild(name)
	if b then
		b:GetAttributeChangedSignal("Owner"):Connect(refreshOwnBase)
	end
end
-- Workspace-level: бази в .rbxl (могут появиться позже если кто-то перепарентит)
workspace.ChildAdded:Connect(function(child)
	if table.find(BASE_NAMES, child.Name) then
		child:GetAttributeChangedSignal("Owner"):Connect(refreshOwnBase)
		refreshOwnBase()
	end
end)

-- Tag add/remove on PlacedBrainrot — render
CollectionService:GetInstanceAddedSignal(PLACED_TAG):Connect(scheduleRender)
CollectionService:GetInstanceRemovedSignal(PLACED_TAG):Connect(scheduleRender)

------------------------------------------------------------------------
-- Open / close
------------------------------------------------------------------------

local function setOpen(open)
	frame.Visible = open
	if open then
		refreshOwnBase() -- resolve base + immediate render
		render()
	end
end

toggleBtn.MouseButton1Click:Connect(function() setOpen(not frame.Visible) end)
closeBtn.MouseButton1Click:Connect(function() setOpen(false) end)

-- ContextActionService вместо UserInputService: не страдает от processed-флага, когда
-- какой-то UI получил фокус, и сам решает приоритет ввода.
ContextActionService:BindAction(
	"ToggleInventory",
	function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			setOpen(not frame.Visible)
		end
		return Enum.ContextActionResult.Pass
	end,
	false, -- не создавать кнопку для тач-устройств (toggleBtn уже есть)
	Enum.KeyCode.I
)

-- Initial resolve (но не рендер — frame.Visible=false, scheduleRender no-op)
ownBase = findOwnBase()
attachBaseConnections(ownBase)

print("[InventoryClient] ready (toggle: button or [I])")
