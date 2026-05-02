require "MarketSense/DT_Core"

DynamicTrading = DynamicTrading or {}
DynamicTrading.HeuristicsDB = DynamicTrading.HeuristicsDB or {
    items = {},
    tags = {},
    categories = {},
    modules = {}
}

local DB = DynamicTrading.HeuristicsDB
local Core = DynamicTrading.Core

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
    stockMultiplier = 0.80,
    minRatio = 0.05
})

DB.registerCategory("Medical", {
    stockMultiplier = 1.10,
    minRatio = 0.20
})

DB.registerCategory("Food", {
    stockMultiplier = 1.20,
    minRatio = 0.25
})

DB.registerCategory("Container", {
    stockMultiplier = 0.90,
    minRatio = 0.10
})

DB.registerTag("Rarity.Uncommon", {
    mult = 1.18,
    stockMultiplier = 0.85
})

DB.registerTag("Rarity.Rare", {
    mult = 1.45,
    stockMultiplier = 0.55,
    minRatio = 0
})

DB.registerTag("Rarity.Legendary", {
    mult = 2.10,
    stockMultiplier = 0.22,
    minRatio = 0
})

DB.registerTag("Quality.Waste", {
    mult = 0.30,
    stockMultiplier = 1.20
})

DB.registerTag("Quality.Luxury", {
    mult = 1.60,
    stockMultiplier = 0.70
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
