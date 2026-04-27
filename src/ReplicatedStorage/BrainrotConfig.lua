-- BrainrotConfig (ModuleScript in ReplicatedStorage)
-- Single source of truth for rarity → income mapping.

local BrainrotConfig = {}

BrainrotConfig.income = {
	Common    = 1,
	Rare      = 4,
	Epic      = 15,
	Legendary = 60,
	Mythic    = 250,
	Gogly     = 1000,
}

BrainrotConfig.defaultRarity = "Common"

function BrainrotConfig.getIncome(rarity)
	return BrainrotConfig.income[rarity] or BrainrotConfig.income[BrainrotConfig.defaultRarity]
end

return BrainrotConfig
