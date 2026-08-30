-- MarketSense weapon pricing.
-- Damage and reach are useful only after they are normalized to the weapon
-- family.  Recipe demand is included for weapon/tool hybrids such as hammers.

require "MarketSense/MS_Config"
require "MarketSense/MS_Core"
require "MarketSense/Pricing/MS_PricingUtils"
require "MarketSense/Pricing/MS_ToolPricing"
require "MarketSense/Pricing/MS_TransformPricing"

MarketSense = MarketSense or {}
MarketSense.WeaponPricing = MarketSense.WeaponPricing or {}

local WeaponPricing = MarketSense.WeaponPricing
local Config = MarketSense.ItemRuntimeConfig
local Core = MarketSense.Core
local Utils = require "MarketSense/Pricing/MS_PricingUtils"
local ToolPricing = MarketSense.ToolPricing
local TransformPricing = MarketSense.TransformPricing
local number = Utils.number

local DEFAULTS = {
    model = "weapon_v2",
    anchor = 18.0,
    floor = 1.0,
    ceiling = 300.0,
    damageWeight = 4.0,
    rangeWeight = 2.0,
    hitWeight = 2.0,
    reliabilityWeight = 0.04,
    hitChanceWeight = 0.03,
    recipeDemandCap = 30.0,
    weightPenalty = 1.25,
    twoHandPenalty = 2.0,
    conditionFloor = 0.15,
}

local function settings()
    local configured = Config and Config.weaponPricing
    if type(configured) ~= "table" then return DEFAULTS end
    local result = {}
    for key, fallback in pairs(DEFAULTS) do
        result[key] = configured[key] ~= nil and configured[key] or fallback
    end
    return result
end

local function text(value)
    return string.lower(tostring(value or ""))
end

local function familyAnchor(family)
    family = text(family)
    if string.find(family, "explosive", 1, true) then return 5 end
    if string.find(family, "firearm", 1, true) then return 4 end
    if string.find(family, "melee", 1, true) then return 2 end
    if string.find(family, "ammo", 1, true) then return 3 end
    if string.find(family, "part", 1, true) then return 1 end
    return 0
end

function WeaponPricing.calculate(ctx, details)
    ctx = ctx or {}
    details = details or {}
    local c = settings()
    local evidence = details.weaponEvidence or {}
    local demand, demandContribution = ToolPricing.recipeEvidence(ctx)
    demandContribution = math.min(number(c.recipeDemandCap, DEFAULTS.recipeDemandCap),
        number(demandContribution, 0))

    local heuristic = {
        model = tostring(c.model or DEFAULTS.model),
        status = "ready",
        reason = "Weapon value combines normalized combat performance, condition, and verified recipe demand.",
        subtype = details.primary or "Weapon",
        mechanicalClass = evidence.mechanicalClass or details.primary or "Weapon",
        mechanicalFamily = evidence.mechanicalFamily,
        marketRole = evidence.marketRole,
        nativeCategories = evidence.nativeCategories,
        conditionMax = ctx.conditionMax,
        condition = ctx.condition,
        conditionRatio = ctx.conditionRatio,
        hasRuntimeState = ctx.hasRuntimeState == true,
        hasRuntimeCondition = ctx.hasRuntimeCondition == true,
        twoHanded = ctx.isTwoHandWeapon == true,
        recipeDemand = demand,
        recipeDemandScore = demand.recipeDemandScore,
        recipeCriticality = demand.criticality,
        recipeContribution = demandContribution,
        minDamage = ctx.minDamage,
        maxDamage = ctx.maxDamage,
        maxRange = ctx.maxRange,
        maxHit = ctx.maxHit,
        hitChance = ctx.hitChance,
        reliability = ctx.reliability,
        ammoType = ctx.ammoType,
        aimingTime = ctx.aimingTime,
        positiveContributions = {},
        negativeContributions = {},
        plannedPositiveAnchors = {
            "effective damage throughput",
            "reach and target coverage",
            "reliability and durability",
            "ammunition compatibility or yield",
            "reusable crafting and repair recipe demand for tool hybrids",
        },
        plannedNegativeAnchors = {
            "weight relative to performance",
            "condition and broken state",
            "hand occupancy and handling cost",
            "aiming or accuracy burden",
            "scarcity or compatibility gaps",
        },
    }
    Utils.addYieldEvidence(heuristic, details)

    local transformScore, transform = TransformPricing.evaluate(ctx, details, {
        multiplier = c.yieldMultiplier,
        premium = c.yieldPremium,
        floor = c.floor,
        ceiling = c.ceiling,
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

    local positives = heuristic.positiveContributions
    local negatives = heuristic.negativeContributions
    local averageDamage = (number(ctx.minDamage, 0) + number(ctx.maxDamage, 0)) / 2
    local damage = math.min(18, averageDamage * number(c.damageWeight, 4)
        * math.max(1, number(ctx.maxHit, 1)))
    local range = math.min(8, number(ctx.maxRange, 0) * number(c.rangeWeight, 2))
    local hitCount = math.min(6, math.max(0, number(ctx.maxHit, 1) - 1)
        * number(c.hitWeight, 2))
    local reliability = math.min(5, math.max(0, number(ctx.reliability, 0))
        * number(c.reliabilityWeight, 0.04))
    local hitChance = math.min(5, math.max(0, number(ctx.hitChance, 0))
        * number(c.hitChanceWeight, 0.03))
    local family = familyAnchor(evidence.mechanicalFamily or details.primary)
    Utils.addContribution(positives, "damage throughput", damage, averageDamage)
    Utils.addContribution(positives, "reach", range, ctx.maxRange)
    Utils.addContribution(positives, "multi-target coverage", hitCount, ctx.maxHit)
    Utils.addContribution(positives, "reliability", reliability, ctx.reliability)
    Utils.addContribution(positives, "accuracy", hitChance, ctx.hitChance)
    Utils.addContribution(positives, "weapon family", family, evidence.mechanicalFamily)
    Utils.addContribution(positives, "verified recipe demand", demandContribution,
        demand.recipeDemandScore)

    local weightPenalty = math.min(14, math.max(0, number(ctx.weight, 0))
        * number(c.weightPenalty, DEFAULTS.weightPenalty))
    local twoHandPenalty = ctx.isTwoHandWeapon == true
        and number(c.twoHandPenalty, DEFAULTS.twoHandPenalty) or 0
    local aimPenalty = math.min(5, math.max(0, number(ctx.aimingTime, 0)) * 0.02)
    Utils.addContribution(negatives, "weight burden", weightPenalty, ctx.weight)
    Utils.addContribution(negatives, "two-handed handling", twoHandPenalty, ctx.isTwoHandWeapon)
    Utils.addContribution(negatives, "aiming burden", aimPenalty, ctx.aimingTime)

    local stateFactor = Utils.runtimeStateFactor(ctx, {
        conditionFloor = c.conditionFloor,
        usesFloor = 0.25,
    })
    local score, summary = Utils.scoreAnchors(c.anchor, positives, negatives, {
        stateFactor = stateFactor,
        floor = c.floor,
        ceiling = c.ceiling,
    })
    for key, value in pairs(summary) do heuristic[key] = value end
    heuristic.mode = "combat_performance"
    heuristic.score = score
    details.priceHeuristic = heuristic
    return score
end

return WeaponPricing
