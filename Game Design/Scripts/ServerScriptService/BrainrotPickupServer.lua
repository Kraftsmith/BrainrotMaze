-- BrainrotPickupServer (Script in ServerScriptService)
-- Handles: picking up brainrot models, delivering them to a base, and dropping tools.
-- Refactored for performance, security, and adherence to the game design loop.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ServerScriptService = game:GetService("ServerScriptService")

print("[BrainrotServer] Script loading...")

-- RemoteEvents
local collectEvent = ReplicatedStorage:WaitForChild("CollectBrainrot")
local droppedEvent = ReplicatedStorage:WaitForChild("BrainrotDropped")
local atBaseEvent = ReplicatedStorage:WaitForChild("BrainrotAtBase")
local pickedUpEvent = ReplicatedStorage:WaitForChild("BrainrotPickedUp")

-- Configuration
local PICKUP_RANGE = 7 -- A bit more lenient than the client's 5 studs
local CARRY_OFFSET = Vector3.new(0, 2, 0) -- How high above the head to carry the item

-- State
-- Tracks which brainrot models are currently being carried to prevent double-pickup.
-- Key: Model, Value: true
local carriedBrainrots = {}
-- Tracks which players are currently in the process of delivering to prevent duplicate triggers.
-- Key: Player, Value: true (with a debounce)
local playerDelivering = {}

------------------------------------------------------------------------
-- Core Logic: Delivery
-- Converts a carried model into a tool in the player's backpack.
------------------------------------------------------------------------
local function deliverBrainrot(player, brainrotModel)
	if not player or not brainrotModel then return end
	
	local character = player.Character
	if not character or brainrotModel.Parent ~= character then
		-- The model is not being carried by this player's character.
		return
	end

	-- Debounce to prevent multiple Touched events firing at once
	if playerDelivering[player] then return end
	playerDelivering[player] = true
	
	print(("[BrainrotServer] %s is delivering %s"):format(player.Name, brainrotModel.Name))

	-- Find the matching tool template in ServerScriptService
	local toolTemplate = ServerScriptService:FindFirstChild("BrainrotTools"):FindFirstChild(brainrotModel.Name)

	if not toolTemplate then
		warn(("[BrainrotServer] No tool template found for %s in ServerScriptService/BrainrotTools"):format(brainrotModel.Name))
		playerDelivering[player] = nil -- Clear debounce on failure
		return
	end

	local newTool = toolTemplate:Clone()
	newTool.Parent = player.Backpack

	-- Clean up the carried model
	carriedBrainrots[brainrotModel] = nil
	brainrotModel:Destroy()

	-- Notify client of successful delivery
	atBaseEvent:FireClient(player, newTool.Name)
	print(("[BrainrotServer] Converted %s to a tool for %s"):format(newTool.Name, player.Name))

	-- Clear debounce after a short delay
	task.delay(1, function()
		playerDelivering[player] = nil
	end)
end


------------------------------------------------------------------------
-- Setup Delivery Zone Listener
-- Listens for players carrying brainrots touching the delivery zone.
------------------------------------------------------------------------
local function setupDeliveryZone()
	-- Find the delivery zone part using a tag. This is much more performant.
	-- You must tag your delivery part/zone with "DeliveryZone" in the Tag Editor.
	local deliveryZones = CollectionService:GetTagged("DeliveryZone")
	if #deliveryZones == 0 then
		warn("[BrainrotServer] No part with the tag 'DeliveryZone' found in workspace. Delivery will not work.")
		return
	end
	
	local deliveryZone = deliveryZones[1] -- Assuming one delivery zone for now
	print("[BrainrotServer] Found DeliveryZone:", deliveryZone:GetFullName())

	deliveryZone.Touched:Connect(function(hit)
		local character = hit.Parent
		if not character then return end
		
		local player = Players:GetPlayerFromCharacter(character)
		if not player then return end

		-- Check if the character is carrying a brainrot
		for _, instance in character:GetChildren() do
			if instance:IsA("Model") and CollectionService:HasTag(instance, "Brainrot") then
				-- Found a carried brainrot, process the delivery
				deliverBrainrot(player, instance)
				break -- Stop checking once one is found
			end
		end
	end)
end

------------------------------------------------------------------------
-- Handle pickup request from client
------------------------------------------------------------------------
collectEvent.OnServerEvent:Connect(function(player, brainrotModel)
	-- 1. --- VALIDATION ---
	if not brainrotModel or not brainrotModel.PrimaryPart or not brainrotModel:IsDescendantOf(workspace) then
		return -- Invalid model or already picked up/destroyed
	end
	
	-- Security: Ensure the model is a valid, pickup-able brainrot
	if not CollectionService:HasTag(brainrotModel, "Brainrot") then
		return
	end
	
	-- Concurrency: Check if another player just picked it up
	if carriedBrainrots[brainrotModel] then
		return
	end
	
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	
	-- Anti-Cheat: Check distance using PrimaryPart
	local distance = (hrp.Position - brainrotModel.PrimaryPart.Position).Magnitude
	if distance > PICKUP_RANGE then
		return
	end
	
	-- 2. --- EXECUTION ---
	print(("[BrainrotServer] %s is picking up %s"):format(player.Name, brainrotModel.Name))
	
	carriedBrainrots[brainrotModel] = true
	brainrotModel.Parent = character
	
	local head = character:FindFirstChild("Head")
	if not head then
		carriedBrainrots[brainrotModel] = nil
		brainrotModel.Parent = workspace
		return
	end
	
	brainrotModel.PrimaryPart.Anchored = false
	brainrotModel.PrimaryPart.CanCollide = false
	
	local weld = Instance.new("WeldConstraint")
	weld.Name = "BrainrotWeld"
	weld.Part0 = head
	weld.Part1 = brainrotModel.PrimaryPart
	weld.Parent = brainrotModel.PrimaryPart
	
	brainrotModel:SetPrimaryPartCFrame(head.CFrame * CFrame.new(CARRY_OFFSET))
	
	-- 3. --- NOTIFY CLIENT ---
	pickedUpEvent:FireClient(player, brainrotModel.Name)
end)

------------------------------------------------------------------------
-- Handle drop request from client
------------------------------------------------------------------------
droppedEvent.OnServerEvent:Connect(function(player, tool)
	if not tool or not tool:IsA("Tool") or not tool:IsDescendantOf(player) then
		return -- Invalid or non-owned tool
	end
	
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	
	print(("[BrainrotServer] %s is dropping %s"):format(player.Name, tool.Name))
	
	-- Find the matching model template in ServerScriptService
	local modelTemplate = ServerScriptService:FindFirstChild("BrainrotModels"):FindFirstChild(tool.Name)
	
	if not modelTemplate then
		warn(("[BrainrotServer] No model template found for %s in ServerScriptService/BrainrotModels"):format(tool.Name))
		tool:Destroy() -- Destroy the tool anyway to prevent it from being stuck
		return
	end
	
	local newModel = modelTemplate:Clone()
	newModel.Parent = workspace
	
	local dropPosition = hrp.CFrame * CFrame.new(0, -hrp.Size.Y/2, -3)
	newModel:SetPrimaryPartCFrame(dropPosition)
	
	tool:Destroy()
end)


-- Initialize the script
setupDeliveryZone()
print("[BrainrotServer] Script initialized successfully")