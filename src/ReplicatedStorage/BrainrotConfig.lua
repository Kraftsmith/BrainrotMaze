-- BrainrotConfig (ModuleScript in ReplicatedStorage)
-- Per-brainrot income (coins/sec when placed on a base).
-- If a brainrot name is missing here, falls back to a per-rarity default.

local BrainrotConfig = {}

BrainrotConfig.income = {
	-- Common
	["Noobini Pizzanini"]    = 1,
	["Tung Tung Tung Sahur"] = 5,
	["Bombardiro Crocodilo"] = 7,
	["Pipi Kiwi"]            = 10,
	["Talpa Di Fero"]        = 12,
	["Lirilì Larilà"]        = 25,

	-- Rare
	["Gangster Footera"]   = 30,
	["Cacto Hipopotamo"]   = 32,
	["Bandito Bobritto"]   = 40,
	["Trippi Troppi"]      = 48,
	["Tric Trac Baraboom"] = 50,
	["Tim Cheese"]         = 52,

	-- Epic
	["Trulimero Trulicina"] = 60,
	["Boneca Ambalabu"]     = 65,
	["Salamino Penguino"]   = 70,
	["Bananita Dolphinita"] = 77,
	["Ta Ta Ta Ta Sahur"]   = 80,

	-- Legendary
	["Chimpanzini Bananini"] = 100,
	["Bambini Crostini"]     = 120,
	["Ballerina Cappuccina"] = 125,
	["Avocadini Antilopini"] = 150,
	["Cappuccino Assassino"] = 160,

	-- Mythic
	["Alessio"]            = 200,
	["Bombombini Gusini"]  = 250,
	["Chef Crabracadabra"] = 250,
	["Dug Dug Dug"]        = 250,
	["Brr Brr Patapim"]    = 250,

	-- Gogly
	["Chachechi"]            = 1000,
	["Cocofanto Elefanto"]   = 1000,
	["Dul Dul Dul"]          = 1000,
	["Garama and Madundung"] = 1000,
	["Frigo Camelo"]         = 1000,
	["Karkerkar Kurkur"]     = 10000,
}

BrainrotConfig.fallbackByRarity = {
	Common    = 1,
	Rare      = 30,
	Epic      = 60,
	Legendary = 100,
	Mythic    = 200,
	Gogly     = 1000,
}

BrainrotConfig.defaultRarity = "Common"

-- Палитра rarity для UI (Inventory, потенциально labels над брейнротами в лабиринте).
-- Цвета подобраны по стандартной RPG-палитре; меняй здесь, остальной код подхватит.
BrainrotConfig.rarityColor = {
	Common    = Color3.fromRGB(156, 163, 175),
	Rare      = Color3.fromRGB(34, 197, 94),
	Epic      = Color3.fromRGB(59, 130, 246),
	Legendary = Color3.fromRGB(249, 115, 22),
	Mythic    = Color3.fromRGB(168, 85, 247),
	Gogly     = Color3.fromRGB(250, 204, 21),
}

-- Порядок отображения групп в инвентаре (сверху вниз). Gogly = топ-тир по доходу.
BrainrotConfig.rarityOrder = {"Gogly", "Mythic", "Legendary", "Epic", "Rare", "Common"}

-- Get income for a brainrot. Pass the Model (preferred) or a name string.
-- Falls back to per-rarity default if name is unknown.
function BrainrotConfig.getIncome(modelOrName)
	local name, rarity
	if typeof(modelOrName) == "Instance" then
		name = modelOrName.Name
		rarity = modelOrName:GetAttribute("Rarity")
	elseif type(modelOrName) == "string" then
		name = modelOrName
	end

	if name and BrainrotConfig.income[name] then
		return BrainrotConfig.income[name]
	end
	return BrainrotConfig.fallbackByRarity[rarity or BrainrotConfig.defaultRarity]
		or BrainrotConfig.fallbackByRarity[BrainrotConfig.defaultRarity]
end

return BrainrotConfig
