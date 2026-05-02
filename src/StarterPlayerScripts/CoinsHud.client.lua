-- CoinsHud (LocalScript in StarterPlayerScripts)
-- Always-visible coin balance in the bottom-right corner.
-- Reads leaderstats.Coins (set by BrainrotDelivery / UpgradeService).

local Players = game:GetService("Players")
local player = Players.LocalPlayer

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CoinsHud"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local label = Instance.new("TextLabel")
label.Name = "Coins"
label.Size = UDim2.new(0, 170, 0, 50)
label.AnchorPoint = Vector2.new(1, 1)
label.Position = UDim2.new(1, -12, 1, -12)
label.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
label.BackgroundTransparency = 0.4
label.TextColor3 = Color3.fromRGB(255, 215, 60)
label.Font = Enum.Font.GothamBold
label.TextSize = 22
label.Text = "💰 0"
label.TextXAlignment = Enum.TextXAlignment.Center
label.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = label

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(255, 215, 60)
stroke.Thickness = 1
stroke.Parent = label

local function setText(value)
	label.Text = ("💰 %d"):format(value)
end

-- Bind to a Coins IntValue: set initial text and update on change.
local function bind(coins)
	setText(coins.Value)
	coins:GetPropertyChangedSignal("Value"):Connect(function()
		setText(coins.Value)
	end)
end

-- Wait for leaderstats and Coins to exist (they're created by server scripts on join,
-- which may race with this client script's start).
local function watch()
	local ls = player:FindFirstChild("leaderstats")
	if not ls then
		local conn
		conn = player.ChildAdded:Connect(function(c)
			if c.Name == "leaderstats" then
				conn:Disconnect()
				watch()
			end
		end)
		return
	end
	local coins = ls:FindFirstChild("Coins")
	if coins then
		bind(coins)
	else
		local conn
		conn = ls.ChildAdded:Connect(function(c)
			if c.Name == "Coins" then
				conn:Disconnect()
				bind(c)
			end
		end)
	end
end

watch()
print("[CoinsHud] ready")
