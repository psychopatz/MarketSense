require "MarketSense/MS_Config"

-- MarketSense liquid pricing.
--
-- Liquid is deliberately in an evidence-only phase.  A fluid container exposes
-- reliable measurements, but a useful market anchor must still distinguish
-- potable utility, harmful state, mixtures, processing requirements, and
-- deterministic package yields.  Keeping those inputs in the heuristic now
-- lets the resolver and offline inspector show exactly what still needs to be
-- calibrated without assigning misleading per-litre prices.

MarketSense = MarketSense or {}
MarketSense.LiquidPricing = MarketSense.LiquidPricing or {}
MarketSense.FluidPricing = nil

local LiquidPricing = MarketSense.LiquidPricing
local Config = MarketSense.ItemRuntimeConfig

local function configuredModel()
    local configured = Config and Config.liquidPricing
    local model = type(configured) == "table" and configured.model or nil
    if type(model) ~= "string" or model == "" then
        return "liquid_v2_pending"
    end
    return model
end

local function list(value)
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

local function hasEffectEvidence(ctx)
    local function nonZero(value)
        return math.abs(tonumber(value) or 0) > 0
    end
    return nonZero(ctx.hungerChange)
        or nonZero(ctx.thirstChange)
        or nonZero(ctx.unhappyChange)
        or nonZero(ctx.boredomChange)
        or nonZero(ctx.stressChange)
        or nonZero(ctx.alcoholPower)
        or nonZero(ctx.painReduction)
        or nonZero(ctx.fluReduction)
        or nonZero(ctx.foodSicknessChange)
end

function LiquidPricing.buildPendingHeuristic(ctx, details)
    ctx = ctx or {}
    details = details or {}

    local classification = type(details.classificationDetails) == "table"
        and details.classificationDetails or {}
    local yield = type(details.yieldResolution) == "table"
        and details.yieldResolution or {}
    local yieldOutputs, yieldQuantity = copyYieldOutputs(yield.outputs)
    local fluidCategories = list(ctx.fluidCategories)
    local hasFluidIdentity = (ctx.fluidTypeString or "") ~= ""
        or (ctx.fluidType or "") ~= ""
    local hasFluidContainer = ctx.isFluidContainer == true

    return {
        model = configuredModel(),
        status = "pending",
        reason = "Legacy liquid per-litre scoring removed; awaiting calibrated utility anchors.",
        subtype = details.primary or "LiquidUnknown",
        classifierSource = classification.source,
        classifierTag = classification.tag,
        isActualLiquid = ctx.isActualLiquid == true,
        isFluidContainer = hasFluidContainer,
        fluidType = ctx.fluidType,
        fluidTypeString = ctx.fluidTypeString,
        fluidCategory = ctx.fluidCategory,
        fluidCategories = fluidCategories,
        fluidAmount = ctx.fluidAmount,
        fluidCapacity = ctx.fluidCapacity,
        fluidPrimaryAmount = ctx.fluidPrimaryAmount,
        fluidFilledRatio = ctx.fluidFilledRatio,
        fluidIsEmpty = ctx.fluidIsEmpty == true,
        fluidIsMixture = ctx.fluidIsMixture == true,
        containerName = ctx.fluidContainerName,
        weight = ctx.weight,
        hungerChange = ctx.hungerChange,
        thirstChange = ctx.thirstChange,
        unhappyChange = ctx.unhappyChange,
        boredomChange = ctx.boredomChange,
        stressChange = ctx.stressChange,
        alcoholPower = ctx.alcoholPower,
        painReduction = ctx.painReduction,
        fluReduction = ctx.fluReduction,
        foodSicknessChange = ctx.foodSicknessChange,
        isPoison = ctx.isPoison == true,
        hasRuntimeFoodState = ctx.hasRuntimeFoodState == true,
        foodAge = ctx.foodAge,
        foodDaysFresh = ctx.foodDaysFresh,
        foodDaysRotten = ctx.foodDaysRotten,
        isRotten = ctx.isRotten == true,
        isFrozen = ctx.isFrozen == true,
        yieldStatus = yield.status,
        yieldRecipe = yield.recipe,
        yieldOutputCount = #yieldOutputs,
        yieldOutputQuantity = yieldQuantity,
        yieldOutputs = yieldOutputs,
        staticMetricsAvailable = {
            classification = details.primary ~= nil and details.primary ~= "",
            fluidContainer = hasFluidContainer,
            fluidIdentity = hasFluidIdentity,
            fluidCategories = #fluidCategories > 0,
            measuredAmount = hasFluidContainer,
            measuredCapacity = hasFluidContainer,
            measuredPrimaryAmount = hasFluidContainer,
            filledRatio = hasFluidContainer,
            emptyState = hasFluidContainer,
            mixtureState = hasFluidContainer,
            playerEffects = hasEffectEvidence(ctx),
            runtimeFoodState = ctx.hasRuntimeFoodState == true,
            weight = ctx.weight ~= nil,
            yield = details.yieldResolution ~= nil,
            deterministicYield = details.yieldResolution ~= nil
                and yield.status == "resolved",
        },
        plannedPositiveAnchors = {
            "measured usable liquid amount, never vessel capacity alone",
            "verified player utility such as hydration, nutrition, mood, or health",
            "verified fluid function such as fuel, medical, cleaning, dye, or industrial use",
            "safe consumption, transfer, and processing compatibility",
            "deterministic child-item yield multiplied by output quantity",
            "stable shelf life and preserved runtime state when mechanically verified",
        },
        plannedNegativeAnchors = {
            "empty or zero-amount content",
            "rotten, tainted, poisonous, or otherwise harmful state",
            "mixture with only a primary component known",
            "unknown fluid identity, category, or player effect",
            "container weight, bulk, and handling burden",
            "required equipment, fuel, power, or processing step",
            "probabilistic, ambiguous, or unresolved package yield",
            "capacity mistaken for liquid value or vessel value counted twice",
        },
    }
end

return LiquidPricing
