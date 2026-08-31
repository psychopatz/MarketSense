local T = require "tests/support/test"
T.addPackagePaths()

local vesselPricing = require "MarketSense/Pricing/MS_VesselPricing"
local containerPricing = require "MarketSense/Pricing/MS_ContainerPricing"
local pricing = require "MarketSense/MS_Pricing"

local function liquidContext(name, capacity)
    return {
        fullType = "Base.Harness" .. name,
        idLower = "harness" .. string.lower(name),
        typeName = "Harness" .. name,
        fluidContainerName = name,
        fluidCapacity = capacity,
        fluidAmount = capacity,
        fluidPrimaryAmount = capacity,
        isFluidContainer = true,
        isActualLiquid = true,
        fluidIsEmpty = false,
        weight = 0.3,
    }
end

local bottle = vesselPricing.calculate(liquidContext("BottleGlass", 1), {
    category = "Liquid",
})
local bucket = vesselPricing.calculate(liquidContext("Bucket", 10), {
    category = "Liquid",
})
T.equal(bottle.status, "ready", "filled liquid vessel is priced")
T.equal(bottle.source, "fluid_container", "runtime vessel source is explicit")
T.equal(bottle.state, "filled", "filled liquid state is explicit")
T.truthy(bucket.value > bottle.value,
    "larger vessel contributes more than a glass bottle")

MarketSense.PropertyReader = {
    buildContext = function(fullType)
        local name = string.match(fullType, "([^%.]+)$") or fullType
        if name == "CannedJar_Open" or name == "EmptyJar" then
            return {
                fullType = fullType,
                replaceOnUse = "Base.EmptyJar",
                fluidContainerName = "Jar",
                fluidCapacity = 1,
                capacity = 0,
                weight = 0.2,
                isFluidContainer = true,
            }
        end
        return {
            fullType = fullType,
            fluidContainerName = name == "TinCanEmpty" and "TinCan" or "Pot",
            fluidCapacity = name == "TinCanEmpty" and 0.3 or 1.5,
            capacity = 0,
            weight = name == "TinCanEmpty" and 0.1 or 1,
            isFluidContainer = true,
        }
    end,
}

local cooked = vesselPricing.calculate({
    fullType = "Base.RicePot",
    moduleName = "Base",
    idLower = "ricepot",
    replaceOnUse = "Base.Pot",
}, {
    category = "Food",
})
T.equal(cooked.source, "replace_on_use", "prepared food uses retained vessel")
T.equal(cooked.state, "retained", "prepared food marks the vessel retained")
T.equal(cooked.vesselFullType, "Base.Pot", "retained vessel full type is preserved")
T.truthy(cooked.value > 0, "retained cooking vessel contributes value")

local openedCan = vesselPricing.calculate({
    fullType = "Base.CannedPeasOpen",
    moduleName = "Base",
    idLower = "cannedpeasopen",
    replaceOnUse = "Base.TinCanEmpty",
}, {
    category = "Food",
    tags = { "FoodNonPerishableCanned" },
})
local sealedCan = vesselPricing.calculate({
    fullType = "Base.CannedPeas",
    moduleName = "Base",
    idLower = "cannedpeas",
    openingRecipe = "OpenCannedFood",
}, {
    category = "Food",
    tags = { "FoodNonPerishableCanned" },
})
T.equal(openedCan.state, "opened", "opened canned food is marked opened")
T.equal(sealedCan.state, "sealed", "sealed canned food is marked sealed")
T.truthy(sealedCan.value > openedCan.value,
    "sealed packaging is worth more than opened packaging")

local sealedJar = vesselPricing.calculate({
    fullType = "Base.CannedJar",
    moduleName = "Base",
    idLower = "cannedjar",
    foodVariantEvidence = {
        status = "verified",
        sourceFullType = "Base.CannedJar_Open",
    },
}, {
    category = "Food",
    tags = { "FoodNonPerishableCanned" },
})
T.equal(sealedJar.source, "variant_replacement",
    "sealed food can derive its vessel from an opened counterpart")
T.equal(sealedJar.state, "sealed",
    "derived sealed vessel keeps sealed state")
T.equal(sealedJar.vesselName, "Jar",
    "derived vessel keeps the opened counterpart container")

local emptyFluidContainer = {
    fullType = "Base.HarnessBucket",
    fluidContainerName = "Bucket",
    fluidCapacity = 10,
    capacity = 0,
    isFluidContainer = true,
    isActualLiquid = false,
    weight = 1,
}
local emptyDetails = { category = "Container", primary = "ContainerLiquid" }
local emptyScore = containerPricing.calculate(emptyFluidContainer, emptyDetails)
T.equal(emptyDetails.priceHeuristic.effectiveCapacity, 10,
    "empty fluid container uses fluid capacity")
T.truthy(emptyScore > 14, "fluid capacity raises empty container value")

-- A filled dish must remain more valuable than the empty vessel it returns.
-- These values mirror the vanilla Pot/RicePot definitions: Pot is a 1.5L,
-- 1.0-weight fluid container and RicePot is a 3.0-weight cooked food item
-- that returns Base.Pot after its contents are removed.
local potContext = {
    fullType = "Base.Pot",
    fluidContainerName = "Pot",
    fluidCapacity = 1.5,
    isFluidContainer = true,
    isActualLiquid = false,
    fluidIsEmpty = true,
    capacity = 0,
    weight = 1.0,
}
local potDetails = {
    category = "Container",
    primary = "ContainerLiquid",
    tags = { "ContainerLiquid", "Quality.Standard", "Origin.Vanilla", "Rarity.Common" },
    expandedTags = { "Container", "ContainerLiquid", "Quality.Standard", "Origin.Vanilla", "Rarity.Common" },
    classificationDetails = {},
}
potDetails.rawScore = pricing.calculateRawScore(potContext, potDetails)
local emptyPotPrice = pricing.applyBalances(potContext, potDetails)

local riceContext = {
    fullType = "Base.RicePot",
    moduleName = "Base",
    idLower = "ricepot",
    replaceOnUse = "Base.Pot",
    weight = 3.0,
    hungerChange = -0.10,
    calories = 720,
    carbohydrates = 0,
    lipids = 48,
    proteins = 78,
    isCooked = true,
    hasFoodNutritionEvidence = true,
    foodDaysFresh = 3,
    foodDaysRotten = 6,
}
local riceDetails = {
    category = "Food",
    primary = "FoodDishPerishable",
    tags = { "FoodDishPerishable", "Quality.Standard", "Origin.Vanilla", "Rarity.Common" },
    expandedTags = { "Food", "FoodDishPerishable", "Quality.Standard", "Origin.Vanilla", "Rarity.Common" },
    classificationDetails = {},
}
riceDetails.rawScore = pricing.calculateRawScore(riceContext, riceDetails)
local filledRicePrice = pricing.applyBalances(riceContext, riceDetails)
T.truthy(filledRicePrice > emptyPotPrice,
    "filled food remains more valuable than its returned empty pot")
T.equal(riceDetails.priceHeuristic.vesselName, "Pot",
    "filled food price order uses the actual returned pot")

local DB = MarketSense.HeuristicsDB
DB.registerItem("Base.HarnessInstance", { price = 999 })
local instanceDetails = {
    fullType = "Base.HarnessInstance",
    category = "Liquid",
    primary = "LiquidWater",
    tags = { "LiquidWater" },
    expandedTags = { "LiquidWater", "Liquid" },
    rawScore = 5,
    priceHeuristic = { model = "liquid_v2", anchor = 5 },
    _instancePricing = true,
}
local instancePrice = pricing.applyBalances(liquidContext("Bucket", 10), instanceDetails)
T.truthy(instancePrice ~= 999,
    "instance pricing bypasses definition exact price for transferred vessels")

T.finish("marketsense_vessel_pricing_smoke")
