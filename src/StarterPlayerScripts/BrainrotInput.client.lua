-- BrainrotInput (LocalScript in StarterPlayerScripts)
-- Listens for E key while carrying a brainrot, fires DropBrainrot on the server.
-- Shows a small HUD hint while carrying.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CARRYING_ATTR = "CarryingBrainrot"
local DROP_KEY = Enum.KeyCode.E

local player = Players.LocalPlayer
local dropEvent = ReplicatedStorage:WaitForChild("DropBrainrot")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BrainrotHud"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local label = Instance.new("TextLabel")
label.Size = UDim2.new(0, 280, 0, 44)
label.Position = UDim2.new(0.5, -140, 0.78, 0)
label.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
label.BackgroundTransparency = 0.45
label.TextColor3 = Color3.fromRGB(255, 255, 255)
label.Font = Enum.Font.GothamBold
label.TextSize = 18
label.Text = "[E] Drop brainrot"
label.Visible = false
label.Parent = screenGui

local function refresh()
	label.Visible = player:GetAttribute(CARRYING_ATTR) == true
end

player:GetAttributeChangedSignal(CARRYING_ATTR):Connect(refresh)
refresh()

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode ~= DROP_KEY then return end
	if player:GetAttribute(CARRYING_ATTR) ~= true then return end
	dropEvent:FireServer()
end)

print("[BrainrotInput] ready")
