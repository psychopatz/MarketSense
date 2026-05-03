require "MarketSense/DT_Core"
require "MarketSense/DT_Config"

DynamicTrading = DynamicTrading or {}
DynamicTrading.HeuristicsDB = DynamicTrading.HeuristicsDB or {
    items = {},
    tags = {},
    categories = {},
    modules = {}
}

local DB = DynamicTrading.HeuristicsDB
local Core = DynamicTrading.Core
local Config = DynamicTrading.ItemRuntimeConfig

local function register(target, key, data)
    if type(key) ~= "string" or key == "" or type(data) ~= "table" then
        return
    end
    target[key] = Core.deepCopy(data)
end

function DB.registerItem(fullType, data)
    register(DB.items, fullType, data)
end

function DB.registerTag(tag, data)
    register(DB.tags, tag, data)
end

function DB.registerCategory(category, data)
    register(DB.categories, category, data)
end

function DB.registerModule(moduleName, data)
    register(DB.modules, moduleName, data)
end

function DB.getItem(fullType)
    return DB.items[fullType]
end

function DB.getTag(tag)
    return DB.tags[tag]
end

function DB.getCategory(category)
    return DB.categories[category]
end

function DB.getModule(moduleName)
    return DB.modules[moduleName]
end

DB.registerCategory("Weapon", {
    stockMultiplier = Config.categories.Weapon and Config.categories.Weapon.stock_multiplier or 0.80,
    minRatio = Config.categories.Weapon and Config.categories.Weapon.stock_min_ratio or 0.05
})

DB.registerCategory("Medical", {
    stockMultiplier = Config.categories.Medical and Config.categories.Medical.stock_multiplier or 1.10,
    minRatio = Config.categories.Medical and Config.categories.Medical.stock_min_ratio or 0.20
})

DB.registerCategory("Food", {
    stockMultiplier = Config.categories.Food and Config.categories.Food.stock_multiplier or 1.20,
    minRatio = Config.categories.Food and Config.categories.Food.stock_min_ratio or 0.25
})

DB.registerCategory("Container", {
    stockMultiplier = Config.categories.Container and Config.categories.Container.stock_multiplier or 0.90,
    minRatio = Config.categories.Container and Config.categories.Container.stock_min_ratio or 0.10
})

DB.registerCategory("Clothing", {
    stockMultiplier = Config.categories.Clothing and Config.categories.Clothing.stock_multiplier or 0.95,
    minRatio = Config.categories.Clothing and Config.categories.Clothing.stock_min_ratio or 0.18
})

DB.registerCategory("Tool", {
    stockMultiplier = Config.categories.Tool and Config.categories.Tool.stock_multiplier or 0.8,
    minRatio = Config.categories.Tool and Config.categories.Tool.stock_min_ratio or 0.12
})

DB.registerCategory("Electronics", {
    stockMultiplier = Config.categories.Electronics and Config.categories.Electronics.stock_multiplier or 0.55,
    minRatio = Config.categories.Electronics and Config.categories.Electronics.stock_min_ratio or 0.05
})

DB.registerCategory("Literature", {
    stockMultiplier = Config.categories.Literature and Config.categories.Literature.stock_multiplier or 1.0,
    minRatio = Config.categories.Literature and Config.categories.Literature.stock_min_ratio or 0.16
})

DB.registerCategory("Resource", {
    stockMultiplier = Config.categories.Resource and Config.categories.Resource.stock_multiplier or 1.1,
    minRatio = Config.categories.Resource and Config.categories.Resource.stock_min_ratio or 0.18
})

DB.registerCategory("Building", {
    stockMultiplier = Config.categories.Building and Config.categories.Building.stock_multiplier or 0.9,
    minRatio = Config.categories.Building and Config.categories.Building.stock_min_ratio or 0.10
})


DB.registerTag("Rarity.Uncommon", {
    mult = Config.rarityMultipliers["Uncommon"] or 1.18,
    stockMultiplier = Config.global.stock_uncommon_multiplier or 0.85
})

DB.registerTag("Rarity.Rare", {
    mult = Config.rarityMultipliers["Rare"] or 1.45,
    stockMultiplier = Config.global.stock_rare_multiplier or 0.55,
    minRatio = Config.global.stock_rare_min_ratio or 0
})

DB.registerTag("Rarity.Legendary", {
    mult = Config.rarityMultipliers["Legendary"] or 2.10,
    stockMultiplier = Config.global.stock_legendary_multiplier or 0.22,
    minRatio = Config.global.stock_rare_min_ratio or 0
})

DB.registerTag("Rarity.UltraRare", {
    mult = Config.rarityMultipliers["UltraRare"] or 2.75,
    stockMultiplier = Config.global.stock_ultrarare_multiplier or 0.10,
    minRatio = Config.global.stock_rare_min_ratio or 0
})


DB.registerTag("Quality.Waste", {
    mult = Config.qualityMultipliers["Waste"] or 0.30,
    stockMultiplier = Config.global.stock_waste_multiplier or 1.20
})

DB.registerTag("Quality.Luxury", {
    mult = Config.qualityMultipliers["Luxury"] or 1.60,
    stockMultiplier = Config.global.stock_luxury_multiplier or 0.70
})

DB.registerTag("Quality.Sterile", {
    mult = Config.qualityMultipliers["Sterile"] or 1.18,
    stockMultiplier = 1.0
})

DB.registerTag("Weapon.Ranged.Firearm", {
    add = 65,
    stockMultiplier = 0.55,
    minRatio = 0
})

DB.registerTag("Weapon.Ranged.Ammo", {
    add = 10,
    stockMultiplier = 1.50,
    minRatio = 0.20
})

DB.registerTag("Food.NonPerishable.Canned", {
    add = 24,
    stockMultiplier = 1.15
})

DB.registerTag("Container.Bag.Backpack", {
    add = 22
})

DB.registerTag("Electronics.Generator", {
    add = 240,
    stockMultiplier = 0.35,
    minRatio = 0
})

-- Example mod balance:
-- DB.registerModule("SomeModModule", {
--     mult = 1.15,
--     stockMultiplier = 0.80
-- })

DB.registerItem("Base.Katana", {
    price = 450,
    tags = {
        "Weapon.Melee.Blade",
        "Rarity.Rare"
    },
    stock = {
        min = 0,
        max = 1
    }
})

return DB
