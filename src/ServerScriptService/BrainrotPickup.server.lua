-- BrainrotPickup (Script in ServerScriptService)
-- Single source of truth for picking up brainrot models.
--   pickup: ProximityPrompt.Triggered  -> weld brainrot above player's head (max MAX_CARRY)
--   drop:   client fires DropBrainrot   -> drop top of stack in front of player
--   death:  destroy all carried brainrots (per design — they're lost)

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Util = require(ServerStorage:WaitForChild("Util"))
local PlayerData = require(ServerStorage:WaitForChild("PlayerData"))
local BrainrotLifecycle = require(ServerStorage:WaitForChild("BrainrotLifecycle"))
local BrainrotPlacement = require(ServerStorage:WaitForChild("BrainrotPlacement"))
local UpgradeConfig = require(ReplicatedStorage:WaitForChild("UpgradeConfig"))

local BRAINROT_TAG = "Brainrot"
local CARRY_OFFSET = 3       -- studs above the head for first brainrot
local STACK_SPACING = 3      -- studs between stacked brainrots
local DROP_FORWARD = 4       -- studs in front of player

local function getMaxCarry(player)
	local lvl = PlayerData.getValue(player, "carryLvl")
	return UpgradeConfig.getEffect("carry", lvl) or 1
end

local dropEvent = ReplicatedStorage:FindFirstChild("DropBrainrot")
if not dropEvent then
	dropEvent = Instance.new("RemoteEvent")
	dropEvent.Name = "DropBrainrot"
	dropEvent.Parent = ReplicatedStorage
end

-- Lifecycle BindableEvents folder (TrapHit is consumed here; Picked/Dropped/Destroyed are
-- fired by BrainrotLifecycle.transition based on state changes — don't fire them directly).
local brainrotEvents = ServerStorage:WaitForChild("BrainrotEvents")

local function findOrSetPrimary(model)
	if model.PrimaryPart then return model.PrimaryPart end
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			model.PrimaryPart = p
			return p
		end
	end
	return nil
end

local function ensureInternalWelds(model, primary)
	if model:GetAttribute("InternalWeldsBuilt") then return end
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p ~= primary then
			local w = Instance.new("WeldConstraint")
			w.Name = "BRWeld"
			w.Part0 = primary
			w.Part1 = p
			w.Parent = primary
		end
	end
	model:SetAttribute("InternalWeldsBuilt", true)
end

local function setPartsCarriedState(model)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.CanCollide = false
			p.Massless = true
		end
	end
end

local function setPartsDroppedState(model)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = true
			p.Massless = false
		end
	end
end

local function setPromptsEnabled(model, enabled)
	for _, d in model:GetDescendants() do
		if d:IsA("ProximityPrompt") then d.Enabled = enabled end
	end
end

local function pickup(player, model)
	if PlayerData.countCarry(player) >= getMaxCarry(player) then return end
	if not model or not model.Parent then return end
	if not CollectionService:HasTag(model, BRAINROT_TAG) then return end

	-- Race protection: prevent two players from grabbing the same brainrot in the same tick
	if model:GetAttribute("BeingPickedUp") then return end
	model:SetAttribute("BeingPickedUp", true)

	local char = player.Character
	if not char then
		model:SetAttribute("BeingPickedUp", false)
		return
	end
	local head = char:FindFirstChild("Head")
	if not head then
		model:SetAttribute("BeingPickedUp", false)
		return
	end

	local primary = findOrSetPrimary(model)
	if not primary then
		model:SetAttribute("BeingPickedUp", false)
		return
	end

	local slotIndex = PlayerData.countCarry(player) -- 0 for first, 1 for second
	local yOffset = head.Size.Y/2 + CARRY_OFFSET + slotIndex * STACK_SPACING

	local anchor = Instance.new("Part")
	anchor.Name = "BrainrotAnchor"
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.Massless = true
	anchor.Anchored = false
	anchor.CFrame = head.CFrame * CFrame.new(0, yOffset, 0)
	anchor.Parent = model

	local headWeld = Instance.new("WeldConstraint")
	headWeld.Name = "BRHeadWeld"
	headWeld.Part0 = head
	headWeld.Part1 = anchor
	headWeld.Parent = anchor

	setPartsCarriedState(model)
	ensureInternalWelds(model, primary)
	model:PivotTo(anchor.CFrame)

	local mainWeld = Instance.new("WeldConstraint")
	mainWeld.Name = "BRMainWeld"
	mainWeld.Part0 = anchor
	mainWeld.Part1 = primary
	mainWeld.Parent = anchor

	setPromptsEnabled(model, false)

	PlayerData.pushCarry(player, {model = model, anchor = anchor})
	BrainrotLifecycle.transition(model, BrainrotLifecycle.States.Carried, {player = player})
	print(("[BrainrotPickup] %s picked up %s (slot %d) @ %s"):format(player.Name, model.Name, slotIndex + 1, Util.locationOf(player)))
end

local function dropTop(player)
	local entry = PlayerData.popCarryTop(player)
	if not entry then return end

	local model = entry.model
	local anchor = entry.anchor

	if not model or not model.Parent then
		if anchor then anchor:Destroy() end
		return
	end

	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local dropCFrame
	if hrp and hrp.Parent then
		dropCFrame = hrp.CFrame * CFrame.new(0, -hrp.Size.Y/2, -DROP_FORWARD)
	else
		dropCFrame = model:GetPivot()
	end

	-- Anchor parts BEFORE removing head weld, so model doesn't fall during reparent
	setPartsDroppedState(model)
	if anchor then anchor:Destroy() end
	model.Parent = workspace
	model:PivotTo(dropCFrame)
	model:SetAttribute("BeingPickedUp", false)
	setPromptsEnabled(model, true)
	BrainrotLifecycle.transition(model, BrainrotLifecycle.States.Dropped, {player = player})
	print(("[BrainrotPickup] %s dropped %s @ %s"):format(player.Name, model.Name, Util.locationOf(player)))
end

local function destroyAllCarried(player)
	local list = PlayerData.popCarryAll(player)
	for _, entry in list do
		if entry.anchor then entry.anchor:Destroy() end
		if entry.model then
			BrainrotLifecycle.transition(entry.model, BrainrotLifecycle.States.Destroyed, {reason = "carrier-died"})
			entry.model:Destroy()
		end
	end
	if #list > 0 then
		print(("[BrainrotPickup] %s lost %d brainrots @ %s"):format(player.Name, #list, Util.locationOf(player)))
	end
end

-- Drop all carried brainrots in front of the player (used by traps).
local function dropAllCarried(player)
	local count = PlayerData.countCarry(player)
	for _ = 1, count do
		dropTop(player)
	end
	if count > 0 then
		print(("[BrainrotPickup] %s tripped, dropped %d brainrots"):format(player.Name, count))
	end
end

local function bindModel(model)
	if not model:IsA("Model") then return end
	for _, d in model:GetDescendants() do
		if d:IsA("ProximityPrompt") then
			d.Triggered:Connect(function(player)
				pickup(player, model)
			end)
		end
	end
end

for _, m in CollectionService:GetTagged(BRAINROT_TAG) do
	bindModel(m)
end
CollectionService:GetInstanceAddedSignal(BRAINROT_TAG):Connect(bindModel)

------------------------------------------------------------------------
-- Take-back: владелец забирает свой placed-брейнрот с базы (E с прицелом на модель)
-- → освобождает слот, добавляет брейнрота в carry-стек.
-- Используется для замены брейнрота: «снять старого с базы, чтобы поставить нового
-- который больше фармит».
--
-- Конфликт с обычным E-дропом разрешается ProximityPrompt-механикой: при активации
-- prompt UserInputService.InputBegan получает gameProcessedEvent=true, BrainrotInput.client
-- (там есть `if processed then return end`) пропускает FireServer DropBrainrot.
-- => Аим на брейнрота + E = take-back. Без аима + E = обычный drop / place.
------------------------------------------------------------------------

local PLACED_TAG = "PlacedBrainrot"

local function takeBackFromBase(player, model)
	-- Owner check (только хозяин)
	if model:GetAttribute("PlacedBy") ~= player.Name then return end
	-- State check (защита от race / устаревших prompt-связок)
	if not CollectionService:HasTag(model, PLACED_TAG) then return end
	-- Capacity check
	if PlayerData.countCarry(player) >= getMaxCarry(player) then
		print(("[BrainrotPickup] %s take-back rejected: carry full (%d/%d)"):format(
			player.Name, PlayerData.countCarry(player), getMaxCarry(player)
		))
		return
	end

	local char = player.Character
	if not char then return end
	local head = char:FindFirstChild("Head")
	if not head then return end

	local primary = findOrSetPrimary(model)
	if not primary then return end

	-- Destroy take-back prompt до Carried→Dropped — иначе setPromptsEnabled(true) при
	-- следующем дропе включит «Забрать» на брейнроте, лежащем в лабиринте (UX-баг).
	local oldPrompt = primary:FindFirstChild("TakeBackPrompt")
	if oldPrompt then oldPrompt:Destroy() end

	-- Reparent из base в workspace — модель теперь не «на базе».
	model.Parent = workspace

	-- Carry rig — идентичен pickup() для согласованности
	local slotIndex = PlayerData.countCarry(player)
	local yOffset = head.Size.Y/2 + CARRY_OFFSET + slotIndex * STACK_SPACING

	local anchor = Instance.new("Part")
	anchor.Name = "BrainrotAnchor"
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.Massless = true
	anchor.Anchored = false
	anchor.CFrame = head.CFrame * CFrame.new(0, yOffset, 0)
	anchor.Parent = model

	local headWeld = Instance.new("WeldConstraint")
	headWeld.Name = "BRHeadWeld"
	headWeld.Part0 = head
	headWeld.Part1 = anchor
	headWeld.Parent = anchor

	setPartsCarriedState(model)
	ensureInternalWelds(model, primary)
	model:PivotTo(anchor.CFrame)

	local mainWeld = Instance.new("WeldConstraint")
	mainWeld.Name = "BRMainWeld"
	mainWeld.Part0 = anchor
	mainWeld.Part1 = primary
	mainWeld.Parent = anchor

	setPromptsEnabled(model, false)

	PlayerData.removePlaced(player, model)
	PlayerData.pushCarry(player, {model = model, anchor = anchor})

	BrainrotLifecycle.transition(model, BrainrotLifecycle.States.Carried, {player = player})

	print(("[BrainrotPickup] %s took back %s from base @ %s"):format(
		player.Name, model.Name, Util.locationOf(player)
	))
end

local function bindPlacedModel(model)
	if not model:IsA("Model") then return end

	local primary = findOrSetPrimary(model)
	if not primary then return end

	-- Re-bind при повторном размещении: уничтожаем старый prompt + создаём свежий
	-- (соединение Triggered принадлежит уничтоженному prompt'у).
	local old = primary:FindFirstChild("TakeBackPrompt")
	if old then old:Destroy() end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TakeBackPrompt"
	prompt.ActionText = "Забрать"
	prompt.ObjectText = ""
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 8
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = true
	prompt.Parent = primary

	prompt.Triggered:Connect(function(player)
		takeBackFromBase(player, model)
	end)
end

for _, m in CollectionService:GetTagged(PLACED_TAG) do
	bindPlacedModel(m)
end
CollectionService:GetInstanceAddedSignal(PLACED_TAG):Connect(bindPlacedModel)

-- E дуальное: на своей базе — сдача случайного в слот; иначе — обычный дроп под ноги.
-- Сервер сам решает по геометрии (BrainrotPlacement.findOwnedBaseUnder), не доверяя клиенту.
dropEvent.OnServerEvent:Connect(function(player)
	local base = BrainrotPlacement.findOwnedBaseUnder(player)
	if base then
		local ok, reason = BrainrotPlacement.tryPlaceRandom(player, base)
		if ok then return end
		-- На failure (база полная / нет слотов / стек пуст) — НЕ роняем брейнрота на пол базы.
		-- Иначе игрок не понимает почему его брейнрот вдруг лежит вместо того чтобы сесть в слот.
		print(("[BrainrotPickup] %s E on own base %s no-place: %s"):format(player.Name, base.Name, reason or "?"))
		return
	end
	-- Игрок не на своей базе → обычный дроп.
	dropTop(player)
end)

local function setupCharacter(player, char)
	local hum = char:WaitForChild("Humanoid", 10)
	if hum then
		hum.Died:Connect(function() destroyAllCarried(player) end)
	end
end

local function setupPlayer(player)
	player.CharacterAdded:Connect(function(c) setupCharacter(player, c) end)
	if player.Character then setupCharacter(player, player.Character) end
end

Players.PlayerAdded:Connect(setupPlayer)
for _, p in Players:GetPlayers() do
	setupPlayer(p)
end
Players.PlayerRemoving:Connect(function(player)
	destroyAllCarried(player)
end)

-- Subscribe to trap hits (fired by MazeTrapsServer)
local trapHitEvent = brainrotEvents:WaitForChild("TrapHit")
trapHitEvent.Event:Connect(dropAllCarried)

print("[BrainrotPickup] ready (carry capacity now per-player from PlayerData)")
