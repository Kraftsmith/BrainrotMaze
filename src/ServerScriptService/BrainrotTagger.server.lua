-- BrainrotTagger (Script in ServerScriptService)
-- Tags all brainrot models with "Brainrot" so the client can detect them.
-- Acts as a safety-net: if user/son drops a model named "*brainrot*" into Workspace
-- manually, it gets tagged automatically (Spawner already tags its own clones).

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local BRAINROT_TAG = "Brainrot"

print("[BrainrotTagger] Script loading...")

local function isBrainrot(model)
	if not model:IsA("Model") then return false end
	local name = string.lower(model.Name)
	return string.find(name, "brainrot") ~= nil
end

local function tagBrainrot(model)
	if not CollectionService:HasTag(model, BRAINROT_TAG) then
		CollectionService:AddTag(model, BRAINROT_TAG)
		print("[BrainrotTagger] Tagged:", model.Name)
	end
end

for _, descendant in Workspace:GetDescendants() do
	if isBrainrot(descendant) then
		tagBrainrot(descendant)
	end
end

Workspace.DescendantAdded:Connect(function(descendant)
	if isBrainrot(descendant) then
		tagBrainrot(descendant)
	end
end)

print("[BrainrotTagger] Script initialized successfully")
