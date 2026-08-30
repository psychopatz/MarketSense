-- MarketSense container pricing.
-- A container is valued by useful storage and carry efficiency. Exact opening
-- recipes are valued by MS_TransformPricing so contents are not double-counted.

require "MarketSense/MS_Config"
require "MarketSense/MS_Core"
require "MarketSense/Pricing/MS_PricingUtils"
require "MarketSense/Pricing/MS_TransformPricing"

MarketSense = MarketSense or {}
MarketSense.ContainerPricing = MarketSense.ContainerPricing or {}

local ContainerPricing = MarketSense.ContainerPricing
local Config = MarketSense.ItemRuntimeConfig
local Core = MarketSense.Core
local Utils = require "MarketSense/Pricing/MS_PricingUtils"
local TransformPricing = MarketSense.TransformPricing

local DEFAULTS = {
    model = "container_v2", anchor = 14.0, floor = 1.0, ceiling = 300.0,
    capacityWeight = 0.85, reductionWeight = 0.07, wearableAnchor = 2.0,
    specialAnchor = 2.0, weightPenalty = 0.75, conditionFloor = 0.20,
    yieldMultiplier = 1.0, yieldPremium = 0.0,
}

local function number(value, fallback)
    value = tonumber(value)
    return value ~= nil and value or fallback
end

local function settings()
    local configured = Config and Config.containerPricing
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

local function has(textValue, marker)
    return string.find(text(textValue), marker, 1, true) ~= nil
end

local function specialAnchor(ctx, details, c)
    local identity = table.concat({
        details.primary or "", ctx.idLower or "", ctx.displayNameLower or "",
        ctx.acceptItemFunction or "", ctx.bodyLocationLower or "",
    }, " ")
    local value = 0
    if has(identity, "cooler") or has(identity, "fridge") then value = value + 2 end
    if has(identity, "medical") or has(identity, "firstaid") then value = value + 1.5 end
    if has(identity, "ammo") or has(identity, "magazine") then value = value + 1.5 end
    if has(identity, "toolbox") or has(identity, "tool") then value = value + 1 end
    return math.min(number(c.specialAnchor, 2), value)
end

function ContainerPricing.calculate(ctx, details)
    ctx = ctx or {}
    details = details or {}
    local c = settings()
    local heuristic = {
        model = tostring(c.model or DEFAULTS.model), status = "ready",
        subtype = details.primary or "Container",
        reason = "Container value combines usable capacity, carry efficiency, portability, and state.",
        capacity = ctx.capacity, weightReduction = ctx.weightReduction, weight = ctx.weight,
        conditionMax = ctx.conditionMax, condition = ctx.condition,
        conditionRatio = ctx.conditionRatio, canBeEquipped = ctx.canBeEquipped,
        bodyLocation = ctx.bodyLocation, bodyLocationToken = ctx.bodyLocationToken,
        isFluidContainer = ctx.isFluidContainer == true, isActualLiquid = ctx.isActualLiquid == true,
        positiveContributions = {}, negativeContributions = {},
        plannedPositiveAnchors = {
            "usable capacity within the container family",
            "weight reduction and saved carry weight",
            "portable or wearable access",
            "verified special function such as cooling, medical, ammo, or tools",
            "deterministic child-content yield valued per output quantity",
            "durability and usable lifetime",
        },
        plannedNegativeAnchors = {
            "container weight relative to usable capacity",
            "low capacity or no meaningful storage utility",
            "movement and encumbrance cost",
            "broken, damaged, or inaccessible state",
            "ambiguous package contents",
            "rarity or family labels without mechanical utility",
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
    local capacity = math.max(0, number(ctx.capacity, 0))
    local reduction = math.max(0, number(ctx.weightReduction, 0))
    local capacityValue = math.min(14, math.sqrt(capacity) * number(c.capacityWeight, 0.85))
    local reductionValue = math.min(8, reduction * number(c.reductionWeight, 0.07))
    local wearableValue = ctx.canBeEquipped and number(c.wearableAnchor, 2) or 0
    local specialValue = specialAnchor(ctx, details, c)
    Utils.addContribution(positives, "usable capacity", capacityValue, capacity)
    Utils.addContribution(positives, "carry-weight reduction", reductionValue, reduction)
    Utils.addContribution(positives, "wearable portability", wearableValue, ctx.canBeEquipped)
    Utils.addContribution(positives, "special container function", specialValue, details.primary)

    local weightPenalty = math.min(14, math.max(0, number(ctx.weight, 0))
        * number(c.weightPenalty, DEFAULTS.weightPenalty))
    local noStoragePenalty = capacity <= 0 and 1.5 or 0
    Utils.addContribution(negatives, "container weight", weightPenalty, ctx.weight)
    Utils.addContribution(negatives, "no measured storage", noStoragePenalty, capacity)
    local stateFactor = Utils.runtimeStateFactor(ctx, { conditionFloor = c.conditionFloor })
    local score, summary = Utils.scoreAnchors(c.anchor, positives, negatives, {
        stateFactor = stateFactor, floor = c.floor, ceiling = c.ceiling,
    })
    for key, value in pairs(summary) do heuristic[key] = value end
    heuristic.mode = "storage_capacity"
    heuristic.specialAnchor = specialValue
    heuristic.score = score
    details.priceHeuristic = heuristic
    return score
end

return ContainerPricing
