local T = require "tests/support/test"
T.addPackagePaths()

-- Simulate the file that the Python editor writes without touching the real
-- working tree.  The production module still loads this through pcall(require)
-- so a missing override file remains a valid installation state.
package.preload["MarketSense/Pricing/MS_LiquidPricing_Overrides_Data"] = function()
    return {
        liquids = {
            Water = { pricePerLiter = 7.5 },
        },
        primaryDefaults = {
            LiquidFuel = 9.0,
        },
        defaultPricePerLiter = 6.0,
    }
end

require "MarketSense/MS_Stock"
local fluidPricing = assert(require "MarketSense/Pricing/MS_FluidPricing")
local water = fluidPricing.getDefinition({ fluidType = "Water" }, { primary = "LiquidWater" })
T.equal(water.pricePerLiter, 7.5, "exact liquid override")
T.equal(water.source, "override", "exact liquid override source")

local fuel = fluidPricing.getDefinition({ fluidType = "NewFuel" }, { primary = "LiquidFuel" })
T.equal(fuel.pricePerLiter, 9.0, "family liquid override")
T.equal(fuel.source, "override", "family liquid override source")

local unknown = fluidPricing.getDefinition({ fluidType = "NewUnknown" }, { primary = "NoSuchFamily" })
T.equal(unknown.pricePerLiter, 6.0, "global liquid fallback override")
T.equal(unknown.source, "default_override", "global fallback override source")

local details = {}
local value = fluidPricing.calculate({
    fluidType = "Water",
    fluidCapacity = 2,
    fluidPrimaryAmount = 2,
}, details)
T.equal(value, 15, "exact liquid override calculates by litre")
T.equal(details.priceHeuristic.pricePerLiter, 7.5, "price audit exposes override")
T.equal(details.priceHeuristic.volume, 2, "price audit exposes litres")
T.truthy(details.priceHeuristic.vesselIndependent, "price audit is vessel independent")

T.finish("marketsense_liquid_pricing_smoke")
