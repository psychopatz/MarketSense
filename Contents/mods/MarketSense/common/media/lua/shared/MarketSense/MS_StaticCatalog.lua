-- MS_StaticCatalog.lua
-- Seed catalog with flat token primary tags.
MarketSense = MarketSense or {}
MarketSense.StaticCatalog = MarketSense.StaticCatalog or {
    ["Base.Katana"] = {
        fullType = "Base.Katana",
        moduleName = "Base",
        typeName = "Katana",
        category = "Weapon",
        primary = "WeaponLongBlade",
        tags = { "WeaponLongBlade", "Rarity.Rare" },
        expandedTags = { "WeaponLongBlade", "WeaponMelee", "Weapon", "Rarity.Rare" },
        price = 450,
        rawScore = 320,
        confidence = 0.95,
        stock = { min = 0, max = 1 }
    },
    ["Base.Hammer"] = {
        fullType = "Base.Hammer",
        moduleName = "Base",
        typeName = "Hammer",
        category = "Tool",
        primary = "ToolCarpentry",
        tags = { "ToolCarpentry", "Quality.Standard" },
        expandedTags = { "ToolCarpentry", "ToolCraft", "Tool", "Quality.Standard" },
        price = 42,
        rawScore = 30,
        confidence = 0.90,
        stock = { min = 2, max = 6 }
    },
    ["Base.Bandage"] = {
        fullType = "Base.Bandage",
        moduleName = "Base",
        typeName = "Bandage",
        category = "Medical",
        primary = "FirstAid",
        tags = { "FirstAid", "Quality.Standard" },
        expandedTags = { "FirstAid", "Medical", "Quality.Standard" },
        price = 24,
        rawScore = 18,
        confidence = 0.92,
        stock = { min = 3, max = 10 }
    }
}

return MarketSense.StaticCatalog
