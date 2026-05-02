-- BrainrotDelivery (Script in ServerScriptService)
-- Что осталось здесь: rehydration placed-брейнротов из SaveService (через тег PlacedBrainrot)
-- + income tick. Сама механика сдачи (E на базе → слот) — в BrainrotPlacement.lua,
-- триггер E-handler — в BrainrotPickup.server.lua.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local BrainrotConfig = require(ReplicatedStorage:WaitForChild("BrainrotConfig"))
local PlayerData = require(ServerStorage:WaitForChild("PlayerData"))
local BaseSlots = require(ServerStorage:WaitForChild("BaseSlots"))

local PLACED_TAG = "PlacedBrainrot"

------------------------------------------------------------------------
-- Floating "+N" income visual above each placed brainrot per tick
------------------------------------------------------------------------

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
-- Auto-registration: брейнроты с тегом PlacedBrainrot, появившиеся не через tryPlaceRandom
-- (например, рехидратированные SaveService после загрузки профиля), попадают в PlayerData
-- через сигнал. Дедупликация — addPlacedIfNew + table.find на старте.
------------------------------------------------------------------------

local function tryRegisterPlaced(model)
	if not model:IsA("Model") then return end
	local placedBy = model:GetAttribute("PlacedBy")
	if not placedBy then return end
	local player = Players:FindFirstChild(placedBy)
	if not player then return end -- хозяин не в игре — пропускаем, при возврате SaveService рехидратирует
	local baseName = model:GetAttribute("PlacedOnBase")
	local base = baseName and workspace:FindFirstChild(baseName)
	if not base then return end

	local existing = PlayerData.getPlaced(player)
	if table.find(existing, model) then return end

	-- Рехидратированные брейнроты приходят без SlotIndex (SaveService сохраняет cframe, не slot).
	-- Назначаем младший свободный — порядок rehydration сохраняет исходный порядок размещения.
	-- И сразу репозиционируем в сетку: сохранённая CFrame могла быть из buggy random-формулы
	-- (или с pivot-vs-bbox смещением шаблона), оставлять её = брейнрот висит вне базы.
	if not model:GetAttribute("SlotIndex") then
		local idx = BaseSlots.findFreeSlot(base, PlayerData.getPlaced(player))
		if idx then
			model:SetAttribute("SlotIndex", idx)
			model:PivotTo(BaseSlots.slotPositionInBase(base, model, idx))
		end
	end
	PlayerData.addPlacedIfNew(player, model)
	print(("[BrainrotDelivery] registered placed %s on %s slot %s (%d/%d)"):format(
		model.Name, base.Name, tostring(model:GetAttribute("SlotIndex")),
		#PlayerData.getPlaced(player), BaseSlots.getCapacity(base)
	))
end

for _, m in CollectionService:GetTagged(PLACED_TAG) do
	tryRegisterPlaced(m)
end
CollectionService:GetInstanceAddedSignal(PLACED_TAG):Connect(tryRegisterPlaced)

------------------------------------------------------------------------
-- Income tick: every second, sum income across each player's base
------------------------------------------------------------------------

task.spawn(function()
	while true do
		task.wait(1)
		for _, player in Players:GetPlayers() do
			PlayerData.prunePlaced(player)
			local list = PlayerData.getPlaced(player)
			local income = 0
			for _, m in list do
				local base = m.Parent
				if base then
					local vipMul = base:GetAttribute("Vip") and 2 or 1
					local brIncome = BrainrotConfig.getIncome(m) * vipMul
					income += brIncome
					task.spawn(showIncomeFloat, m, brIncome)
				end
			end
			if income > 0 then
				PlayerData.addCoins(player, income)
				print(("[BrainrotDelivery] %s +%d coins/sec (total: %d, placed=%d)"):format(
					player.Name, income, PlayerData.getCoins(player), #list
				))
			end
		end
	end
end)

print("[BrainrotDelivery] ready")
