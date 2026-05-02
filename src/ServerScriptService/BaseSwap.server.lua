-- BaseSwap (Script in ServerScriptService)
-- Replaces the visual model of a player base when its Capacity attribute changes.
-- Spec: see Game Design/Base.md (variant B — model swap, max 3 levels).
--
-- The shell `bazapl1..4` keeps its identity (Name, Owner, SpawnPoint, Capacity attribute)
-- so all other systems (BrainrotDelivery, BaseManager, UpgradeService) keep working unchanged.
-- We only swap what the player SEES.
--
-- Strategy:
--   - On init: snapshot the original visual children of each base (everything except SpawnPoint)
--     and their (Transparency, CanCollide). These represent "Level 1" visual.
--   - On Capacity change:
--       lvl 1 -> show originals, remove Visual model.
--       lvl 2/3 -> hide originals, clone matching template into a child Model named "Visual".

local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")

local BASE_NAMES = {"bazapl1", "bazapl2", "bazapl3", "bazapl4"}

local TEMPLATES_FOLDER = "BaseModels"
-- Level 1 = the player's bazapl_ shell as-is (no clone). Levels 2+ swap in a model from ServerStorage.BaseModels.
local LEVEL_TO_TEMPLATE = {
	[2] = "baza5",
	[3] = "bazalvl3",
}
-- VIP-вариант (см. Game Design/Base.md § VIP Base): свой набор моделей на все 3 уровня (включая L1 — VIP всегда визуально отличается).
local VIP_LEVEL_TO_TEMPLATE = {
	[1] = "vipbase1",
	[2] = "vipbase2",
	[3] = "vipbase3",
}
local MAX_LEVEL = 3

local templatesFolder = ServerStorage:WaitForChild(TEMPLATES_FOLDER)

------------------------------------------------------------------------
-- Originals snapshot
------------------------------------------------------------------------

-- [base] = { [BasePart] = {transparency=N, canCollide=bool} }
local originals = {}

local function snapshotOriginals(base)
	local snap = {}
	for _, p in ipairs(base:GetDescendants()) do
		if p:IsA("BasePart") and p.Name ~= "SpawnPoint" then
			snap[p] = {
				transparency = p.Transparency,
				canCollide = p.CanCollide,
			}
		end
	end
	originals[base] = snap
end

local function setOriginalsVisible(base, visible)
	local snap = originals[base]
	if not snap then return end
	for part, orig in pairs(snap) do
		if part.Parent then -- still alive
			if visible then
				part.Transparency = orig.transparency
				part.CanCollide = orig.canCollide
			else
				part.Transparency = 1
				part.CanCollide = false
			end
		end
	end
end

------------------------------------------------------------------------
-- Visual swap
------------------------------------------------------------------------

-- Per-slot apgrades (UpgradeConfig.baseCap): cap может быть любым в [10..30].
-- ceil чтобы первый купленный слот (cap=11) сразу свопил визуал на L2 (baza5 c Floor2),
-- а не ждал cap=20.
local function levelFromCapacity(cap)
	cap = cap or 10
	return math.clamp(math.ceil(cap / 10), 1, MAX_LEVEL)
end

local function alignBottomsTo(clone, basePos, baseSize)
	local cloneCF, cloneSize = clone:GetBoundingBox()
	local baseBottomY = basePos.Y - baseSize.Y/2
	local cloneBottomY = cloneCF.Position.Y - cloneSize.Y/2
	local lift = baseBottomY - cloneBottomY
	local target = CFrame.new(basePos.X, cloneCF.Position.Y + lift, basePos.Z)
	clone:PivotTo(target)
end

local function clearVisual(base)
	local v = base:FindFirstChild("Visual")
	if v then v:Destroy() end
end

local function pickTemplateName(lvl, isVip)
	if isVip then
		return VIP_LEVEL_TO_TEMPLATE[lvl]
	elseif lvl <= 1 then
		return nil -- non-VIP L1 — используем оригинал bazapl, без клонирования
	else
		return LEVEL_TO_TEMPLATE[lvl]
	end
end

local function applyVisualForLevel(base, lvl, isVip)
	local templateName = pickTemplateName(lvl, isVip)

	if not templateName then
		-- Non-VIP L1: показываем originals, очищаем Visual.
		clearVisual(base)
		setOriginalsVisible(base, true)
		return
	end

	local template = templatesFolder:FindFirstChild(templateName)
	-- VIP fallback: если уровень-специфичной модели (vipbase1/2/3) ещё нет, используем generic `vipbase`.
	-- Позволяет пользоваться одной моделью на все 3 уровня пока не сделают отдельные.
	if not template and isVip then
		template = templatesFolder:FindFirstChild("vipbase")
		if template then
			print(("[BaseSwap] '%s' not found, fallback to generic 'vipbase' (lvl %d)"):format(templateName, lvl))
		end
	end
	if not template then
		warn(("[BaseSwap] template '%s' not found in ServerStorage.%s"):format(templateName, TEMPLATES_FOLDER))
		return
	end

	-- Remove old Visual first so it's NOT in the base's bounding box when we align the new one.
	clearVisual(base)
	-- Snapshot base bbox BEFORE we add the new clone (otherwise GetBoundingBox would include the
	-- not-yet-aligned clone in its default ServerStorage position, throwing alignment 1000+ studs off).
	local baseCF, baseSize = base:GetBoundingBox()

	-- Hide originals (after capturing bbox — hidden parts still report position).
	setOriginalsVisible(base, false)

	local clone = template:Clone()
	clone.Name = "Visual"
	for _, p in ipairs(clone:GetDescendants()) do
		if p:IsA("BasePart") then p.Anchored = true end
	end
	-- Align in world space first, then parent.
	alignBottomsTo(clone, baseCF.Position, baseSize)
	clone.Parent = base
end

local function applyForBase(base)
	local cap = base:GetAttribute("Capacity")
	local isVip = base:GetAttribute("Vip") == true
	applyVisualForLevel(base, levelFromCapacity(cap), isVip)
end

------------------------------------------------------------------------
-- Wire up
------------------------------------------------------------------------

for _, name in ipairs(BASE_NAMES) do
	local base = Workspace:FindFirstChild(name)
	if not base then
		warn(("[BaseSwap] base not found: %s"):format(name))
	else
		snapshotOriginals(base)
		applyForBase(base)
		base:GetAttributeChangedSignal("Capacity"):Connect(function()
			applyForBase(base)
		end)
		base:GetAttributeChangedSignal("Vip"):Connect(function()
			applyForBase(base)
		end)
		print(("[BaseSwap] bound %s (cap=%s, vip=%s)"):format(
			name, tostring(base:GetAttribute("Capacity")), tostring(base:GetAttribute("Vip"))
		))
	end
end

print("[BaseSwap] ready")
