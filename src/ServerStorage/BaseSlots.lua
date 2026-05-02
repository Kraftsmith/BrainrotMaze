-- BaseSlots (ModuleScript in ServerStorage)
-- Геометрия слотов на базе: позиция по индексу слота, свободные слоты, capacity.
-- Чистый модуль — без знания о владельце/PlayerData. Каллер передаёт placedList явно.
--
-- Модель слотов:
--   slotIndex 1..N глобальный по базе. Этаж = ceil(slotIndex/10).
--   Внутри этажа — НЕ алгоритмическая сетка, а явные маркеры в Studio:
--     `base.slots` (Floor 1) или `base.Visual.Floor<N>.slots` (Floor 2+) — Model-контейнер
--     с детьми Part'ами с Name == "slot". 1 маркер = 1 слот.
--   Если разметка маркерами на этаже отсутствует — fallback в pitch-сетку 5×2 вокруг SpawnPoint.
--   На каждой placed-модели стоит атрибут SlotIndex — он же используется для поиска свободных.

local BaseSlots = {}

local DEFAULT_CAPACITY = 10
local SLOTS_PER_FLOOR = 10
local SLOT_COLS = 5
local SLOT_ROWS = 2
-- Pitch-сетка — fallback когда нет явных slot-маркеров. См. комментарий в slotPositionInBase.
local SLOT_PITCH_X = 7
local SLOT_PITCH_Z = 7

BaseSlots.SLOTS_PER_FLOOR = SLOTS_PER_FLOOR

function BaseSlots.getCapacity(base)
	return base:GetAttribute("Capacity") or DEFAULT_CAPACITY
end

local Y_BIN = 5  -- студ. Маркеры разных этажей разнесены по Y >> 5; одного этажа — почти равны.

-- Все slot-маркеры под root, сгруппированные по Y-бину. Возвращает {bin -> {Part, ...}}.
local function collectMarkersByY(root)
	local groups = {}
	for _, p in root:GetDescendants() do
		if p:IsA("BasePart") and p.Name == "slot" then
			local bin = math.floor(p.Position.Y / Y_BIN + 0.5) * Y_BIN
			groups[bin] = groups[bin] or {}
			table.insert(groups[bin], p)
		end
	end
	return groups
end

-- Маркеры этажа floorIndex. Возвращает упорядоченный список Part'ов или nil.
--
-- Стратегия:
--   1. Пробуем `base.Visual` (после BaseSwap там клон baza5/bazalvl6 с маркерами на разных Y).
--      Если в Visual есть маркеры — используем их, шелл игнорируем (он визуально hide'нут).
--   2. Иначе — `base` напрямую (L1, BaseSwap ещё не сработал).
--   3. Группируем маркеры по Y-бину, сортируем бины по возрастанию.
--      bins[1] = Floor 1, bins[2] = Floor 2, ... — определяется их Y-порядком, а не hierarchy.
--   4. Внутри одного этажа сортируем по (X, Z) — детерминированный порядок SlotIndex,
--      устойчивый к перетасовкам в Studio.
local function getFloorMarkers(base, floorIndex)
	local visual = base:FindFirstChild("Visual")
	local roots = {}
	if visual then table.insert(roots, visual) end
	table.insert(roots, base)

	for _, root in roots do
		local groups = collectMarkersByY(root)
		local bins = {}
		for k in pairs(groups) do table.insert(bins, k) end
		if #bins == 0 then continue end
		table.sort(bins)

		local key = bins[floorIndex]
		if key then
			local markers = groups[key]
			table.sort(markers, function(a, b)
				if math.abs(a.Position.X - b.Position.X) > 0.5 then
					return a.Position.X < b.Position.X
				end
				return a.Position.Z < b.Position.Z
			end)
			return markers
		end
	end
	return nil
end

-- Младший свободный слот в [1..Capacity]. placedList — текущие placed-модели на базе
-- (типично PlayerData.getPlaced(owner) после prune). Возвращает nil если все слоты заняты.
function BaseSlots.findFreeSlot(base, placedList)
	local cap = BaseSlots.getCapacity(base)
	local taken = {}
	for _, m in placedList do
		if m and m.Parent == base then
			local idx = m:GetAttribute("SlotIndex")
			if idx then taken[idx] = true end
		end
	end
	for i = 1, cap do
		if not taken[i] then return i end
	end
	return nil
end

-- Top Y пола этажа.
--   Если на этаже есть маркеры — берём их Y (маркер.Y совпадает с поверхностью пола: на bazapl1
--   маркеры стоят на Y=25.5 ≈ SpawnPoint.Y; в template baza5 — на Y=0.2 для Floor 1, Y=22.2 для
--   Floor 2; после alignBottomsTo при BaseSwap эти числа смещаются на одну и ту же дельту,
--   сохраняя инвариант "маркер.Y = пол этажа").
--   Иначе — fallback на SpawnPoint (Floor 1) или Floor%d-bbox (Floor 2+, как раньше).
local function topYForFloor(base, floorIndex, markers)
	if markers and markers[1] then
		return markers[1].Position.Y
	end
	if floorIndex == 1 then
		local sp = base:FindFirstChild("SpawnPoint")
		if sp and sp:IsA("BasePart") then
			return sp.Position.Y + sp.Size.Y/2
		end
		return base:GetPivot().Position.Y + 1
	end
	local fp = base:FindFirstChild(("Floor%d"):format(floorIndex), true)
	if fp then
		local cf, size
		if fp:IsA("Model") then
			cf, size = fp:GetBoundingBox()
		elseif fp:IsA("BasePart") then
			cf, size = fp.CFrame, fp.Size
		end
		if cf then
			return cf.Position.Y + size.Y/2
		end
	end
	-- fallback: ground
	return topYForFloor(base, 1, nil)
end

-- Позиция слота на сетке. slotIndex 1..N (глобальный по базе). Этаж = ceil(slotIndex/10).
-- Сначала пытаемся достать координаты из явных маркеров (`slots` Model). Иначе — pitch-сетка.
function BaseSlots.slotPositionInBase(base, model, slotIndex)
	local floorIndex = math.max(1, math.ceil(slotIndex / SLOTS_PER_FLOOR))
	local localIdx = ((slotIndex - 1) % SLOTS_PER_FLOOR) + 1

	local x, z
	local markers = getFloorMarkers(base, floorIndex)
	if markers and markers[localIdx] then
		-- Явный маркер. Берём X/Z; Y игнорируем (маркер — 13-stud стойка вокруг центра,
		-- его центр Y ниже пола; брейнрот должен стоять на полу).
		local marker = markers[localIdx]
		x, z = marker.Position.X, marker.Position.Z
	else
		-- Fallback: pitch-сетка 5×2 вокруг SpawnPoint (Floor 1) или Floor<N>-pivot (выше).
		-- Используется на не-размеченных базах и на этажах без `slots`-контейнера.
		local refCenter
		if floorIndex == 1 then
			local sp = base:FindFirstChild("SpawnPoint")
			refCenter = (sp and sp:IsA("BasePart")) and sp.Position or base:GetPivot().Position
		else
			local fp = base:FindFirstChild(("Floor%d"):format(floorIndex), true)
			if fp and fp:IsA("Model") then
				refCenter = fp:GetBoundingBox().Position
			elseif fp and fp:IsA("BasePart") then
				refCenter = fp.Position
			else
				warn(("[BaseSlots] Floor%d not found on %s, fallback to ground"):format(floorIndex, base.Name))
				local sp = base:FindFirstChild("SpawnPoint")
				refCenter = (sp and sp:IsA("BasePart")) and sp.Position or base:GetPivot().Position
			end
		end
		local col = (localIdx - 1) % SLOT_COLS
		local row = math.floor((localIdx - 1) / SLOT_COLS)
		x = refCenter.X + (col - (SLOT_COLS - 1) / 2) * SLOT_PITCH_X
		z = refCenter.Z + (row - (SLOT_ROWS - 1) / 2) * SLOT_PITCH_Z
	end

	local topY = topYForFloor(base, floorIndex, markers)

	-- Возвращаем pivot-CFrame, при котором BBOX-ЦЕНТР модели окажется в (x, topY+bsz.Y/2, z),
	-- а не сам pivot. У шаблонов брейнротов pivot часто смещён от visible parts (Lirilì: ~5 студов
	-- по Y между RootPart и центром). Транслируем pivot так, чтобы bbox сел в слот.
	local pivotCF = model:GetPivot()
	local bcf, bsz = model:GetBoundingBox()
	local target = Vector3.new(x, topY + bsz.Y/2 + 0.1, z)
	return pivotCF + (target - bcf.Position)
end

return BaseSlots
