-- UpgradeConfig (ModuleScript in ServerStorage)
-- Static tables for upgrade tracks: level → effect value + cost.
-- Numbers from Game Design/Economy.md.

local UpgradeConfig = {}

-- Speed (lvl 1–10): 16 → 35 WalkSpeed
UpgradeConfig.speed = {
	[1]  = {value = 16, cost = 0},
	[2]  = {value = 18, cost = 100},
	[3]  = {value = 20, cost = 300},
	[4]  = {value = 22, cost = 800},
	[5]  = {value = 24, cost = 2000},
	[6]  = {value = 26, cost = 5000},
	[7]  = {value = 28, cost = 12000},
	[8]  = {value = 30, cost = 30000},
	[9]  = {value = 32, cost = 75000},
	[10] = {value = 35, cost = 200000},
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

-- Base capacity (lvl 1–8): how many brainrots placed simultaneously on base
UpgradeConfig.baseCap = {
	[1] = {value = 4,  cost = 0},
	[2] = {value = 6,  cost = 500},
	[3] = {value = 8,  cost = 2000},
	[4] = {value = 12, cost = 8000},
	[5] = {value = 16, cost = 30000},
	[6] = {value = 24, cost = 100000},
	[7] = {value = 32, cost = 400000},
	[8] = {value = 48, cost = 1500000},
}

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
