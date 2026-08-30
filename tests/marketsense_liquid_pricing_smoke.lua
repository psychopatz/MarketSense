local T = require "tests/support/test"
T.addPackagePaths()

require "MarketSense/MS_Stock"
local pricing = assert(require "MarketSense/MS_Pricing")

local context = {
    fullType = "Base.HarnessWaterBottle",
    fluidType = "Water",
    fluidTypeString = "Water",
    fluidCategory = "Beverage",
    fluidCategories = { "Beverage", "Liquid" },
    fluidAmount = 2,
    fluidCapacity = 2,
    fluidPrimaryAmount = 2,
    fluidFilledRatio = 1,
    fluidIsEmpty = false,
    fluidIsMixture = false,
    fluidContainerName = "Bottle",
    isFluidContainer = true,
    isActualLiquid = true,
    weight = 0.4,
    thirstChange = -0.3,
    isPoison = false,
}
local details = {
    category = "Liquid",
    primary = "LiquidWater",
    tags = { "LiquidWater" },
    expandedTags = { "LiquidWater", "Liquid" },
    classificationDetails = { source = "fluid_exact", tag = "LiquidWater" },
    rawScore = 0,
}

local score = pricing.calculateRawScore(context, details)
T.truthy(score > 5, "measured liquid utility raises its anchor")
T.equal(details.priceHeuristic.model, "liquid_v2",
    "liquid pricing model is exposed")
T.equal(details.priceHeuristic.status, "ready",
    "liquid pricing model is ready")
T.equal(details.priceHeuristic.fluidPrimaryAmount, 2,
    "liquid heuristic exposes primary amount")
T.equal(details.priceHeuristic.fluidFilledRatio, 1,
    "liquid heuristic exposes fill ratio")
T.falsy(details.priceHeuristic.fluidIsMixture,
    "single-fluid heuristic is not marked as mixture")
T.falsy(details.priceHeuristic.pricePerLiter,
    "legacy per-litre anchor is removed")
T.falsy(details.priceHeuristic.contentValue,
    "legacy content value is removed")

details.rawScore = score
T.equal(pricing.applyBalances(context, details),
    MarketSense.Core.round(MarketSense.Core.priceClamp(score)),
    "liquid pricing keeps heuristic score without legacy flat additions")

local stale = pricing.applyOverridesOnly(context, {
    fullType = context.fullType,
    category = "Liquid",
    primary = "LiquidWater",
    tags = { "LiquidWater" },
    rawScore = 999,
    price = 999,
}, true)
T.equal(stale.priceHeuristic.model, "liquid_v2",
    "cached legacy liquid score is rebuilt")
T.truthy(stale.price < 999, "cached legacy liquid dollars are discarded")

T.finish("marketsense_liquid_pricing_smoke")
