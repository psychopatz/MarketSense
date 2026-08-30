-- MarketSense liquid pricing.
-- Only measured liquid amount contributes to liquid value; vessel capacity is
-- not silently treated as filled content.  Fluid identity and player effects
-- provide the utility anchors, while empty, harmful, and unknown mixtures are
-- explicit negatives.

require "MarketSense/MS_Config"
require "MarketSense/MS_Core"
require "MarketSense/Pricing/MS_PricingUtils"
require "MarketSense/Pricing/MS_TransformPricing"

MarketSense = MarketSense or {}
MarketSense.LiquidPricing = MarketSense.LiquidPricing or {}
MarketSense.FluidPricing = nil

local LiquidPricing = MarketSense.LiquidPricing
local Config = MarketSense.ItemRuntimeConfig
local Core = MarketSense.Core
local Utils = require "MarketSense/Pricing/MS_PricingUtils"
local TransformPricing = MarketSense.TransformPricing

local DEFAULTS = {
    model = "liquid_v2", anchor = 5.0, floor = 1.0, ceiling = 300.0,
    amountWeight = 1.5, thirstWeight = 4.0, hungerWeight = 2.0,
    moodWeight = 0.04, medicalWeight = 2.0, fuelWeight = 2.0,
    waterAnchor = 2.0, mixturePenalty = 2.0, emptyPenalty = 8.0,
    poisonPenalty = 6.0, weightPenalty = 0.55, conditionFloor = 0.20,
    yieldMultiplier = 1.0, yieldPremium = 0.0,
}

local function number(value, fallback)
    value = tonumber(value)
    return value ~= nil and value or fallback
end

local function settings()
    local configured = Config and Config.liquidPricing
    if type(configured) ~= "table" then return DEFAULTS end
    local result = {}
    for key, fallback in pairs(DEFAULTS) do
        result[key] = configured[key] ~= nil and configured[key] or fallback
    end
    return result
end

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function hasAny(value, markers)
    local text = lower(value)
    for _, marker in ipairs(markers) do
        if string.find(text, marker, 1, true) then return true end
    end
    return false
end

local function benefit(value)
    return math.max(0, -number(value, 0))
end

function LiquidPricing.calculate(ctx, details)
    ctx = ctx or {}
    details = details or {}
    local c = settings()
    local fluidText = table.concat({
        ctx.fluidTypeString or "", ctx.fluidType or "", ctx.fluidCategory or "",
        ctx.fluidCategoryLower or "", details.primary or "",
    }, " ")
    local categories = ctx.fluidCategories or {}
    local heuristic = {
        model = tostring(c.model or DEFAULTS.model), status = "ready",
        subtype = details.primary or "LiquidUnknown",
        reason = "Liquid value combines measured amount, player effects, fluid function, and safety state.",
        isActualLiquid = ctx.isActualLiquid == true,
        isFluidContainer = ctx.isFluidContainer == true,
        fluidType = ctx.fluidType, fluidTypeString = ctx.fluidTypeString,
        fluidCategory = ctx.fluidCategory, fluidCategories = categories,
        fluidAmount = ctx.fluidAmount, fluidCapacity = ctx.fluidCapacity,
        fluidPrimaryAmount = ctx.fluidPrimaryAmount, fluidFilledRatio = ctx.fluidFilledRatio,
        fluidIsEmpty = ctx.fluidIsEmpty == true, fluidIsMixture = ctx.fluidIsMixture == true,
        weight = ctx.weight, hungerChange = ctx.hungerChange,
        thirstChange = ctx.thirstChange, unhappyChange = ctx.unhappyChange,
        boredomChange = ctx.boredomChange, stressChange = ctx.stressChange,
        alcoholPower = ctx.alcoholPower, painReduction = ctx.painReduction,
        fluReduction = ctx.fluReduction, foodSicknessChange = ctx.foodSicknessChange,
        isPoison = ctx.isPoison == true, isRotten = ctx.isRotten == true,
        positiveContributions = {}, negativeContributions = {},
        plannedPositiveAnchors = {
            "measured usable liquid amount, never vessel capacity alone",
            "verified hydration, nutrition, mood, or health utility",
            "verified fuel, medical, cleaning, dye, or industrial function",
            "safe transfer and processing compatibility",
            "stable shelf life and preserved runtime state",
            "exact child-item yield valued per output quantity",
        },
        plannedNegativeAnchors = {
            "empty or zero-amount content",
            "rotten, tainted, poisonous, or harmful state",
            "mixture with only a primary component known",
            "unknown fluid identity or player effect",
            "container weight, bulk, and handling burden",
            "required equipment, fuel, power, or processing",
            "capacity mistaken for liquid value",
        },
    }
    Utils.addYieldEvidence(heuristic, details)

    local transformScore, transform = TransformPricing.evaluate(ctx, details, {
        multiplier = c.yieldMultiplier, premium = c.yieldPremium,
        floor = c.floor, ceiling = c.ceiling,
    })
    if transformScore ~= nil then
        for key, value in pairs(transform) do heuristic[key] = value end
        heuristic.model = Utils.bundleModel(c.model)
        heuristic.status = "ready"
        heuristic.reason = "Deterministic transform valued from individualized child outputs."
        heuristic.yieldEvaluation = "valued"
        heuristic.positiveContributions = Core.deepCopy(transform.contributions)
        heuristic.score = transformScore
        details.priceHeuristic = heuristic
        return transformScore
    end
    heuristic.yieldEvaluation = "blocked"
    heuristic.yieldBlockedReason = type(transform) == "table" and transform.reason or nil

    local positives, negatives = heuristic.positiveContributions, heuristic.negativeContributions
    local amount = math.max(0, number(ctx.fluidAmount, number(ctx.fluidPrimaryAmount, 0)))
    local amountValue = math.min(14, amount * number(c.amountWeight, 1.5))
    local thirstValue = math.min(8, benefit(ctx.thirstChange) * number(c.thirstWeight, 4))
    local hungerValue = math.min(6, benefit(ctx.hungerChange) * number(c.hungerWeight, 2))
    local moodValue = math.min(5, (benefit(ctx.unhappyChange) + benefit(ctx.boredomChange)
        + benefit(ctx.stressChange)) * number(c.moodWeight, 0.04))
    local medicalValue = math.min(6, (number(ctx.painReduction, 0)
        + number(ctx.fluReduction, 0)) * number(c.medicalWeight, 2))
    local waterValue = hasAny(fluidText, { "water", "freshwater", "potable" })
        and number(c.waterAnchor, 2) or 0
    local fuelValue = hasAny(fluidText, { "fuel", "gasoline", "diesel" })
        and number(c.fuelWeight, 2) or 0
    Utils.addContribution(positives, "measured liquid amount", amountValue, amount)
    Utils.addContribution(positives, "thirst relief", thirstValue, ctx.thirstChange)
    Utils.addContribution(positives, "nutrition", hungerValue, ctx.hungerChange)
    Utils.addContribution(positives, "mood relief", moodValue, ctx.unhappyChange)
    Utils.addContribution(positives, "medical effect", medicalValue, ctx.painReduction)
    Utils.addContribution(positives, "safe water identity", waterValue, fluidText)
    Utils.addContribution(positives, "fuel identity", fuelValue, fluidText)

    local weightPenalty = math.min(12, math.max(0, number(ctx.weight, 0))
        * number(c.weightPenalty, 0.55))
    local emptyPenalty = (ctx.fluidIsEmpty == true or amount <= 0)
        and number(c.emptyPenalty, 8) or 0
    local mixturePenalty = ctx.fluidIsMixture == true and number(c.mixturePenalty, 2) or 0
    local poisonPenalty = ctx.isPoison == true and number(c.poisonPenalty, 6) or 0
    Utils.addContribution(negatives, "liquid weight", weightPenalty, ctx.weight)
    Utils.addContribution(negatives, "empty content", emptyPenalty, ctx.fluidIsEmpty)
    Utils.addContribution(negatives, "unknown mixture", mixturePenalty, ctx.fluidIsMixture)
    Utils.addContribution(negatives, "poison or harmful state", poisonPenalty, ctx.isPoison)
    local stateFactor = Utils.runtimeStateFactor(ctx, { conditionFloor = c.conditionFloor })
    local score, summary = Utils.scoreAnchors(c.anchor, positives, negatives, {
        stateFactor = stateFactor, floor = c.floor, ceiling = c.ceiling,
    })
    for key, value in pairs(summary) do heuristic[key] = value end
    heuristic.mode = "measured_fluid_utility"
    heuristic.score = score
    details.priceHeuristic = heuristic
    return score
end

return LiquidPricing
