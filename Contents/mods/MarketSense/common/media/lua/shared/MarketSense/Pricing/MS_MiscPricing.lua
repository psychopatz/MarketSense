-- MarketSense Misc pricing evidence.
--
-- Misc is the final fallback bucket and contains both useful survival items
-- and items with no mechanical utility.  Keep this phase evidence-only so a
-- weak classifier or a decorative item cannot inherit a large flat price.

MarketSense = MarketSense or {}
require "MarketSense/MS_Config"
require "MarketSense/MS_Core"
require "MarketSense/Pricing/MS_YieldResolver"
require "MarketSense/Pricing/MS_TransformPricing"
require "MarketSense/Pricing/MS_PricingUtils"

MarketSense.MiscPricing = MarketSense.MiscPricing or {}

local MiscPricing = MarketSense.MiscPricing
local Config = MarketSense.ItemRuntimeConfig
local Core = MarketSense.Core
local YieldResolver = MarketSense.YieldResolver
local TransformPricing = MarketSense.TransformPricing
local Utils = require "MarketSense/Pricing/MS_PricingUtils"

local DEFAULTS = {
    model = "misc_v2",
    floor = 1.0,
    yieldMultiplier = 0.85,
    yieldPremium = 0.0,
}

local function settings()
    local configured = Config and Config.miscPricing
    if type(configured) ~= "table" then
        return DEFAULTS
    end

    local result = {}
    for key, fallback in pairs(DEFAULTS) do
        result[key] = configured[key] ~= nil and configured[key] or fallback
    end
    return result
end

local function copyList(value)
    if type(value) ~= "table" then return {} end
    local result = {}
    for _, entry in ipairs(value) do
        result[#result + 1] = entry
    end
    return result
end

local function copyYieldOutputs(outputs)
    local result = {}
    local totalQuantity = 0
    for _, output in ipairs(outputs or {}) do
        local quantity = tonumber(output.quantity)
        if quantity ~= nil then totalQuantity = totalQuantity + quantity end
        result[#result + 1] = {
            fullType = output.fullType,
            quantity = output.quantity,
            maxQuantity = output.maxQuantity,
            chance = output.chance,
            resolution = output.resolution,
            inheritFoodAge = output.inheritFoodAge == true,
        }
    end
    return result, totalQuantity
end

local function addSignal(signals, name, enabled)
    if enabled then signals[#signals + 1] = name end
end

function MiscPricing.buildHeuristic(ctx, details)
    ctx = ctx or {}
    details = details or {}

    local classification = type(details.classificationDetails) == "table"
        and details.classificationDetails or {}
    local capabilityData = type(ctx.capabilities) == "table"
        and ctx.capabilities or {}
    local world = type(ctx.worldObjectEvidence) == "table"
        and ctx.worldObjectEvidence or {}
    local yield = type(details.yieldResolution) == "table"
        and details.yieldResolution or {}
    local yieldOutputs, yieldQuantity = copyYieldOutputs(yield.outputs)
    local subtype = details.primary or "Misc"
    local yieldStatus = yield.status or "not_detected"
    local hasYield = details.yieldResolution ~= nil
    local deterministicYield = hasYield and yieldStatus == "resolved"
    local hasRecipeSignal = (ctx.openingRecipe or "") ~= ""
        or (ctx.doubleClickRecipe or "") ~= ""
        or #yieldOutputs > 0

    local capabilities = copyList(capabilityData.capabilities)
    local requirements = copyList(capabilityData.requirements)
    local capabilityEvidence = copyList(capabilityData.evidence)
    local signals = {}
    for _, capability in ipairs(capabilities) do
        signals[#signals + 1] = "capability:" .. tostring(capability)
    end
    addSignal(signals, "water_storage", ctx.canStoreWater == true)
    -- A MiscFishing subtype is already backed by the classifier's explicit
    -- fishing display/tag evidence. Keep that evidence useful even when a
    -- script definition does not expose the optional boolean method.
    addSignal(signals, "fishing_lure",
        ctx.isFishingLure == true or subtype == "MiscFishing")
    addSignal(signals, "drainable", ctx.isDrainable == true)
    addSignal(signals, "craft_recipe_product", ctx.isCraftRecipeProduct == true)
    addSignal(signals, "forageable", ctx.canBeForaged == true)
    addSignal(signals, "loot_obtainable", ctx.canSpawnAsLoot == true)
    addSignal(signals, "moveable", ctx.isMoveable == true)
    addSignal(signals, "packaged", ctx.isPackaged == true)
    addSignal(signals, "poison", ctx.isPoison == true)
    addSignal(signals, "dung", ctx.isDung == true)
    addSignal(signals, "recipe_transform", hasRecipeSignal)

    local c = settings()
    return {
        model = tostring(c.model or DEFAULTS.model),
        status = "ready",
        reason = "Misc evidence is retained for the deterministic utility fallback.",
        subtype = subtype,
        classifierSource = classification.source,
        classifierTag = classification.tag,
        displayCategory = ctx.displayCategory,
        itemType = ctx.itemType,
        lootType = ctx.lootType,
        description = ctx.description,
        worldStaticModel = ctx.worldStaticModel,
        worldObjectSprite = ctx.worldObjectSprite,
        worldEvidenceAvailable = world.available == true,
        worldObjectClass = world.objectClass,
        worldCustomName = world.customName,
        worldGroupName = world.groupName,
        worldContainerType = world.containerType,
        capabilities = capabilities,
        requirements = requirements,
        capabilityEvidence = capabilityEvidence,
        powerSource = capabilityData.powerSource,
        signals = signals,
        isMemento = subtype == "Memento" or subtype == "MementoPlushie",
        isJunk = subtype == "Junk",
        isMoveable = ctx.isMoveable == true,
        canBeEquipped = ctx.canBeEquipped,
        canStoreWater = ctx.canStoreWater == true,
        isFishingLure = ctx.isFishingLure == true,
        isDrainable = ctx.isDrainable == true,
        isDrainableInstance = ctx.isDrainableInstance == true,
        useDelta = ctx.useDelta,
        maxUses = ctx.maxUses,
        currentUsesFloat = ctx.currentUsesFloat,
        remainingUsesRatio = ctx.remainingUsesRatio,
        weight = ctx.weight,
        weightEmpty = ctx.weightEmpty,
        conditionMax = ctx.conditionMax,
        condition = ctx.condition,
        conditionRatio = ctx.conditionRatio,
        canStack = ctx.canStack,
        stackCount = ctx.stackCount,
        isCraftRecipeProduct = ctx.isCraftRecipeProduct == true,
        canSpawnAsLoot = ctx.canSpawnAsLoot == true,
        canBeForaged = ctx.canBeForaged == true,
        isPackaged = ctx.isPackaged == true,
        isPoison = ctx.isPoison == true,
        isDung = ctx.isDung == true,
        openingRecipe = ctx.openingRecipe,
        doubleClickRecipe = ctx.doubleClickRecipe,
        replaceOnDeplete = ctx.replaceOnDeplete,
        replaceOnUse = ctx.replaceOnUse,
        isDisappearOnUse = ctx.isDisappearOnUse,
        unbundleCandidate = hasRecipeSignal,
        yieldStatus = yieldStatus,
        yieldRecipe = yield.recipe,
        yieldOutputCount = #yieldOutputs,
        yieldOutputQuantity = yieldQuantity,
        yieldOutputs = yieldOutputs,
        staticMetricsAvailable = {
            classification = details.primary ~= nil and details.primary ~= "",
            capabilityEvidence = #capabilities > 0,
            capabilityRequirements = #requirements > 0,
            worldEvidence = world.available == true,
            weight = ctx.weight ~= nil,
            stackability = ctx.canStack ~= nil and ctx.canStack ~= "",
            stackCount = ctx.stackCount ~= nil,
            condition = ctx.conditionMax ~= nil or ctx.conditionRatio ~= nil,
            drainableUses = ctx.maxUses ~= nil or ctx.remainingUsesRatio ~= nil,
            recipeProduct = ctx.isCraftRecipeProduct ~= nil,
            packageSignal = hasRecipeSignal,
            deterministicYield = deterministicYield,
            stateFlags = ctx.isPoison ~= nil or ctx.isDung ~= nil
                or ctx.isPackaged ~= nil or ctx.isFishingLure ~= nil,
        },
        plannedPositiveAnchors = {
            "verified player capability or action enabled by the item",
            "deterministic child-item yield multiplied by output quantity",
            "reusable uses, remaining amount, or stack quantity",
            "fishing, fire, safety, security, navigation, or household utility proven by metadata",
            "crafting, processing, agriculture, or recreation utility proven by metadata",
            "portable utility delivered per unit of weight and encumbrance",
            "recipe transform that reduces processing cost or exposes useful contents",
        },
        plannedNegativeAnchors = {
            "fallback, ambiguous, or unknown classification",
            "decorative memento, junk, or cosmetic status without mechanical utility",
            "weight, bulk, placement, and handling burden relative to utility",
            "single-use, depleted, empty, damaged, broken, or partial-use state",
            "electricity, water, fuel, station, or other operating requirement",
            "poison, waste, contamination, or harmful handling state",
            "probabilistic or unresolved package contents",
            "rarity, theme, or source labels without verified player utility",
            "double-counting a parent package and its child outputs",
        },
    }
end

function MiscPricing.calculate(ctx, details, neutralScore)
    ctx = ctx or {}
    details = details or {}
    local c = settings()
    local yieldInfo = type(details.yieldResolution) == "table"
        and details.yieldResolution or YieldResolver.resolve(ctx)
    details.yieldResolution = yieldInfo

    local heuristic = MiscPricing.buildHeuristic(ctx, details)
    heuristic.positiveContributions = {}
    heuristic.negativeContributions = {}
    heuristic.yieldEvaluation = "not_detected"
    heuristic.yieldBlockedReason = nil

    local transformScore, transform = TransformPricing.evaluate(ctx, details, {
        multiplier = c.yieldMultiplier,
        premium = c.yieldPremium,
        floor = c.floor,
    })
    if transformScore ~= nil then
        for key, value in pairs(transform) do heuristic[key] = value end
        heuristic.model = "misc_v2_bundle"
        heuristic.status = "ready"
        heuristic.reason = "Deterministic transform valued from individualized child outputs."
        heuristic.yieldEvaluation = "valued"
        heuristic.positiveContributions = Core.deepCopy(transform.contributions)
        heuristic.score = transformScore
        return transformScore, heuristic
    end

    if type(transform) == "table" then
        if transform.yieldStatus == "resolved" then
            yieldInfo.evaluation = "fallback"
            yieldInfo.fallbackReason = transform.reason or "yield evaluation failed"
        end
        heuristic.yieldEvaluation = "blocked"
        heuristic.yieldBlockedReason = transform.reason
            or ("yield status is " .. tostring(yieldInfo.status))
        heuristic.blockedReasons = { heuristic.yieldBlockedReason }
    end

    local positives = {}
    local negatives = {}
    local subtype = tostring(heuristic.subtype or "Misc")
    local capabilityCount = #heuristic.capabilities
    local capabilityValue = math.min(8, capabilityCount * 2)
    local familyValue = 0
    if string.find(subtype, "Fishing", 1, true) then familyValue = 4
    elseif string.find(subtype, "Fire", 1, true) then familyValue = 4
    elseif string.find(subtype, "Safety", 1, true)
        or string.find(subtype, "Security", 1, true) then familyValue = 3
    elseif string.find(subtype, "Navigation", 1, true)
        or string.find(subtype, "Utility", 1, true)
        or string.find(subtype, "Household", 1, true) then familyValue = 2
    elseif string.find(subtype, "Recreation", 1, true)
        or string.find(subtype, "Entertainment", 1, true) then familyValue = 1.5
    end
    local usesValue = math.min(4, math.max(0, tonumber(ctx.maxUses) or 0) * 0.5)
    local stackValue = math.min(4, math.max(0, tonumber(ctx.stackCount) or 0) * 0.15)
    local waterValue = ctx.canStoreWater == true and 3 or 0
    local fishingValue = ctx.isFishingLure == true and 2 or 0
    -- A recipe signal is evidence that the item may be a transform, not a
    -- value by itself. Exact transforms are valued above; blocked ones stay
    -- diagnostic-only so an ambiguous package cannot receive a free premium.
    local recipeValue = 0
    local weightPenalty = math.min(8, math.max(0, tonumber(ctx.weight) or 0) * 0.8)
    local stateFactor = Utils.runtimeStateFactor(ctx, { harmfulFactor = 0.12, wasteFactor = 0.3 })
    Utils.addContribution(positives, "verified capability", capabilityValue, capabilityCount)
    Utils.addContribution(positives, "verified Misc family", familyValue, subtype)
    Utils.addContribution(positives, "reusable amount", usesValue, ctx.maxUses)
    Utils.addContribution(positives, "stack quantity", stackValue, ctx.stackCount)
    Utils.addContribution(positives, "water storage", waterValue, true)
    Utils.addContribution(positives, "fishing utility", fishingValue, true)
    Utils.addContribution(positives, "transform access", recipeValue, true)
    Utils.addContribution(negatives, "weight burden", weightPenalty, ctx.weight)
    Utils.addContribution(negatives, "decorative memento", subtype == "Memento" and 1.5 or 0, subtype)
    Utils.addContribution(negatives, "junk identity", subtype == "Junk" and 1.0 or 0, subtype)
    Utils.addContribution(negatives, "poison or waste state",
        (ctx.isPoison or ctx.isDung) and 2 or 0, true)
    local score, summary = Utils.scoreAnchors(neutralScore or 2, positives, negatives, {
        stateFactor = stateFactor,
        floor = c.floor,
    })
    for key, value in pairs(summary) do heuristic[key] = value end
    heuristic.model = "misc_v2"
    heuristic.status = "ready"
    heuristic.mode = "fallback"
    heuristic.reason = "Misc utility anchors evaluated from verified metadata."
    heuristic.positiveContributions = positives
    heuristic.negativeContributions = negatives
    heuristic.score = score
    return score, heuristic
end

return MiscPricing
