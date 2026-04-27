-- BrainrotDelivery (Script in ServerScriptService)
-- Player carrying a brainrot touches their own base -> brainrot is placed on the base.
-- Placed brainrots generate income per second (Rarity → income from BrainrotConfig).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")

local BrainrotState = require(ServerStorage:WaitForChild("BrainrotState"))
local BrainrotConfig = require(ReplicatedStorage:WaitForChild("BrainrotConfig"))
local Util = require(ServerStorage:WaitForChild("Util"))

local brainrotEvents = ServerStorage:WaitForChild("BrainrotEvents")
local evtPlaced = brainrotEvents:WaitForChild("Placed")

local BASE_NAMES = {"bazapl1", "bazapl2", "bazapl3", "bazapl4"}
local DEFAULT_CAPACITY = 4
local PLACED_TAG = "PlacedBrainrot"
local DELIVERY_DEBOUNCE = 0.5

-- per-base placed brainrots: [base] = { Model, Model, ... }
local placed = {}
-- per-player debounce timer
local lastDelivery = {}

------------------------------------------------------------------------
-- leaderstats setup
------------------------------------------------------------------------

local function setupLeaderstats(player)
	if player:FindFirstChild("leaderstats") then return end
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Value = 0
	coins.Parent = ls
	ls.Parent = player
end

Players.PlayerAdded:Connect(setupLeaderstats)
for _, p in Players:GetPlayers() do setupLeaderstats(p) end

------------------------------------------------------------------------
-- Floating "+N" income visual above each placed brainrot per tick
------------------------------------------------------------------------

local TweenService = game:GetService("TweenService")

local function showIncomeFloat(model, amount)
	if amount <= 0 then return end
	local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not primary then return end

	local bg = Instance.new("BillboardGui")
	bg.Name = "IncomeFloat"
	bg.Size = UDim2.new(0, 80, 0, 30)
	bg.StudsOffset = Vector3.new(0, 3, 0)
	bg.AlwaysOnTop = true
	bg.Adornee = primary
	bg.Parent = primary

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = ("+%d 💰"):format(amount)
	label.TextColor3 = Color3.fromRGB(255, 215, 60)
	label.TextStrokeColor3 = Color3.fromRGB(80, 50, 0)
	label.TextStrokeTransparency = 0
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Parent = bg

	-- Float upward + fade out over 1.2s
	local info = TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(bg, info, {StudsOffset = Vector3.new(0, 7, 0)}):Play()
	local fade = TweenService:Create(label, info, {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	fade:Play()
	fade.Completed:Connect(function() bg:Destroy() end)
end

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

local function getOwnerPlayer(base)
	local ownerName = base:GetAttribute("Owner")
	if not ownerName or ownerName == "" then return nil end
	return Players:FindFirstChild(ownerName)
end

local function getCapacity(base)
	return base:GetAttribute("Capacity") or DEFAULT_CAPACITY
end

local function placedCount(base)
	local list = placed[base]
	if not list then return 0 end
	-- prune destroyed entries lazily
	local alive = {}
	for _, m in list do
		if m and m.Parent == base then table.insert(alive, m) end
	end
	placed[base] = alive
	return #alive
end

local function randomPositionInBase(base, model)
	local _, baseSize = base:GetBoundingBox()
	local cf = base:GetPivot()
	local margin = 4
	local x = (math.random() * 2 - 1) * (baseSize.X/2 - margin)
	local z = (math.random() * 2 - 1) * (baseSize.Z/2 - margin)

	-- Y: stand on top of SpawnPoint if present, else above pivot
	local sp = base:FindFirstChild("SpawnPoint")
	local groundY
	if sp and sp:IsA("BasePart") then
		groundY = sp.Position.Y + sp.Size.Y/2
	else
		groundY = cf.Position.Y + 1
	end

	local _, brSize = model:GetBoundingBox()
	local worldY = groundY + brSize.Y/2 + 0.1

	return CFrame.new(cf.Position.X + x, worldY, cf.Position.Z + z)
		* CFrame.Angles(0, math.rad(math.random(0, 359)), 0)
end

------------------------------------------------------------------------
-- Place a brainrot on a base
------------------------------------------------------------------------

local function tryPlace(player, base)
	if BrainrotState.count(player) == 0 then return end
	if placedCount(base) >= getCapacity(base) then return end

	local entry = BrainrotState.popTop(player)
	if not entry then return end

	local model = entry.model
	if not model or not model.Parent then
		if entry.anchor then entry.anchor:Destroy() end
		return
	end

	-- Anchor parts and disable collision (so player walks through)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
			p.Massless = false
		end
	end

	-- Disable prompts (placed brainrots are stationary, can't be re-picked up)
	for _, d in model:GetDescendants() do
		if d:IsA("ProximityPrompt") then d.Enabled = false end
	end

	-- Remove head anchor weld
	if entry.anchor then entry.anchor:Destroy() end

	-- Tag and stash metadata
	CollectionService:RemoveTag(model, "Brainrot")
	CollectionService:AddTag(model, PLACED_TAG)
	model:SetAttribute("PlacedOnBase", base.Name)
	model:SetAttribute("PlacedBy", player.Name)

	model.Parent = base
	model:PivotTo(randomPositionInBase(base, model))

	placed[base] = placed[base] or {}
	table.insert(placed[base], model)

	print(("[BrainrotDelivery] %s placed %s on %s (%d/%d, +%d/sec) @ %s"):format(
		player.Name, model.Name, base.Name,
		#placed[base], getCapacity(base),
		BrainrotConfig.getIncome(model:GetAttribute("Rarity")),
		Util.locationOf(player)
	))
	evtPlaced:Fire(model, base, player)
end

------------------------------------------------------------------------
-- Touched setup per base
------------------------------------------------------------------------

local function bindBase(base)
	placed[base] = placed[base] or {}

	local function bindPart(p)
		if not p:IsA("BasePart") then return end
		-- Skip placed brainrots' own parts (already filtered by ownership but cheap to skip)
		if CollectionService:HasTag(p:FindFirstAncestorOfClass("Model") or p, PLACED_TAG) then return end

		p.Touched:Connect(function(hit)
			local char = hit:FindFirstAncestorOfClass("Model")
			if not char then return end
			if not char:FindFirstChildOfClass("Humanoid") then return end
			local player = Players:GetPlayerFromCharacter(char)
			if not player then return end

			-- Owner check: only base's owner triggers delivery
			if getOwnerPlayer(base) ~= player then return end

			-- Debounce per player
			local now = os.clock()
			local last = lastDelivery[player]
			if last and now - last < DELIVERY_DEBOUNCE then return end
			lastDelivery[player] = now

			tryPlace(player, base)
		end)
	end

	for _, p in base:GetDescendants() do bindPart(p) end
	base.DescendantAdded:Connect(bindPart)
end

for _, name in BASE_NAMES do
	local base = workspace:FindFirstChild(name)
	if base then
		bindBase(base)
		print("[BrainrotDelivery] bound " .. name)
	else
		warn("[BrainrotDelivery] base not found: " .. name)
	end
end

------------------------------------------------------------------------
-- Income tick: every second, sum income across each player's base
------------------------------------------------------------------------

task.spawn(function()
	while true do
		task.wait(1)
		for _, player in Players:GetPlayers() do
			local ls = player:FindFirstChild("leaderstats")
			local coins = ls and ls:FindFirstChild("Coins")
			if not coins then continue end

			local income = 0
			for _, baseName in BASE_NAMES do
				local base = workspace:FindFirstChild(baseName)
				if base and base:GetAttribute("Owner") == player.Name then
					local list = placed[base] or {}
					for _, m in list do
						if m and m.Parent == base then
							local brIncome = BrainrotConfig.getIncome(m:GetAttribute("Rarity"))
							income += brIncome
							task.spawn(showIncomeFloat, m, brIncome)
						end
					end
				end
			end
			if income > 0 then
				coins.Value = coins.Value + income
				print(("[BrainrotDelivery] %s +%d coins/sec (total: %d)"):format(
					player.Name, income, coins.Value
				))
			end
		end
	end
end)

------------------------------------------------------------------------
-- Cleanup on player leave
------------------------------------------------------------------------

Players.PlayerRemoving:Connect(function(player)
	lastDelivery[player] = nil
end)

print("[BrainrotDelivery] ready")
