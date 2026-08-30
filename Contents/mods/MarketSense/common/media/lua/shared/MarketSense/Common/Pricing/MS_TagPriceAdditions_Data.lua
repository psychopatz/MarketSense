-- MarketSense Tag Price Additions
-- Flat token additions used by the standalone MarketSense runtime.

return {
    tagAdditions = {
        -- Root categories
        -- Liquid price comes from the dedicated per-litre fluid data table;
        -- keep the taxonomy root neutral so it cannot charge for the vessel.
        ["Liquid"]         = 0,
        ["Medical"]        = 40,
        ["Tool"]           = 25,
        ["Container"]      = 30,
        ["Electronics"]    = 20,
        ["Resource"]       = 8,
        ["Building"]       = 14,
        ["Misc"]           = 2,
        -- Tool subtypes
        ["ToolCarpentry"]    = 12,
        ["ToolBlacksmith"]   = 14,
        ["ToolWelding"]      = 16,
        ["ToolMechanics"]    = 14,
        ["ToolTailoring"]    = 8,
        ["ToolButchering"]   = 8,
        ["ToolFarming"]      = 10,
        ["Cooking"]          = 9,
        -- Container subtypes
        ["ContainerWearable"]       = 40,
        ["ContainerWearableAmmo"]   = 20,
        ["ContainerAmmo"]           = 15,
        ["ContainerBox"]            = 6,
        ["ContainerLiquid"]         = 10,
        -- Electronics subtypes
        ["ElectronicsGenerator"]    = 240,
        ["ElectronicsBattery"]      = 10,
        ["ElectronicsRadio"]        = 36,
        ["ElectronicsTelevision"]   = 24,
        ["ElectronicsCommunicator"] = 45,
        ["ElectronicsTransmitter"]  = 50,
        -- Resource subtypes
        ["ResourceFuel"]            = 50,
        ["MaterialMetalworking"]    = 12,
        ["MaterialTailoring"]       = 8,
        ["MaterialChemical"]        = 18,
        ["MaterialMaintenance"]     = 10,
        -- Gardening subtypes
        ["GardeningSeed"]           = 8,
        ["GardeningSeedPacket"]     = 14,
        -- Descriptor overlays (kept as dot-notation)
        ["Quality.Luxury"]          = 40,
        ["Quality.Waste"]           = -10,
        ["Rarity.Common"]           = 11,
        ["Rarity.Uncommon"]         = 14,
        ["Rarity.Rare"]             = 17,
        ["Rarity.Legendary"]        = 30,
        ["Theme.Combat"]            = 17,
        ["Theme.Industrial"]        = 15,
        ["Theme.Militia"]           = 20,
        ["Theme.Police"]            = 13,
        ["Theme.Primitive"]         = 7,
        ["Theme.Survival"]          = 20,
        ["Theme.Winter"]            = 15,
    },
}
