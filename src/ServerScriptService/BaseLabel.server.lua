-- BaseLabel (Script in ServerScriptService)
-- Spec: Game Design/Base.md § Визуальное различение баз
--
-- Над каждой базой висит BillboardGui с DisplayName владельца, окрашенный
-- в персональный цвет (детерминированно по UserId, с разрешением коллизий
-- среди активных баз — у разных игроков на сессии цвета не совпадают).
-- Метка следует за атрибутом `Owner`, а не за номером базы. Без Owner — скрыта.
--
-- Привязка: BaseManager (в Studio, не на диске) выставляет base.Owner —
-- мы реагируем через GetAttributeChangedSignal, как и VipService.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local BASE_NAMES = {"bazapl1", "bazapl2", "bazapl3", "bazapl4"}

-- 8 ярких различимых цветов — комфортный запас при 4 одновременных слотах.
local PALETTE = {
	Color3.fromRGB(255, 89, 89),   -- red
	Color3.fromRGB(89, 191, 255),  -- cyan
	Color3.fromRGB(89, 255, 119),  -- green
	Color3.fromRGB(255, 219, 89),  -- yellow
	Color3.fromRGB(214, 89, 255),  -- magenta
	Color3.fromRGB(255, 153, 51),  -- orange
	Color3.fromRGB(89, 255, 224),  -- teal
	Color3.fromRGB(255, 130, 200), -- pink
}

local LABEL_HEIGHT_OFFSET = 12  -- studs над верхним краем bbox базы
local MAX_VIEW_DISTANCE = 600   -- ~ размер карты
local LABEL_SIZE = UDim2.new(0, 220, 0, 60)

------------------------------------------------------------------------
-- Color assignment
------------------------------------------------------------------------

-- base -> Color3 of current owner (для разрешения коллизий между базами)
local baseColor = {}

local function colorKey(c)
	return string.format("%d,%d,%d", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local function pickColorFor(player, baseExcluded)
	local taken = {}
	for b, c in pairs(baseColor) do
		if b ~= baseExcluded and c then
			taken[colorKey(c)] = true
		end
	end
	local startIdx = (player.UserId % #PALETTE) + 1
	for i = 0, #PALETTE - 1 do
		local idx = ((startIdx - 1 + i) % #PALETTE) + 1
		local c = PALETTE[idx]
		if not taken[colorKey(c)] then
			return c
		end
	end
	-- Все цвета заняты (5+ баз) — отдаём хешированный slot.
	return PALETTE[startIdx]
end

------------------------------------------------------------------------
-- GUI scaffolding
------------------------------------------------------------------------

local function getOrMakeAnchor(base)
	local a = base:FindFirstChild("BaseLabelAnchor")
	if a then return a end
	a = Instance.new("Part")
	a.Name = "BaseLabelAnchor"
	a.Size = Vector3.new(0.5, 0.5, 0.5)
	a.Transparency = 1
	a.CanCollide = false
	a.CanQuery = false
	a.CanTouch = false
	a.Anchored = true
	a.Massless = true
	a.Parent = base
	return a
end

local function getOrMakeGui(anchor)
	local gui = anchor:FindFirstChild("BaseLabelGui")
	if gui then return gui, gui:FindFirstChildOfClass("TextLabel") end
	gui = Instance.new("BillboardGui")
	gui.Name = "BaseLabelGui"
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Size = LABEL_SIZE
	gui.MaxDistance = MAX_VIEW_DISTANCE
	gui.Adornee = anchor
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Name = "Name"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextStrokeTransparency = 0.3
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.Parent = gui
	return gui, label
end

-- Top Y of base, ignoring our own anchor (иначе anchor дрейфует вверх при каждом
-- вызове, потому что попадает в собственный bbox).
local function topYOfBase(base, anchor)
	local topY = -math.huge
	for _, p in ipairs(base:GetDescendants()) do
		if p:IsA("BasePart") and p ~= anchor then
			local y = p.Position.Y + p.Size.Y / 2
			if y > topY then topY = y end
		end
	end
	return topY
end

local function repositionAnchor(base, anchor)
	local topY = topYOfBase(base, anchor)
	if topY == -math.huge then return end
	local x, z
	local spawnPoint = base:FindFirstChild("SpawnPoint")
	if spawnPoint and spawnPoint:IsA("BasePart") then
		x, z = spawnPoint.Position.X, spawnPoint.Position.Z
	else
		local pivot = base:GetPivot().Position
		x, z = pivot.X, pivot.Z
	end
	anchor.CFrame = CFrame.new(x, topY + LABEL_HEIGHT_OFFSET, z)
end

------------------------------------------------------------------------
-- Update
------------------------------------------------------------------------

local function updateLabel(base)
	local anchor = getOrMakeAnchor(base)
	local gui, label = getOrMakeGui(anchor)
	repositionAnchor(base, anchor)

	local ownerName = base:GetAttribute("Owner")
	if not ownerName or ownerName == "" then
		baseColor[base] = nil
		gui.Enabled = false
		label.Text = ""
		return
	end

	local player = Players:FindFirstChild(ownerName)
	if not player then
		-- Owner назначен, но игрока ещё/уже нет в Players (теоретически между PlayerRemoving и обнулением Owner).
		baseColor[base] = nil
		gui.Enabled = false
		return
	end

	local color = pickColorFor(player, base)
	baseColor[base] = color
	label.Text = player.DisplayName
	label.TextColor3 = color
	gui.Enabled = true
end

------------------------------------------------------------------------
-- Wire up
------------------------------------------------------------------------

for _, name in ipairs(BASE_NAMES) do
	local base = Workspace:FindFirstChild(name)
	if not base then
		warn(("[BaseLabel] base not found: %s"):format(name))
	else
		updateLabel(base)
		base:GetAttributeChangedSignal("Owner"):Connect(function()
			updateLabel(base)
		end)
		base:GetAttributeChangedSignal("Capacity"):Connect(function()
			-- BaseSwap слушает тот же сигнал и подменяет Visual — defer чтобы наш
			-- reposition увидел уже новый bbox базы.
			task.defer(function()
				local anchor = base:FindFirstChild("BaseLabelAnchor")
				if anchor then repositionAnchor(base, anchor) end
			end)
		end)
		print(("[BaseLabel] bound %s"):format(name))
	end
end

print("[BaseLabel] ready")
