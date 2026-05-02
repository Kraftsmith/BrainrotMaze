-- UpgradeConfig (ModuleScript in ReplicatedStorage)
-- Static tables for upgrade tracks: level → effect value + cost.
-- Numbers from Game Design/Economy.md and Game Design/Base.md.

local UpgradeConfig = {}

-- Speed (lvl 1–10): 16 → 70 WalkSpeed
UpgradeConfig.speed = {
	[1]  = {value = 16, cost = 0},
	[2]  = {value = 20, cost = 100},
	[3]  = {value = 24, cost = 300},
	[4]  = {value = 28, cost = 800},
	[5]  = {value = 33, cost = 2500},
	[6]  = {value = 38, cost = 7000},
	[7]  = {value = 44, cost = 20000},
	[8]  = {value = 51, cost = 60000},
	[9]  = {value = 60, cost = 200000},
	[10] = {value = 70, cost = 600000},
}

-- Carry capacity (lvl 1–8): how many brainrots stacked on head at once
UpgradeConfig.carry = {
	[1] = {value = 1, cost = 0},
	[2] = {value = 2, cost = 250},
	[3] = {value = 3, cost = 1000},
	[4] = {value = 4, cost = 4000},
	[5] = {value = 5, cost = 15000},
	[6] = {value = 6, cost = 50000},
	[7] = {value = 7, cost = 150000},
	[8] = {value = 8, cost = 500000},
}

-- Base capacity (lvl 1–21): per-slot purchases.
-- Lvl 1 = 10 slots (старт). Каждый следующий уровень = +1 слот по 500 монет, до 30 слотов (lvl 21).
-- Визуальный своп моделей по диапазонам Capacity (10 / 11..20 / 21..30) — в BaseSwap.server.lua (`ceil(cap/10)`).
UpgradeConfig.baseCap = {[1] = {value = 10, cost = 0}}
for lvl = 2, 21 do
	UpgradeConfig.baseCap[lvl] = {value = 9 + lvl, cost = 500}
end

function UpgradeConfig.getMaxLevel(track)
	local t = UpgradeConfig[track]
	return t and #t or 0
end

function UpgradeConfig.getEffect(track, level)
	local t = UpgradeConfig[track]
	if not t then return nil end
	local entry = t[math.clamp(level, 1, #t)]
	return entry and entry.value or nil
end

function UpgradeConfig.getCost(track, level)
	local t = UpgradeConfig[track]
	if not t then return nil end
	local entry = t[math.clamp(level, 1, #t)]
	return entry and entry.cost or nil
end

return UpgradeConfig
