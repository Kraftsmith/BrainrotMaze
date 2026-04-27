-- BrainrotClient (LocalScript in StarterPlayerScripts)
-- Handles: E to pick up brainrot (5 stud range), E to drop when tool is equipped
-- Refactored for performance and robustness.

print("[BrainrotClient] Script loading...")

-- Services
local UserInputService    = game:GetService("UserInputService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local RunService          = game:GetService("RunService")
local Players             = game:GetService("Players")
local CollectionService   = game:GetService("CollectionService")

-- Local Player
local player = Players.LocalPlayer

-- Remote Events
local collectEvent  = ReplicatedStorage:WaitForChild("CollectBrainrot")
local droppedEvent  = ReplicatedStorage:WaitForChild("BrainrotDropped")
local atBaseEvent   = ReplicatedStorage:WaitForChild("BrainrotAtBase")
local pickedUpEvent = ReplicatedStorage:WaitForChild("BrainrotPickedUp")

-- Constants
local PICKUP_RANGE_SQ = 5 * 5  -- Use squared range for performance (avoids square roots)
local SEARCH_INTERVAL = 0.2    -- How often to search for nearby brainrots (in seconds)

-- State
local isCarrying    = false  -- True when a brainrot is welded to the player's head
local closestBR     = nil    -- Closest brainrot model in range

------------------------------------------------------------------------
-- Hint GUI ("Press E to pick up" / "Press E to drop")
------------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BrainrotHintGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local hintLabel = Instance.new("TextLabel")
hintLabel.Size = UDim2.new(0, 260, 0, 44)
hintLabel.Position = UDim2.new(0.5, -130, 0.75, 0)
hintLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
hintLabel.BackgroundTransparency = 0.45
hintLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
hintLabel.Font = Enum.Font.GothamBold
hintLabel.TextSize = 18
hintLabel.Text = "[E] Pick up Brainrot"
hintLabel.Visible = false
hintLabel.Parent = screenGui

------------------------------------------------------------------------
-- Helper functions for checking player state
------------------------------------------------------------------------

-- NOTE: These functions still use name checking. For better robustness,
-- you could also tag your tools with "BrainrotTool" and use CollectionService here.
local function getEquippedBrainrotTool()
	local character = player.Character
	if not character then return nil end
	for _, child in character:GetChildren() do
		if child:IsA("Tool") and string.find(string.lower(child.Name), "brainrot") then
			return child
		end
	end
	return nil
end

local function hasBrainrotTool()
	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		for _, item in backpack:GetChildren() do
			if item:IsA("Tool") and string.find(string.lower(item.Name), "brainrot") then
				return true
			end
		end
	end
	return getEquippedBrainrotTool() ~= nil
end

------------------------------------------------------------------------
-- Background loop to find the closest brainrot (PERFORMANCE-FRIENDLY)
------------------------------------------------------------------------
task.spawn(function()
	while true do
		-- Only search if the player isn't carrying anything and doesn't have a tool
		if not isCarrying and not hasBrainrotTool() then
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")

			if hrp then
				local currentClosest = nil
				local minDistanceSq = PICKUP_RANGE_SQ

				-- Efficiently iterate only through objects tagged "Brainrot"
				for _, brModel in CollectionService:GetTagged("Brainrot") do
					-- Ensure the model has a PrimaryPart to calculate distance from
					if brModel:IsA("Model") and brModel.PrimaryPart then
						local distSq = (hrp.Position - brModel.PrimaryPart.Position).Magnitude^2
						if distSq < minDistanceSq then
							minDistanceSq = distSq
							currentClosest = brModel
						end
					end
				end
				closestBR = currentClosest
			else
				closestBR = nil
			end
		else
			closestBR = nil
		end
		task.wait(SEARCH_INTERVAL)
	end
end)


------------------------------------------------------------------------
-- RenderStepped: update hint visibility (LIGHTWEIGHT)
------------------------------------------------------------------------

RunService.RenderStepped:Connect(function()
	if isCarrying then
		hintLabel.Text = "Неси брейнрот на базу!"
		hintLabel.Visible = true
		return
	end

	local equippedTool = getEquippedBrainrotTool()
	if equippedTool then
		hintLabel.Text = "[E] Бросить " .. equippedTool.Name
		hintLabel.Visible = true
		return
	end

	-- The 'closestBR' variable is updated by the background loop.
	-- We just read it here to update the GUI.
	if closestBR then
		hintLabel.Text = "[E] Подобрать " .. closestBR.Name
		hintLabel.Visible = true
	else
		hintLabel.Visible = false
	end
end)

------------------------------------------------------------------------
-- E key handler
------------------------------------------------------------------------

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or input.KeyCode ~= Enum.KeyCode.E then return end

	-- Case 1: Drop equipped brainrot tool
	local equippedTool = getEquippedBrainrotTool()
	if equippedTool then
		droppedEvent:FireServer(equippedTool)
		return
	end

	-- Case 2: Pick up a nearby brainrot
	if closestBR and not isCarrying and not hasBrainrotTool() then
		print("[BrainrotClient] Firing CollectBrainrot event for:", closestBR.Name)
		collectEvent:FireServer(closestBR)
	end
end)

------------------------------------------------------------------------
-- Remote Event Handlers
------------------------------------------------------------------------

-- Server confirms pickup succeeded (brainrot welded to head)
pickedUpEvent.OnClientEvent:Connect(function(brainrotName)
	isCarrying = true
	print("[BrainrotClient] Successfully picked up:", brainrotName)
end)

-- Server confirms delivery to base (brainrot became a tool)
atBaseEvent.OnClientEvent:Connect(function(toolName)
	isCarrying = false
	hintLabel.Text = toolName .. " добавлен в инвентарь!"
	hintLabel.Visible = true
	task.delay(3, function()
		if hintLabel.Text == toolName .. " добавлен в инвентарь!" then
			hintLabel.Visible = false
		end
	end)
end)

print("[BrainrotClient] Initialized successfully")