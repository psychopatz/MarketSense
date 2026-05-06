require "MarketSense/MS_Core"
require "MarketSense/MS_Config"

MarketSense = MarketSense or {}
MarketSense.HeuristicsDB = MarketSense.HeuristicsDB or {
    items = {},
    tags = {},
    categories = {},
    modules = {}
}

local DB     = MarketSense.HeuristicsDB
local Core   = MarketSense.Core
local Config = MarketSense.ItemRuntimeConfig

local function register(target, key, data)
    if type(key) ~= "string" or key == "" or type(data) ~= "table" then return end
    target[key] = Core.deepCopy(data)
end

function DB.registerItem(fullType, data)   register(DB.items,      fullType, data) end
function DB.registerTag(tag, data)         register(DB.tags,       tag,      data) end
function DB.registerCategory(category, data) register(DB.categories, category, data) end
function DB.registerModule(moduleName, data) register(DB.modules,    moduleName, data) end

function DB.getItem(fullType)       return DB.items[fullType] end
function DB.getTag(tag)             return DB.tags[tag] end
function DB.getCategory(category)   return DB.categories[category] end
function DB.getModule(moduleName)   return DB.modules[moduleName] end

-- Category defaults
DB.registerCategory("Beverage", {
    stockMultiplier = Config.categories and Config.categories.Beverage and Config.categories.Beverage.stock_multiplier or 1.15,
    minRatio = Config.categories and Config.categories.Beverage and Config.categories.Beverage.stock_min_ratio or 0.25
})
DB.registerCategory("Weapon", {
    stockMultiplier = Config.categories and Config.categories.Weapon and Config.categories.Weapon.stock_multiplier or 0.80,
    minRatio = Config.categories and Config.categories.Weapon and Config.categories.Weapon.stock_min_ratio or 0.05
})
DB.registerCategory("Medical", {
    stockMultiplier = Config.categories and Config.categories.Medical and Config.categories.Medical.stock_multiplier or 1.10,
    minRatio = Config.categories and Config.categories.Medical and Config.categories.Medical.stock_min_ratio or 0.20
})
DB.registerCategory("Food", {
    stockMultiplier = Config.categories and Config.categories.Food and Config.categories.Food.stock_multiplier or 1.20,
    minRatio = Config.categories and Config.categories.Food and Config.categories.Food.stock_min_ratio or 0.25
})
DB.registerCategory("Container", {
    stockMultiplier = Config.categories and Config.categories.Container and Config.categories.Container.stock_multiplier or 0.90,
    minRatio = Config.categories and Config.categories.Container and Config.categories.Container.stock_min_ratio or 0.10
})
DB.registerCategory("Clothing", {
    stockMultiplier = Config.categories and Config.categories.Clothing and Config.categories.Clothing.stock_multiplier or 0.95,
    minRatio = Config.categories and Config.categories.Clothing and Config.categories.Clothing.stock_min_ratio or 0.18
})
DB.registerCategory("Tool", {
    stockMultiplier = Config.categories and Config.categories.Tool and Config.categories.Tool.stock_multiplier or 0.8,
    minRatio = Config.categories and Config.categories.Tool and Config.categories.Tool.stock_min_ratio or 0.12
})
DB.registerCategory("Electronics", {
    stockMultiplier = Config.categories and Config.categories.Electronics and Config.categories.Electronics.stock_multiplier or 0.55,
    minRatio = Config.categories and Config.categories.Electronics and Config.categories.Electronics.stock_min_ratio or 0.05
})
DB.registerCategory("Literature", {
    stockMultiplier = Config.categories and Config.categories.Literature and Config.categories.Literature.stock_multiplier or 1.0,
    minRatio = Config.categories and Config.categories.Literature and Config.categories.Literature.stock_min_ratio or 0.16
})
DB.registerCategory("Resource", {
    stockMultiplier = Config.categories and Config.categories.Resource and Config.categories.Resource.stock_multiplier or 1.1,
    minRatio = Config.categories and Config.categories.Resource and Config.categories.Resource.stock_min_ratio or 0.18
})
DB.registerCategory("Building", {
    stockMultiplier = Config.categories and Config.categories.Building and Config.categories.Building.stock_multiplier or 0.9,
    minRatio = Config.categories and Config.categories.Building and Config.categories.Building.stock_min_ratio or 0.10
})

-- Descriptor tag defaults (dot-notation kept for descriptors)
DB.registerTag("Rarity.Uncommon", {
    add = Config.rarityAdditions and Config.rarityAdditions["Uncommon"] or 14,
    stockMultiplier = Config.global and Config.global.stock_uncommon_multiplier or 0.85
})
DB.registerTag("Rarity.Rare", {
    add = Config.rarityAdditions and Config.rarityAdditions["Rare"] or 17,
    stockMultiplier = Config.global and Config.global.stock_rare_multiplier or 0.55,
    minRatio = Config.global and Config.global.stock_rare_min_ratio or 0
})
DB.registerTag("Rarity.Legendary", {
    add = Config.rarityAdditions and Config.rarityAdditions["Legendary"] or 20,
    stockMultiplier = Config.global and Config.global.stock_legendary_multiplier or 0.22,
    minRatio = Config.global and Config.global.stock_rare_min_ratio or 0
})
DB.registerTag("Rarity.UltraRare", {
    add = Config.rarityAdditions and Config.rarityAdditions["UltraRare"] or 27,
    stockMultiplier = Config.global and Config.global.stock_ultrarare_multiplier or 0.1,
    minRatio = Config.global and Config.global.stock_rare_min_ratio or 0
})
DB.registerTag("Quality.Waste", {
    add = Config.qualityAdditions and Config.qualityAdditions["Waste"] or -10.0,
    stockMultiplier = Config.global and Config.global.stock_waste_multiplier or 1.2
})
DB.registerTag("Quality.Luxury", {
    add = Config.qualityAdditions and Config.qualityAdditions["Luxury"] or 40.0,
    stockMultiplier = Config.global and Config.global.stock_luxury_multiplier or 0.7
})
DB.registerTag("Quality.Sterile", {
    add = Config.qualityAdditions and Config.qualityAdditions["Sterile"] or 14.0,
    stockMultiplier = 1.0
})

-- Flat token specific overrides
DB.registerTag("Firearm", {
    add = 65,
    stockMultiplier = 0.55,
    minRatio = 0
})
DB.registerTag("Ammo", {
    add = 10,
    stockMultiplier = 1.50,
    minRatio = 0.20
})
DB.registerTag("FoodNonPerishableCanned", {
    add = 24,
    stockMultiplier = 1.15
})
DB.registerTag("ContainerWearable", {
    add = 22
})
DB.registerTag("ElectronicsGenerator", {
    add = 240,
    stockMultiplier = 0.35,
    minRatio = 0
})

-- Item overrides (flat tokens in tags)
DB.registerItem("Base.Katana", {
    price = 450,
    tags = { "WeaponLongBlade", "Rarity.Rare" },
    stock = { min = 0, max = 1 }
})

return DB
