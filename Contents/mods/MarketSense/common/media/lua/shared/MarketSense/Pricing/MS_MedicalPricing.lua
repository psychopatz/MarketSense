-- MarketSense medical pricing.
-- Treatment outcomes are the anchor; names, rarity, and loot origin are only
-- explanatory evidence. Missing medical APIs remain neutral instead of being
-- mistaken for a zero-effect treatment.

require "MarketSense/MS_Config"
require "MarketSense/MS_Core"
require "MarketSense/Pricing/MS_PricingUtils"
require "MarketSense/Pricing/MS_TransformPricing"

MarketSense = MarketSense or {}
MarketSense.MedicalPricing = MarketSense.MedicalPricing or {}

local MedicalPricing = MarketSense.MedicalPricing
local Config = MarketSense.ItemRuntimeConfig
local Core = MarketSense.Core
local Utils = require "MarketSense/Pricing/MS_PricingUtils"
local TransformPricing = MarketSense.TransformPricing

local DEFAULTS = {
    model = "medical_v2", anchor = 30.0, floor = 1.0,
    bandageWeight = 6.0, infectionWeight = 7.0, alcoholWeight = 3.0,
    painWeight = 0.08, fluWeight = 0.08, sicknessReliefWeight = 0.08,
    medicalLootAnchor = 1.5, useWeight = 0.8, weightPenalty = 0.8,
    harmfulPenalty = 4.0, conditionFloor = 0.20,
    yieldMultiplier = 0.85, yieldPremium = 0.0,
}

local function number(value, fallback)
    value = tonumber(value)
    return value ~= nil and value or fallback
end

local function settings()
    local configured = Config and Config.medicalPricing
    if type(configured) ~= "table" then return DEFAULTS end
    local result = {}
    for key, fallback in pairs(DEFAULTS) do
        result[key] = configured[key] ~= nil and configured[key] or fallback
    end
    return result
end

local function relief(value)
    value = number(value, 0)
    return math.max(0, -value)
end

function MedicalPricing.calculate(ctx, details)
    ctx = ctx or {}
    details = details or {}
    local c = settings()
    local heuristic = {
        model = tostring(c.model or DEFAULTS.model), status = "ready",
        subtype = details.primary or "Medical",
        reason = "Medical value combines verified treatment outcomes, doses, and patient-facing utility.",
        classifierSource = type(details.classificationDetails) == "table"
            and details.classificationDetails.source or nil,
        classifierTag = type(details.classificationDetails) == "table"
            and details.classificationDetails.tag or nil,
        isMedicalLoot = ctx.isMedicalLoot == true, canBandage = ctx.canBandage,
        useSelf = ctx.useSelf, bandagePower = ctx.bandagePower,
        reduceInfectionPower = ctx.reduceInfectionPower, alcoholPower = ctx.alcoholPower,
        painReduction = ctx.painReduction, fluReduction = ctx.fluReduction,
        foodSicknessChange = ctx.foodSicknessChange, conditionMax = ctx.conditionMax,
        condition = ctx.condition, conditionRatio = ctx.conditionRatio,
        weight = ctx.weight, useDelta = ctx.useDelta, maxUses = ctx.maxUses,
        remainingUsesRatio = ctx.remainingUsesRatio, replaceOnUse = ctx.replaceOnUse,
        replaceOnUseOn = ctx.replaceOnUseOn, isDisappearOnUse = ctx.isDisappearOnUse,
        positiveContributions = {}, negativeContributions = {},
        plannedPositiveAnchors = {
            "verified treatment effect and patient-facing outcome",
            "wound coverage, bandage power, and infection reduction",
            "pain, flu, food-sickness, or other verified symptom relief",
            "deterministic doses, remaining uses, and replacement output",
            "sterility or clean-use state when mechanically verified",
            "exact child-item yield valued per output quantity",
        },
        plannedNegativeAnchors = {
            "weight, bulk, and handling cost per treatment delivered",
            "depleted uses, consumed-on-use state, or missing replacement",
            "broken, damaged, expired, or unusable state",
            "side effects, toxicity, addiction, or operating risk",
            "narrow treatment compatibility or patient restrictions",
            "names or rarity without effect evidence",
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
    local bandage = math.min(8, number(ctx.bandagePower, 0) * number(c.bandageWeight, 6))
    local infection = math.min(8, number(ctx.reduceInfectionPower, 0)
        * number(c.infectionWeight, 7))
    local alcohol = math.min(5, number(ctx.alcoholPower, 0) * number(c.alcoholWeight, 3))
    local symptoms = math.min(8, number(ctx.painReduction, 0) * number(c.painWeight, 0.08)
        + number(ctx.fluReduction, 0) * number(c.fluWeight, 0.08)
        + relief(ctx.foodSicknessChange) * number(c.sicknessReliefWeight, 0.08))
    local loot = ctx.isMedicalLoot == true and number(c.medicalLootAnchor, 1.5) or 0
    local uses = math.min(5, math.max(0, number(ctx.maxUses, 0))
        * number(c.useWeight, 0.8))
    Utils.addContribution(positives, "bandage treatment", bandage, ctx.bandagePower)
    Utils.addContribution(positives, "infection treatment", infection, ctx.reduceInfectionPower)
    Utils.addContribution(positives, "alcohol treatment", alcohol, ctx.alcoholPower)
    Utils.addContribution(positives, "symptom relief", symptoms, ctx.painReduction or ctx.fluReduction)
    Utils.addContribution(positives, "medical classification", loot, ctx.isMedicalLoot)
    Utils.addContribution(positives, "usable doses", uses, ctx.maxUses)

    local weightPenalty = math.min(10, math.max(0, number(ctx.weight, 0))
        * number(c.weightPenalty, 0.8))
    local harmfulPenalty = (number(ctx.foodSicknessChange, 0) > 0
        or ctx.isPoison == true) and number(c.harmfulPenalty, 4) or 0
    Utils.addContribution(negatives, "weight burden", weightPenalty, ctx.weight)
    Utils.addContribution(negatives, "harmful or toxic effect", harmfulPenalty, ctx.isPoison)
    local stateFactor = Utils.runtimeStateFactor(ctx, { conditionFloor = c.conditionFloor })
    local score, summary = Utils.scoreAnchors(c.anchor, positives, negatives, {
        stateFactor = stateFactor, floor = c.floor,
    })
    for key, value in pairs(summary) do heuristic[key] = value end
    heuristic.mode = "treatment_effects"
    heuristic.score = score
    details.priceHeuristic = heuristic
    return score
end

return MedicalPricing
