DynamicTrading = DynamicTrading or {}
DynamicTrading.StaticCatalog = DynamicTrading.StaticCatalog or {
    ["Base.Katana"] = {
        fullType = "Base.Katana",
        moduleName = "Base",
        typeName = "Katana",
        category = "Weapon",
        primary = "Weapon.Melee.Blade",
        tags = {
            "Weapon.Melee.Blade",
            "Rarity.Rare",
            "Quality.Luxury"
        },
        expandedTags = {
            "Weapon.Melee.Blade",
            "Weapon.Melee",
            "Weapon",
            "Rarity.Rare",
            "Rarity",
            "Quality.Luxury",
            "Quality"
        },
        price = 450,
        rawScore = 320,
        confidence = 0.95,
        stock = {
            min = 0,
            max = 1
        }
    },
    ["Base.Hammer"] = {
        fullType = "Base.Hammer",
        moduleName = "Base",
        typeName = "Hammer",
        category = "Tool",
        primary = "Tool.Crafting",
        tags = {
            "Tool.Crafting",
            "Tool.Durable",
            "Quality.Standard"
        },
        expandedTags = {
            "Tool.Crafting",
            "Tool",
            "Tool.Durable",
            "Quality.Standard",
            "Quality"
        },
        price = 42,
        rawScore = 30,
        confidence = 0.90,
        stock = {
            min = 2,
            max = 6
        }
    },
    ["Base.Bandage"] = {
        fullType = "Base.Bandage",
        moduleName = "Base",
        typeName = "Bandage",
        category = "Medical",
        primary = "Medical.Healthcare",
        tags = {
            "Medical.Healthcare",
            "Medical.Consumable",
            "Quality.Standard"
        },
        expandedTags = {
            "Medical.Healthcare",
            "Medical",
            "Medical.Consumable",
            "Quality.Standard",
            "Quality"
        },
        price = 24,
        rawScore = 18,
        confidence = 0.92,
        stock = {
            min = 3,
            max = 10
        }
    }
}

return DynamicTrading.StaticCatalog
