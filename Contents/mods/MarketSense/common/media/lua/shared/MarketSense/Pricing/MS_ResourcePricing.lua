require "MarketSense/MS_Config"

-- MarketSense resource pricing.
--
-- Resources are deliberately in an evidence-only phase.  The category mixes
-- raw and refined materials, fuel, hardware, construction inputs, animal
-- parts, and packaged supplies.  A useful anchor must compare delivered
-- utility, processing cost, quantity, and weight rather than add dollars for
-- a broad material label.  Keep every mechanically observable input visible
-- while those anchors are calibrated.

MarketSense = MarketSense or {}
MarketSense.ResourcePricing = MarketSense.ResourcePricing or {}

local ResourcePricing = MarketSense.ResourcePricing
local Config = MarketSense.ItemRuntimeConfig

local function configuredModel()
    local configured = Config and Config.resourcePricing
    local model = type(configured) == "table" and configured.model or nil
    if type(model) ~= "string" or model == "" then
        return "resource_v2_pending"
    end
    return model
end

local function copyList(value)
    if type(value) ~= "table" then return {} end
    local result = {}
    for index, entry in ipairs(value) do
        result[index] = entry
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

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function containsAny(text, markers)
    text = lower(text)
    for _, marker in ipairs(markers) do
        if string.find(text, marker, 1, true) then return true end
    end
    return false
end

local function inferMaterialForm(ctx)
    local text = table.concat({
        ctx.idLower or ctx.typeName or "",
        ctx.displayNameLower or ctx.displayName or "",
        ctx.descriptionLower or ctx.description or "",
        ctx.worldStaticModelLower or ctx.worldStaticModel or "",
        ctx.worldObjectSpriteLower or ctx.worldObjectSprite or "",
    }, " ")

    -- The order is intentional: packaging describes the delivered unit,
    -- while words such as "metal" or "wood" describe the family only.
    local forms = {
        { "bundle", "bundled" },
        { "carton", "box", "crate", "pack", "stack" },
        { "powder", "dust" },
        { "ore", "raw" },
        { "scrap", "fragment", "shard" },
        { "mold", "mould" },
        { "ingot", "bloom", "billet" },
        { "sheet", "plate", "panel" },
        { "coin", "currency" },
        { "bar", "rod", "band", "slug" },
        { "block", "brick" },
        { "chunk", "log" },
        { "plank", "board" },
        { "piece", "part" },
        { "bottle", "can", "tank", "jerry" },
    }
    local names = {
        "bundle", "package", "powder", "ore", "scrap", "mold", "ingot",
        "sheet", "coin", "bar", "block", "chunk", "plank", "piece",
        "container",
    }
    for index, markers in ipairs(forms) do
        if containsAny(text, markers) then return names[index] end
    end
    return "unknown"
end

local function materialFamily(subtype)
    local text = tostring(subtype or "")
    if string.sub(text, 1, 8) == "Material" then
        local family = string.sub(text, 9)
        return family ~= "" and family or "Material"
    end
    if string.sub(text, 1, 8) == "Resource" then
        local family = string.sub(text, 9)
        return family ~= "" and family or "Resource"
    end
    return text ~= "" and text or "Unknown"
end

function ResourcePricing.buildPendingHeuristic(ctx, details)
    ctx = ctx or {}
    details = details or {}

    local classification = type(details.classificationDetails) == "table"
        and details.classificationDetails or {}
    local yield = type(details.yieldResolution) == "table"
        and details.yieldResolution or {}
    local yieldOutputs, yieldQuantity = copyYieldOutputs(yield.outputs)
    local subtype = details.primary or "ResourceUnknown"
    local yieldStatus = yield.status or "not_detected"
    local hasYield = details.yieldResolution ~= nil
    local deterministicYield = hasYield and yieldStatus == "resolved"
    local hasUnbundleSignal = (ctx.openingRecipe or "") ~= ""
        or (ctx.doubleClickRecipe or "") ~= ""
        or #yieldOutputs > 0

    return {
        model = configuredModel(),
        status = "pending",
        reason = "Legacy resource flat additions removed; awaiting calibrated utility, quantity, and processing anchors.",
        subtype = subtype,
        materialFamily = materialFamily(subtype),
        materialForm = inferMaterialForm(ctx),
        classifierSource = classification.source,
        classifierTag = classification.tag,
        displayCategory = ctx.displayCategory,
        itemType = ctx.itemType,
        lootType = ctx.lootType,
        description = ctx.description,
        worldStaticModel = ctx.worldStaticModel,
        worldObjectSprite = ctx.worldObjectSprite,
        weight = ctx.weight,
        weightEmpty = ctx.weightEmpty,
        canStack = ctx.canStack,
        stackCount = ctx.stackCount,
        isCraftRecipeProduct = ctx.isCraftRecipeProduct == true,
        canSpawnAsLoot = ctx.canSpawnAsLoot == true,
        canBeForaged = ctx.canBeForaged == true,
        isMoveable = ctx.isMoveable == true,
        conditionMax = ctx.conditionMax,
        condition = ctx.condition,
        conditionRatio = ctx.conditionRatio,
        isDrainable = ctx.isDrainable == true,
        isDrainableInstance = ctx.isDrainableInstance == true,
        useDelta = ctx.useDelta,
        maxUses = ctx.maxUses,
        currentUsesFloat = ctx.currentUsesFloat,
        remainingUsesRatio = ctx.remainingUsesRatio,
        replaceOnDeplete = ctx.replaceOnDeplete,
        isDisappearOnUse = ctx.isDisappearOnUse,
        isPoison = ctx.isPoison == true,
        isDung = ctx.isDung == true,
        fluidType = ctx.fluidType,
        fluidTypeString = ctx.fluidTypeString,
        fluidCategory = ctx.fluidCategory,
        fluidCategories = copyList(ctx.fluidCategories),
        fluidAmount = ctx.fluidAmount,
        fluidCapacity = ctx.fluidCapacity,
        fluidFilledRatio = ctx.fluidFilledRatio,
        unbundleCandidate = hasUnbundleSignal,
        yieldStatus = yieldStatus,
        yieldRecipe = yield.recipe,
        yieldOutputCount = #yieldOutputs,
        yieldOutputQuantity = yieldQuantity,
        yieldOutputs = yieldOutputs,
        staticMetricsAvailable = {
            classification = details.primary ~= nil and details.primary ~= "",
            materialForm = true,
            weight = ctx.weight ~= nil,
            stackability = ctx.canStack ~= nil and ctx.canStack ~= "",
            stackCount = ctx.stackCount ~= nil,
            condition = ctx.conditionMax ~= nil or ctx.conditionRatio ~= nil,
            drainableUses = ctx.maxUses ~= nil or ctx.remainingUsesRatio ~= nil,
            recipeProduct = ctx.isCraftRecipeProduct ~= nil,
            packageSignal = hasUnbundleSignal,
            fluidIdentity = (ctx.fluidType or "") ~= ""
                or (ctx.fluidTypeString or "") ~= "",
            yield = hasYield,
            deterministicYield = deterministicYield,
        },
        plannedPositiveAnchors = {
            "verified player-useful material role and subtype",
            "deterministic child-item yield multiplied by output quantity",
            "stack quantity or remaining usable amount",
            "refined or directly usable form with less processing required",
            "verified fuel, construction, repair, crafting, or survival function",
            "recipe/component demand when the runtime graph proves it",
            "utility delivered per unit of weight and encumbrance",
        },
        plannedNegativeAnchors = {
            "weight, bulk, and handling burden relative to delivered utility",
            "raw, ore, scrap, mold, or other processing-stage cost",
            "depleted, damaged, broken, empty, or partial-use state",
            "required workstation, tool, fuel, power, or extra processing",
            "hazard, poison, contamination, or harmful handling state",
            "ambiguous classification or unknown material form",
            "probabilistic or unresolved package yield",
            "rarity, theme, or display labels without mechanical utility",
            "double-counting a parent package and its child outputs",
        },
    }
end

return ResourcePricing
