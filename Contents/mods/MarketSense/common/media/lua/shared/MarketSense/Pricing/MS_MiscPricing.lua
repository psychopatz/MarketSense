-- MarketSense Misc pricing evidence.
--
-- Misc is the final fallback bucket and contains both useful survival items
-- and items with no mechanical utility.  Keep this phase evidence-only so a
-- weak classifier or a decorative item cannot inherit a large flat price.

MarketSense = MarketSense or {}
require "MarketSense/MS_Config"

MarketSense.MiscPricing = MarketSense.MiscPricing or {}

local MiscPricing = MarketSense.MiscPricing
local Config = MarketSense.ItemRuntimeConfig

local function configuredModel()
    local configured = Config and Config.miscPricing
    local model = type(configured) == "table" and configured.model or nil
    if type(model) ~= "string" or model == "" then
        return "misc_v2_pending"
    end
    return model
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
        }
    end
    return result, totalQuantity
end

local function addSignal(signals, name, enabled)
    if enabled then signals[#signals + 1] = name end
end

function MiscPricing.buildPendingHeuristic(ctx, details)
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

    return {
        model = configuredModel(),
        status = "pending",
        reason = "Legacy Misc flat additions removed; awaiting calibrated capability, fallback, and utility anchors.",
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

return MiscPricing
