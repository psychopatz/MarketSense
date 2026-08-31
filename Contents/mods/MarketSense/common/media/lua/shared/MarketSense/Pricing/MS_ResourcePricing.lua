-- MarketSense resource pricing.
-- Resources are valued by directly usable material role, delivered quantity,
-- processing stage, and utility per unit weight. Broad names and rarity do
-- not create value without a mechanical signal.

require "MarketSense/MS_Config"
require "MarketSense/MS_Core"
require "MarketSense/Pricing/MS_PricingUtils"
require "MarketSense/Pricing/MS_TransformPricing"

MarketSense = MarketSense or {}
MarketSense.ResourcePricing = MarketSense.ResourcePricing or {}

local ResourcePricing = MarketSense.ResourcePricing
local Config = MarketSense.ItemRuntimeConfig
local Core = MarketSense.Core
local Utils = require "MarketSense/Pricing/MS_PricingUtils"
local TransformPricing = MarketSense.TransformPricing

local DEFAULTS = {
    model = "resource_v2", anchor = 12.0, floor = 1.0,
    familyWeight = 2.0, formWeight = 1.5, quantityWeight = 1.2,
    useWeight = 0.7, recipeWeight = 1.5, weightPenalty = 0.45,
    processingPenalty = 2.0, unknownPenalty = 0.8, harmfulPenalty = 3.0,
    conditionFloor = 0.20, yieldMultiplier = 0.55, yieldPremium = 0.0,
}

local function number(value, fallback)
    value = tonumber(value)
    return value ~= nil and value or fallback
end

local function settings()
    local configured = Config and Config.resourcePricing
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

local function contains(value, marker)
    return string.find(lower(value), marker, 1, true) ~= nil
end

local function materialForm(ctx)
    local identity = table.concat({
        ctx.idLower or ctx.typeName or "",
        ctx.displayNameLower or ctx.displayName or "",
        ctx.descriptionLower or ctx.description or "",
        ctx.worldStaticModelLower or ctx.worldStaticModel or "",
        ctx.worldObjectSpriteLower or ctx.worldObjectSprite or "",
    }, " ")
    local forms = {
        { "bundle", 1, 0 }, { "package", 1, 0 }, { "carton", 1, 0 },
        { "box", 1, 0 },
        { "ingot", 4, 0 }, { "sheet", 3, 0 }, { "plate", 3, 0 },
        { "plank", 3, 0 }, { "board", 3, 0 }, { "block", 2, 0 },
        { "powder", 1, 0.5 }, { "piece", 1, 0.5 }, { "ore", 0, 2 },
        { "raw", 0, 2 }, { "scrap", 0, 1.5 }, { "fragment", 0, 1.5 },
        { "mold", 0, 2 },
    }
    for _, entry in ipairs(forms) do
        if contains(identity, entry[1]) then return entry[1], entry[2], entry[3] end
    end
    return "unknown", 0, 0.8
end

local function familyAnchor(details, ctx)
    local primary = tostring(details.primary or "")
    if string.sub(primary, 1, 8) == "Material" then
        local suffix = string.sub(primary, 9)
        if suffix ~= "" and lower(suffix) ~= "bundled" then
            local normalized = lower(suffix)
            if string.find(normalized, "metal", 1, true) then return 4, suffix end
            if string.find(normalized, "fuel", 1, true) then return 4, suffix end
            if string.find(normalized, "hardware", 1, true) then return 3, suffix end
            if string.find(normalized, "construction", 1, true) then return 3, suffix end
            return 1, suffix
        end
    end
    local identity = lower(table.concat({
        details.primary or "", ctx.displayCategory or "", ctx.description or "",
        ctx.idLower or "", ctx.displayNameLower or "",
    }, " "))
    if contains(identity, "fuel") or contains(identity, "gas") then return 4, "fuel" end
    if contains(identity, "metal") or contains(identity, "steel") then return 4, "metal" end
    if contains(identity, "hardware") or contains(identity, "nail")
        or contains(identity, "screw") then return 3, "hardware" end
    if contains(identity, "masonry") or contains(identity, "concrete")
        or contains(identity, "cement") then return 3, "masonry" end
    if contains(identity, "textile") or contains(identity, "cloth")
        or contains(identity, "leather") then return 2, "textile" end
    if contains(identity, "wood") or contains(identity, "lumber") then return 2, "wood" end
    if contains(identity, "part") or contains(identity, "component") then return 2, "part" end
    if contains(identity, "bundled") or contains(identity, "bundle") then return 1, "Bundled" end
    return 0, "unknown"
end

function ResourcePricing.calculate(ctx, details)
    ctx = ctx or {}
    details = details or {}
    local c = settings()
    local family, familyName = familyAnchor(details, ctx)
    local form, formValue, processingPenalty = materialForm(ctx)
    if form == "unknown" and contains(details.primary, "bundl") then
        form, formValue, processingPenalty = "bundle", 1, 0
    end
    local capabilityData = type(ctx.capabilities) == "table" and ctx.capabilities or {}
    local capabilities = capabilityData.capabilities or {}
    local heuristic = {
        model = tostring(c.model or DEFAULTS.model), status = "ready",
        subtype = details.primary or "ResourceUnknown",
        reason = "Resource value combines material role, usable form, quantity, and processing cost.",
        materialFamily = familyName, materialForm = form,
        displayCategory = ctx.displayCategory, itemType = ctx.itemType,
        description = ctx.description, weight = ctx.weight, weightEmpty = ctx.weightEmpty,
        canStack = ctx.canStack, stackCount = ctx.stackCount,
        isCraftRecipeProduct = ctx.isCraftRecipeProduct == true,
        canSpawnAsLoot = ctx.canSpawnAsLoot == true, canBeForaged = ctx.canBeForaged == true,
        conditionMax = ctx.conditionMax, condition = ctx.condition,
        conditionRatio = ctx.conditionRatio, isDrainable = ctx.isDrainable == true,
        isDrainableInstance = ctx.isDrainableInstance == true, maxUses = ctx.maxUses,
        currentUsesFloat = ctx.currentUsesFloat, remainingUsesRatio = ctx.remainingUsesRatio,
        capabilities = capabilities, requirements = capabilityData.requirements or {},
        fluidType = ctx.fluidType, fluidCategory = ctx.fluidCategory,
        fluidAmount = ctx.fluidAmount, fluidCapacity = ctx.fluidCapacity,
        unbundleCandidate = details.yieldResolution ~= nil,
        positiveContributions = {}, negativeContributions = {},
        plannedPositiveAnchors = {
            "verified player-useful material role and subtype",
            "deterministic child-item yield valued per output quantity",
            "stack quantity or remaining usable amount",
            "refined or directly usable form with less processing required",
            "fuel, construction, repair, crafting, or survival function",
            "recipe/component demand proven by runtime evidence",
            "utility delivered per unit of weight",
        },
        plannedNegativeAnchors = {
            "weight and handling burden relative to delivered utility",
            "raw, ore, scrap, mold, or other processing-stage cost",
            "depleted, damaged, broken, empty, or partial-use state",
            "required workstation, tool, fuel, power, or extra processing",
            "hazard, poison, contamination, or harmful state",
            "ambiguous material form or classification",
            "probabilistic package yield or double-counted contents",
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
    local stackValue = math.min(10, math.sqrt(math.max(0, number(ctx.stackCount, 0)))
        * number(c.quantityWeight, 1.2))
    local useValue = math.min(5, math.max(0, number(ctx.maxUses, 0))
        * number(c.useWeight, 0.7))
    local recipeValue = ctx.isCraftRecipeProduct == true
        and number(c.recipeWeight, 1.5) or 0
    local capabilityValue = math.min(5, #capabilities * 1.2)
    Utils.addContribution(positives, "material family", family * number(c.familyWeight, 2), familyName)
    Utils.addContribution(positives, "usable material form", formValue * number(c.formWeight, 1.5), form)
    Utils.addContribution(positives, "stack quantity", stackValue, ctx.stackCount)
    Utils.addContribution(positives, "remaining usable amount", useValue, ctx.maxUses)
    Utils.addContribution(positives, "recipe product utility", recipeValue, ctx.isCraftRecipeProduct)
    Utils.addContribution(positives, "verified capability", capabilityValue, #capabilities)

    local weightPenalty = math.min(14, math.max(0, number(ctx.weight, 0))
        * number(c.weightPenalty, 0.45))
    local unknownPenalty = form == "unknown" and number(c.unknownPenalty, 0.8) or 0
    local harmfulPenalty = (ctx.isPoison == true or ctx.isDung == true)
        and number(c.harmfulPenalty, 3) or 0
    Utils.addContribution(negatives, "weight burden", weightPenalty, ctx.weight)
    Utils.addContribution(negatives, "processing stage", processingPenalty
        * number(c.processingPenalty, 2), form)
    Utils.addContribution(negatives, "unknown material form", unknownPenalty, form)
    Utils.addContribution(negatives, "harmful or waste state", harmfulPenalty, ctx.isPoison or ctx.isDung)
    local stateFactor = Utils.runtimeStateFactor(ctx, { conditionFloor = c.conditionFloor })
    local score, summary = Utils.scoreAnchors(c.anchor, positives, negatives, {
        stateFactor = stateFactor, floor = c.floor,
    })
    for key, value in pairs(summary) do heuristic[key] = value end
    heuristic.mode = "material_utility"
    heuristic.score = score
    details.priceHeuristic = heuristic
    return score
end

return ResourcePricing
