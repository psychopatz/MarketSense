-- MarketSense clothing pricing.
-- Protection and environmental utility are normalized separately from
-- mobility cost.  This keeps a heavy jacket from winning simply because it
-- has a large raw insulation number.

require "MarketSense/MS_Config"
require "MarketSense/MS_Core"
require "MarketSense/Pricing/MS_PricingUtils"
require "MarketSense/Pricing/MS_TransformPricing"

MarketSense = MarketSense or {}
MarketSense.ClothingPricing = MarketSense.ClothingPricing or {}

local ClothingPricing = MarketSense.ClothingPricing
local Config = MarketSense.ItemRuntimeConfig
local Core = MarketSense.Core
local Utils = require "MarketSense/Pricing/MS_PricingUtils"
local TransformPricing = MarketSense.TransformPricing

local DEFAULTS = {
    model = "clothing_v2", anchor = 10.0, floor = 1.0,
    biteWeight = 7.0, scratchWeight = 5.0, bulletWeight = 5.0,
    insulationWeight = 0.12, windWeight = 0.05, waterWeight = 0.04,
    temperatureWeight = 0.04, accessoryAnchor = 1.0, weightPenalty = 0.65,
    speedPenalty = 4.0, neckPenalty = 1.0, conditionFloor = 0.20,
    yieldMultiplier = 0.90, yieldPremium = 0.0,
}

local function number(value, fallback)
    value = tonumber(value)
    return value ~= nil and value or fallback
end

local function settings()
    local configured = Config and Config.clothingPricing
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

function ClothingPricing.calculate(ctx, details)
    ctx = ctx or {}
    details = details or {}
    local c = settings()
    local body = lower(ctx.bodyLocation or ctx.bodyLocationToken)
    local heuristic = {
        model = tostring(c.model or DEFAULTS.model), status = "ready",
        subtype = details.primary or "Clothing",
        reason = "Clothing value combines protection, environmental coverage, mobility, and condition.",
        bodyLocation = ctx.bodyLocation, bodyLocationToken = ctx.bodyLocationToken,
        biteDefense = ctx.biteDefense, scratchDefense = ctx.scratchDefense,
        bulletDefense = ctx.bulletDefense, insulation = ctx.insulation,
        windResistance = ctx.windResistance, waterResistance = ctx.waterResistance,
        temperature = ctx.temperature, runSpeedModifier = ctx.runSpeedModifier,
        combatSpeedModifier = ctx.combatSpeedModifier,
        neckProtectionModifier = ctx.neckProtectionModifier,
        conditionMax = ctx.conditionMax, condition = ctx.condition,
        conditionRatio = ctx.conditionRatio, weight = ctx.weight,
        positiveContributions = {}, negativeContributions = {},
        plannedPositiveAnchors = {
            "effective bite, scratch, and bullet protection",
            "body-slot coverage and protection relevance",
            "insulation, wind, water, and temperature utility",
            "mobility or combat-speed benefit",
            "durability and repairability",
            "functional or verified accessory utility",
        },
        plannedNegativeAnchors = {
            "weight relative to delivered protection or utility",
            "run-speed, combat-speed, or fall-risk penalties",
            "holes, broken condition, and worn state",
            "blood, dirtiness, and wetness maintenance state",
            "neck-protection reduction or uncovered critical areas",
            "cosmetic or rarity labels without mechanical utility",
        },
    }
    Utils.addYieldEvidence(heuristic, details)

    local transformScore, transform = TransformPricing.evaluate(ctx, details, {
        multiplier = c.yieldMultiplier, premium = c.yieldPremium,
        floor = c.floor,
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
    local protection = math.min(16,
        number(ctx.biteDefense, 0) * number(c.biteWeight, 7)
        + number(ctx.scratchDefense, 0) * number(c.scratchWeight, 5)
        + number(ctx.bulletDefense, 0) * number(c.bulletWeight, 5))
    local environment = math.min(10,
        number(ctx.insulation, 0) * number(c.insulationWeight, 0.12)
        + number(ctx.windResistance, 0) * number(c.windWeight, 0.05)
        + number(ctx.waterResistance, 0) * number(c.waterWeight, 0.04)
        + number(ctx.temperature, 0) * number(c.temperatureWeight, 0.04))
    local accessory = (body ~= "" and body ~= "none")
        and number(c.accessoryAnchor, 1) or 0
    Utils.addContribution(positives, "protection", protection, ctx.biteDefense)
    Utils.addContribution(positives, "environmental coverage", environment, ctx.insulation)
    Utils.addContribution(positives, "body-slot utility", accessory, ctx.bodyLocation)

    local weightPenalty = math.min(12, math.max(0, number(ctx.weight, 0))
        * number(c.weightPenalty, 0.65))
    local speedPenalty = math.min(8,
        math.max(0, -number(ctx.runSpeedModifier, 0))
        + math.max(0, -number(ctx.combatSpeedModifier, 0)))
        * number(c.speedPenalty, 4)
    local neckPenalty = math.min(4, math.max(0, number(ctx.neckProtectionModifier, 0))
        * number(c.neckPenalty, 1))
    Utils.addContribution(negatives, "weight burden", weightPenalty, ctx.weight)
    Utils.addContribution(negatives, "mobility penalty", speedPenalty, ctx.runSpeedModifier)
    Utils.addContribution(negatives, "neck or coverage penalty", neckPenalty, ctx.neckProtectionModifier)
    local stateFactor = Utils.runtimeStateFactor(ctx, { conditionFloor = c.conditionFloor })
    local score, summary = Utils.scoreAnchors(c.anchor, positives, negatives, {
        stateFactor = stateFactor, floor = c.floor,
    })
    for key, value in pairs(summary) do heuristic[key] = value end
    heuristic.mode = "protection_and_coverage"
    heuristic.score = score
    details.priceHeuristic = heuristic
    return score
end

return ClothingPricing
