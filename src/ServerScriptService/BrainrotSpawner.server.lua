-- BrainrotSpawner (Script in ServerScriptService)
-- For each part tagged BrainrotSpawnPad: spawn a brainrot, wait 30–90s after consume, respawn.
-- A pad is "consumed" when one of {Picked, Placed, Destroyed} BindableEvents fires for its model.

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")

local SPAWN_TAG     = "BrainrotSpawnPad"
local BRAINROT_TAG  = "Brainrot"
local MIN_INTERVAL  = 30
local MAX_INTERVAL  = 90

local templatesFolder = ServerStorage:WaitForChild("BrainrotTemplates")

------------------------------------------------------------------------
-- Build template index: rarity -> list of templates
------------------------------------------------------------------------
local templatesByRarity = {}

local function indexTemplate(t)
	if not t:IsA("Model") then return end
	local r = t:GetAttribute("Rarity") or "Common"
	templatesByRarity[r] = templatesByRarity[r] or {}
	table.insert(templatesByRarity[r], t)
end

for _, t in templatesFolder:GetChildren() do indexTemplate(t) end
templatesFolder.ChildAdded:Connect(indexTemplate)

local function pickTemplate(rarities)
	local pool = {}
	for _, rarity in rarities do
		for _, t in (templatesByRarity[rarity] or {}) do
			table.insert(pool, t)
		end
	end
	if #pool == 0 then return nil end
	return pool[math.random(1, #pool)]
end

------------------------------------------------------------------------
-- Spawn one brainrot at a pad
------------------------------------------------------------------------
local function spawnAtPad(pad)
	local raritiesCsv = pad:GetAttribute("Rarities") or "Common"
	local rarities = {}
	for part in string.gmatch(raritiesCsv, "[^,]+") do
		table.insert(rarities, part:match("^%s*(.-)%s*$"))
	end

	local template = pickTemplate(rarities)
	if not template then
		warn(("[BrainrotSpawner] no template for rarities '%s' (pad %s)"):format(raritiesCsv, pad:GetFullName()))
		return nil
	end

	local clone = template:Clone()
	-- Ensure PrimaryPart
	if not clone.PrimaryPart then
		for _, p in clone:GetDescendants() do
			if p:IsA("BasePart") then clone.PrimaryPart = p; break end
		end
	end
	-- Anchor parts (will be unanchored on pickup by BrainrotPickup)
	for _, p in clone:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = true
		end
	end
	-- Re-enable prompts (templates have them disabled)
	for _, d in clone:GetDescendants() do
		if d:IsA("ProximityPrompt") then d.Enabled = true end
	end

	-- Place above pad
	clone.Parent = workspace
	local _, brSize = clone:GetBoundingBox()
	local y = pad.Position.Y + pad.Size.Y/2 + brSize.Y/2 + 0.1
	clone:PivotTo(
		CFrame.new(pad.Position.X, y, pad.Position.Z)
		* CFrame.Angles(0, math.rad(math.random(0, 359)), 0)
	)

	-- Tag (this triggers BrainrotPickup's bindModel via GetInstanceAddedSignal)
	CollectionService:AddTag(clone, BRAINROT_TAG)

	return clone
end

------------------------------------------------------------------------
-- Pad lifecycle: spawn -> wait for lifecycle event -> respawn after delay
-- Pad is freed when one of {Picked, Placed, Destroyed} fires for its model.
------------------------------------------------------------------------
local activeModelByPad = {} -- [pad] = model
local activePadByModel = {} -- [model] = pad

local function startPad(pad)
	if activeModelByPad[pad] then return end
	local model = spawnAtPad(pad)
	if not model then return end
	activeModelByPad[pad] = model
	activePadByModel[model] = pad
end

local function freeAndRespawn(model)
	local pad = activePadByModel[model]
	if not pad then return end -- not one of ours (e.g., dropped brainrot, foreign Brainrot tag)
	activeModelByPad[pad] = nil
	activePadByModel[model] = nil
	task.spawn(function()
		task.wait(math.random(MIN_INTERVAL, MAX_INTERVAL))
		if pad.Parent and not activeModelByPad[pad] then
			startPad(pad)
		end
	end)
end

------------------------------------------------------------------------
-- Subscribe to lifecycle events FIRST (before initial spawn) so no events miss.
------------------------------------------------------------------------
local brainrotEvents = ServerStorage:WaitForChild("BrainrotEvents")
brainrotEvents:WaitForChild("Picked").Event:Connect(freeAndRespawn)
brainrotEvents:WaitForChild("Placed").Event:Connect(freeAndRespawn)
brainrotEvents:WaitForChild("Destroyed").Event:Connect(freeAndRespawn)

for _, pad in CollectionService:GetTagged(SPAWN_TAG) do
	startPad(pad)
end
CollectionService:GetInstanceAddedSignal(SPAWN_TAG):Connect(startPad)

local totalPads = #CollectionService:GetTagged(SPAWN_TAG)
local totalTemplates = 0
for _, t in templatesFolder:GetChildren() do totalTemplates += 1 end
print(("[BrainrotSpawner] ready (pads=%d, templates=%d, interval=%d–%ds)"):format(
	totalPads, totalTemplates, MIN_INTERVAL, MAX_INTERVAL
))
