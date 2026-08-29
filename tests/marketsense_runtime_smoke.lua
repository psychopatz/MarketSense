local T = require "tests/support/test"
T.addPackagePaths()

_G.unpack = _G.unpack or table.unpack
_G.DynamicTrading = { Log = function() end }

local runtimeRules = assert(T.load("MarketSense/MS_RuntimeRules.lua"))
local shared = assert(T.load("MarketSense/ItemsRegistry/MS_ItemsRegistry_Shared.lua"))

T.truthy(runtimeRules.apply({
    overridesById = {
        ["Base.HarnessRule"] = { price = 42, stock = { min = 2, max = 5 } },
    },
}), "runtime rule application")
local override = assert(runtimeRules.getOverride("Base.HarnessRule"))
T.equal(override.price, 42, "runtime price override")
T.equal(override.stock.min, 2, "runtime stock override")
T.equal(override.stock.max, 5, "runtime stock override max")

local empty = shared.buildEmptyCatalog({ activeModsHash = "test" }, "harness")
T.equal(type(empty.items), "table", "empty catalog has item map")
T.equal(empty.source, "harness", "empty catalog source")
T.equal(shared.stableHash({ "a", "b" }), shared.stableHash({ "a", "b" }), "stable hash")

_G.getGameTime = function()
    return {
        getYear = function() return 1993 end,
        getMonth = function() return 6 end,
        getDay = function() return 15 end,
        getTimeOfDay = function() return 13.5 end,
        getMinutes = function() return 30 end,
    }
end
T.equal(shared.getTimestamp(), "PZ-1993-07-15T13:30:00", "PZ timestamp")
_G.getGameTime = nil

T.finish("marketsense_runtime_smoke")
