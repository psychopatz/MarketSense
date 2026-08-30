-- MarketSense building and placeable pricing.
-- Placeables are priced by the player service they unlock. World-object
-- names are retained as evidence, but never create value on their own.

require "MarketSense/MS_Config"
require "MarketSense/MS_Core"
require "MarketSense/Pricing/MS_PricingUtils"
require "MarketSense/Pricing/MS_TransformPricing"

MarketSense = MarketSense or {}
MarketSense.BuildingPricing = MarketSense.BuildingPricing or {}

local BuildingPricing = MarketSense.BuildingPricing
local Config = MarketSense.ItemRuntimeConfig
local Core = MarketSense.Core
local Utils = require "MarketSense/Pricing/MS_PricingUtils"
local TransformPricing = MarketSense.TransformPricing

local DEFAULTS = {
    model = "building_v2", anchor = 5.0, floor = 1.0, ceiling = 400.0,
    capabilityWeight = 2.2, worldUtilityAnchor = 2.0, capacityWeight = 0.35,
    moveableAnchor = 2.0, familyAnchor = 2.0, requirementPenalty = 0.8,
    weightPenalty = 0.6, stationaryPenalty = 1.0, conditionFloor = 0.20,
    yieldMultiplier = 1.0, yieldPremium = 0.0,
}

local function number(value, fallback)
    value = tonumber(value)
    return value ~= nil and value or fallback
end

local function settings()
    local configured = Config and Config.buildingPricing
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

local function familyValue(ctx, details, c)
    local identity = lower(table.concat({
        details.primary or "", ctx.idLower or "", ctx.displayNameLower or "",
        ctx.worldStaticModelLower or "", ctx.worldObjectSpriteLower or "",
    }, " "))
    local value = 0
    if string.find(identity, "seed", 1, true) then value = 3 end
    if string.find(identity, "trap", 1, true) then value = math.max(value, 2) end
    if string.find(identity, "generator", 1, true)
        or string.find(identity, "water", 1, true) then value = math.max(value, 3) end
    if string.find(identity, "vehicle", 1, true) then value = math.max(value, 3) end
    if string.find(identity, "furniture", 1, true) then value = math.max(value, 1) end
    return math.min(number(c.familyAnchor, 2), value)
end

function BuildingPricing.calculate(ctx, details)
    ctx = ctx or {}
    details = details or {}
    local c = settings()
    local capabilityData = type(ctx.capabilities) == "table" and ctx.capabilities or {}
    local world = type(ctx.worldObjectEvidence) == "table" and ctx.worldObjectEvidence or {}
    local capabilities = capabilityData.capabilities or {}
    local requirements = capabilityData.requirements or {}
    local heuristic = {
        model = tostring(c.model or DEFAULTS.model), status = "ready",
        subtype = details.primary or "Building",
        reason = "Building value combines verified placed-object services, storage, and deployability.",
        displayCategory = ctx.displayCategory, itemType = ctx.itemType,
        isMoveable = ctx.isMoveable == true, canBeEquipped = ctx.canBeEquipped,
        weight = ctx.weight, conditionMax = ctx.conditionMax,
        condition = ctx.condition, conditionRatio = ctx.conditionRatio,
        capacity = ctx.capacity, weightReduction = ctx.weightReduction,
        worldEvidenceAvailable = world.available == true,
        worldObjectClass = world.objectClass, worldCustomName = world.customName,
        worldGroupName = world.groupName, worldContainerCapacity = world.containerCapacity,
        worldSurface = world.surface, worldIsTable = world.isTable == true,
        worldIsTableTop = world.isTableTop == true,
        worldGenericCraftingSurface = world.genericCraftingSurface == true,
        capabilities = capabilities, requirements = requirements,
        capabilityEvidence = capabilityData.evidence or {},
        powerSource = capabilityData.powerSource,
        positiveContributions = {}, negativeContributions = {},
        plannedPositiveAnchors = {
            "verified player action or service enabled by the placed object",
            "usable storage capacity and saved carry weight",
            "crafting, processing, agriculture, medical, or recreation utility",
            "shelter, sleeping, deployability, and survival access",
            "portable or placeable access when mechanically verified",
            "durability, repairability, and exact recipe utility",
        },
        plannedNegativeAnchors = {
            "weight, bulk, encumbrance, placement, and handling burden",
            "electricity, water, fuel, or other operating requirements",
            "stationary-only access, footprint, or difficult deployment",
            "broken, damaged, incomplete, or unusable state",
            "ambiguous package contents",
            "decorative or rarity labels without mechanical utility",
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
    local capabilityValue = math.min(12, #capabilities * number(c.capabilityWeight, 2.2))
    local worldUtility = world.available == true and number(c.worldUtilityAnchor, 2) or 0
    local capacity = math.max(number(ctx.capacity, 0), number(world.containerCapacity, 0))
    local storageValue = math.min(8, math.sqrt(math.max(0, capacity))
        * number(c.capacityWeight, 0.35))
    local moveableValue = ctx.isMoveable == true and number(c.moveableAnchor, 2) or 0
    local family = familyValue(ctx, details, c)
    Utils.addContribution(positives, "verified building capability", capabilityValue, #capabilities)
    Utils.addContribution(positives, "world-object utility", worldUtility, world.objectClass)
    Utils.addContribution(positives, "storage capacity", storageValue, capacity)
    Utils.addContribution(positives, "deployable or moveable access", moveableValue, ctx.isMoveable)
    Utils.addContribution(positives, "building family", family, details.primary)

    local weightPenalty = math.min(18, math.max(0, number(ctx.weight, 0))
        * number(c.weightPenalty, 0.6))
    local requirementsPenalty = math.min(8, #requirements
        * number(c.requirementPenalty, 0.8))
    local stationaryPenalty = world.available == true and ctx.isMoveable ~= true
        and number(c.stationaryPenalty, 1) or 0
    Utils.addContribution(negatives, "weight burden", weightPenalty, ctx.weight)
    Utils.addContribution(negatives, "operating requirements", requirementsPenalty, #requirements)
    Utils.addContribution(negatives, "stationary placement burden", stationaryPenalty, world.objectClass)
    local stateFactor = Utils.runtimeStateFactor(ctx, { conditionFloor = c.conditionFloor })
    local score, summary = Utils.scoreAnchors(c.anchor, positives, negatives, {
        stateFactor = stateFactor, floor = c.floor, ceiling = c.ceiling,
    })
    for key, value in pairs(summary) do heuristic[key] = value end
    heuristic.mode = "placed_object_utility"
    heuristic.score = score
    details.priceHeuristic = heuristic
    return score
end

return BuildingPricing
