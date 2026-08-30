-- MarketSense tool pricing.
-- Recipe demand is a bounded usefulness signal. It is deliberately kept in
-- its own resolver so adding a recipe or a Workshop tool changes evidence by
-- the same deterministic path as vanilla items.

require "MarketSense/Pricing/MS_ToolRecipeDemand"

MarketSense = MarketSense or {}
MarketSense.ToolPricing = MarketSense.ToolPricing or {}

local ToolPricing = MarketSense.ToolPricing
local Demand = MarketSense.ToolRecipeDemand
local Config = MarketSense.ItemRuntimeConfig

local DEFAULTS = {
    model = "tool_v2",
    anchor = 10.0,
    floor = 1.0,
    ceiling = 250.0,
    conditionWeight = 8.0,
    conditionScale = 10.0,
    drainableUsesWeight = 0.35,
    drainableUsesCap = 8.0,
    recipeDemandWeight = 32.0,
    familyAnchors = {
        Tool = 0.0,
        ToolMaintenance = 1.0,
        ToolBlacksmith = 4.0,
        ToolButchering = 3.0,
        ToolCarpentry = 4.0,
        ToolFlintKnapping = 3.0,
        ToolFarming = 3.0,
        ToolGardening = 3.0,
        ToolMasonry = 3.0,
        ToolMechanics = 5.0,
        ToolPottery = 3.0,
        ToolTailoring = 2.0,
        ToolWelding = 5.0,
        Cooking = 1.0,
        ToolSmoking = 1.0,
    },
    weightPenalty = 1.5,
    twoHandPenalty = 2.0,
    stateFloor = 0.15,
}

local function number(value, fallback)
    value = tonumber(value)
    return value ~= nil and value or fallback
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function settings()
    local configured = Config and Config.toolPricing
    if type(configured) ~= "table" then return DEFAULTS end
    local result = {}
    for key, fallback in pairs(DEFAULTS) do
        if key == "familyAnchors" then
            result[key] = {}
            for family, value in pairs(fallback) do
                result[key][family] = configured[key]
                    and configured[key][family] ~= nil
                    and configured[key][family] or value
            end
        else
            result[key] = configured[key] ~= nil and configured[key] or fallback
        end
    end
    return result
end

local function buildHeuristic(ctx, details, c, demand, score)
    local classification = type(details.classificationDetails) == "table"
        and details.classificationDetails or {}
    local subtype = details.primary or "Tool"
    return {
        model = c.model,
        status = "ready",
        reason = "Tool usefulness combines engine metrics with reusable recipe demand.",
        subtype = subtype,
        classifierSource = classification.source,
        classifierTag = classification.tag,
        familyAnchor = c.familyAnchors[subtype] or 0,
        conditionMax = ctx.conditionMax,
        condition = ctx.condition,
        conditionRatio = ctx.conditionRatio,
        conditionLowerChance = ctx.conditionLowerChance,
        conditionContribution = score.conditionContribution,
        useDelta = ctx.useDelta,
        maxUses = ctx.maxUses,
        currentUsesFloat = ctx.currentUsesFloat,
        remainingUsesRatio = ctx.remainingUsesRatio,
        drainableContribution = score.drainableContribution,
        weightEmpty = ctx.weightEmpty,
        weight = ctx.weight,
        weightPenalty = score.weightPenalty,
        mechanicType = ctx.mechanicType,
        capacity = ctx.capacity,
        weightReduction = ctx.weightReduction,
        isDrainable = ctx.isDrainable == true,
        isDrainableInstance = ctx.isDrainableInstance == true,
        canBeEquipped = ctx.canBeEquipped,
        isTwoHandWeapon = ctx.isTwoHandWeapon == true,
        acceptItemFunction = ctx.acceptItemFunction,
        recipeDemand = demand,
        recipeDemandScore = demand.recipeDemandScore,
        recipeCriticality = demand.criticality,
        recipeContribution = score.recipeContribution,
        score = score.total,
        staticMetricsAvailable = {
            conditionMax = ctx.conditionMax ~= nil,
            condition = ctx.condition ~= nil,
            conditionLowerChance = ctx.conditionLowerChance ~= nil,
            useDelta = ctx.useDelta ~= nil and ctx.useDelta > 0,
            maxUses = ctx.maxUses ~= nil,
            remainingUses = ctx.remainingUsesRatio ~= nil,
            weightEmpty = ctx.weightEmpty ~= nil,
            weight = ctx.weight ~= nil,
            mechanicType = ctx.mechanicType ~= nil,
            capacity = ctx.capacity ~= nil and ctx.capacity > 0,
            weightReduction = ctx.weightReduction ~= nil and ctx.weightReduction > 0,
            canBeEquipped = ctx.canBeEquipped ~= nil and ctx.canBeEquipped ~= "",
            twoHandWeapon = ctx.isTwoHandWeapon ~= nil,
            acceptItemFunction = ctx.acceptItemFunction ~= nil
                and ctx.acceptItemFunction ~= "",
            recipeDemand = demand.status == "resolved",
        },
        plannedPositiveAnchors = {
            "verified action breadth and player utility",
            "reusable recipe demand and recipe criticality",
            "usable condition lifetime for condition-based tools",
            "remaining and maximum uses for drainable tools",
            "condition-loss resistance and repairability",
            "specialized crafting, farming, mechanics, cooking, or maintenance capability",
            "resource efficiency and reusable tool body value",
        },
        plannedNegativeAnchors = {
            "weight and endurance cost relative to delivered work",
            "low condition, depleted uses, or broken state",
            "single-purpose or gated use without broad utility",
            "fuel or resource consumption and replacement burden",
            "hand occupancy, two-handed handling, or movement cost",
            "ambiguous name/tag classification or rarity without mechanical evidence",
        },
    }
end

function ToolPricing.recipeEvidence(ctx)
    local c = settings()
    local demand = Demand and Demand.resolve and Demand.resolve(ctx or {}) or {
        status = "not_detected", recipeDemandScore = 0, criticality = "none",
        recipeCount = 0, reusableRecipeCount = 0, reusableInputCount = 0,
        consumedRecipeCount = 0, consumedInputCount = 0, recipes = {},
    }
    local contribution = math.max(0, number(demand.recipeDemandScore, 0))
        * number(c.recipeDemandWeight, DEFAULTS.recipeDemandWeight)
    return demand, contribution
end

function ToolPricing.calculate(ctx, details)
    ctx = ctx or {}
    details = details or {}
    local c = settings()
    local demand, recipeContribution = ToolPricing.recipeEvidence(ctx)
    local subtype = details.primary or "Tool"
    local familyAnchor = number(c.familyAnchors[subtype], 0)
    local conditionMax = math.max(0, number(ctx.conditionMax, 0))
    local conditionRatio = ctx.conditionRatio
    if conditionRatio == nil then conditionRatio = 1.0 end
    conditionRatio = clamp(number(conditionRatio, 1.0), 0, 1)
    local conditionContribution = conditionMax > 0
        and math.min(number(c.conditionWeight, DEFAULTS.conditionWeight),
            conditionMax / math.max(0.01, number(c.conditionScale, DEFAULTS.conditionScale))
                * number(c.conditionWeight, DEFAULTS.conditionWeight)) or 0
    local maxUses = math.max(0, number(ctx.maxUses, 0))
    local drainableContribution = math.min(
        number(c.drainableUsesCap, DEFAULTS.drainableUsesCap),
        maxUses * number(c.drainableUsesWeight, DEFAULTS.drainableUsesWeight)
    )
    local totalBeforeState = number(c.anchor, DEFAULTS.anchor)
        + familyAnchor + conditionContribution + drainableContribution
        + recipeContribution
    local weightPenalty = math.min(12, math.max(0, number(ctx.weight, 0))
        * number(c.weightPenalty, DEFAULTS.weightPenalty))
    if ctx.isTwoHandWeapon == true then
        weightPenalty = weightPenalty + number(c.twoHandPenalty, DEFAULTS.twoHandPenalty)
    end
    local stateFloor = clamp(number(c.stateFloor, DEFAULTS.stateFloor), 0, 1)
    local stateFactor = stateFloor + (1 - stateFloor) * conditionRatio
    if ctx.remainingUsesRatio ~= nil then
        stateFactor = stateFactor * (0.25 + 0.75 * clamp(
            number(ctx.remainingUsesRatio, 1), 0, 1
        ))
    end
    local total = math.max(number(c.floor, DEFAULTS.floor),
        math.min(number(c.ceiling, DEFAULTS.ceiling),
            totalBeforeState * stateFactor - weightPenalty))
    local score = {
        total = total,
        conditionContribution = conditionContribution,
        drainableContribution = drainableContribution,
        recipeContribution = recipeContribution,
        weightPenalty = weightPenalty,
    }
    details.priceHeuristic = buildHeuristic(ctx, details, c, demand, score)
    return total
end

return ToolPricing
