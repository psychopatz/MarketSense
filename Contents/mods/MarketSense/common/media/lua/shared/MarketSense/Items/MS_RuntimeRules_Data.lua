-- MarketSense Runtime Rules Data
-- Edited by MarketSense Inspector on 2026-08-30T04:10:49+00:00
-- Standalone MarketSense runtime contract.
-- Changes made here are consumed by the MarketSense Lua mod.

return {
    ["blacklist"] = {
        "Animal",
        "Bag_FoodCanned",
        "Base.AxeTest",
        "Base.BareHands",
        "FISH_DEV_ITEM",
        "Money",
        "MoneyBundle",
        "Moveable",
        "ScratchTicket",
        "ScratchTicket_Loser",
        "ScratchTicket_Winner",
        "TestHotDrink",
        "TestMug",
        "TestWaterMug",
        "Wallet",
        "Wallet_Female",
        "Wallet_Male",
        "YardstickDEBUG",
        "Base.CorpseFemale"
    },
    ["blacklistPatterns"] = {},
    ["overrides"] = {
        {
            ["id"] = "Base.Battery",
            ["price"] = 50
        }
    },
    ["whitelist"] = {},
    ["whitelistPatterns"] = {}
}
