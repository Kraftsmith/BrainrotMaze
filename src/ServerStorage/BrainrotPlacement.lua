-- BrainrotPlacement (ModuleScript in ServerStorage)
-- Сдача брейнрота в слот базы по нажатию E. Spec: Game Design/Base.md § Размещение брейнротов.
--
-- Используется из BrainrotPickup (E-handler решает: place vs drop) и из BrainrotDelivery
-- (rehydration на тег PlacedBrainrot — там логика похожая, но без снятия weld'ов).
--
-- ВАЖНО: модуль не знает про RemoteEvent / Touched — только функции tryPlaceRandom + findOwnedBaseUnder.

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local BaseSlots = require(ServerStorage:WaitForChild("BaseSlots"))
local PlayerData = require(ServerStorage:WaitForChild("PlayerData"))
local BrainrotLifecycle = require(ServerStorage:WaitForChild("BrainrotLifecycle"))
local BrainrotConfig = require(ReplicatedStorage:WaitForChild("BrainrotConfig"))
local Util = require(ServerStorage:WaitForChild("Util"))

local BASE_NAMES = {"bazapl1", "bazapl2", "bazapl3", "bazapl4"}
-- Радиус "игрок на своей базе" вокруг SpawnPoint. Платформа bazapl ~34×20, расстояние
-- от SpawnPoint до угла платформы ≈ 20 студ, поэтому 25 даёт небольшой forgiveness-overhang.
local DELIVERY_RADIUS = 25

local BrainrotPlacement = {}

-- Возвращает базу, на которой стоит игрок (X/Z в радиусе DELIVERY_RADIUS от SpawnPoint)
-- И которой он владеет. Y игнорируем — игрок может быть на любом этаже.
function BrainrotPlacement.findOwnedBaseUnder(player)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end
	local pos = hrp.Position

	for _, name in BASE_NAMES do
		local base = Workspace:FindFirstChild(name)
		if base and base:GetAttribute("Owner") == player.Name then
			local sp = base:FindFirstChild("SpawnPoint")
			if sp and sp:IsA("BasePart") then
				local dx, dz = pos.X - sp.Position.X, pos.Z - sp.Position.Z
				if dx*dx + dz*dz < DELIVERY_RADIUS*DELIVERY_RADIUS then
					return base
				end
			end
		end
	end
	return nil
end

-- Сдать СЛУЧАЙНОГО брейнрота из carry-стека игрока в свободный слот базы.
-- Возвращает (true) при успехе или (false, reason) если нечего/некуда/некому сдавать.
-- Не делает fallback дроп — caller сам решит что делать на failure.
function BrainrotPlacement.tryPlaceRandom(player, base)
	if not base then return false, "no base" end
	if base:GetAttribute("Owner") ~= player.Name then return false, "not owner" end

	if PlayerData.countCarry(player) == 0 then return false, "empty carry" end

	-- Capacity check
	PlayerData.prunePlaced(player)
	local placedList = PlayerData.getPlaced(player)
	if #placedList >= BaseSlots.getCapacity(base) then return false, "base full" end

	local slotIndex = BaseSlots.findFreeSlot(base, placedList)
	if not slotIndex then return false, "no free slot" end

	-- Случайный entry из стека.
	local idx = math.random(1, PlayerData.countCarry(player))
	local entry = PlayerData.removeCarryAt(player, idx)
	if not entry then return false, "carry race" end

	local model = entry.model
	if not model or not model.Parent then
		if entry.anchor then entry.anchor:Destroy() end
		return false, "model invalid"
	end

	-- Anchor parts + collision off (как в старом tryPlace).
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
			p.Massless = false
		end
	end
	for _, d in model:GetDescendants() do
		if d:IsA("ProximityPrompt") then d.Enabled = false end
	end
	if entry.anchor then entry.anchor:Destroy() end

	model:SetAttribute("SlotIndex", slotIndex)
	-- target ДО parent: иначе bbox базы распухнет на parts модели в carry-позиции.
	local targetCFrame = BaseSlots.slotPositionInBase(base, model, slotIndex)
	model.Parent = base
	model:PivotTo(targetCFrame)

	BrainrotLifecycle.transition(model, BrainrotLifecycle.States.Placed, {base = base, player = player})
	PlayerData.addPlacedIfNew(player, model)

	print(("[BrainrotPlacement] %s placed %s on %s slot %d (carry-idx %d, %d/%d, +%d/sec) @ %s"):format(
		player.Name, model.Name, base.Name, slotIndex, idx,
		#PlayerData.getPlaced(player), BaseSlots.getCapacity(base),
		BrainrotConfig.getIncome(model),
		Util.locationOf(player)
	))
	return true
end

return BrainrotPlacement
