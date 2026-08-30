require "MarketSense/MS_Config"

-- MarketSense medical pricing.
-- The numerical medical model is intentionally pending calibration.

MarketSense = MarketSense or {}
MarketSense.MedicalPricing = MarketSense.MedicalPricing or {}

local MedicalPricing = MarketSense.MedicalPricing
local Config = MarketSense.ItemRuntimeConfig

local function configuredModel()
    local configured = Config and Config.medicalPricing
    local model = type(configured) == "table" and configured.model or nil
    if type(model) ~= "string" or model == "" then
        return "medical_v2_pending"
    end
    return model
end

function MedicalPricing.buildPendingHeuristic(ctx, details)
    ctx = ctx or {}
    details = details or {}

    local classification = type(details.classificationDetails) == "table"
        and details.classificationDetails or {}
    local yield = type(details.yieldResolution) == "table"
        and details.yieldResolution or {}

    return {
        model = configuredModel(),
        status = "pending",
        reason = "Legacy medical scoring removed; awaiting calibrated treatment anchors.",
        subtype = details.primary or "Medical",
        classifierSource = classification.source,
        classifierTag = classification.tag,
        displayCategory = ctx.displayCategory,
        itemType = ctx.itemType,
        lootType = ctx.lootType,
        isMedicalLoot = ctx.isMedicalLoot == true,
        canBandage = ctx.canBandage == true,
        useSelf = ctx.useSelf,
        bandagePower = ctx.bandagePower,
        reduceInfectionPower = ctx.reduceInfectionPower,
        alcoholPower = ctx.alcoholPower,
        painReduction = ctx.painReduction,
        fluReduction = ctx.fluReduction,
        foodSicknessChange = ctx.foodSicknessChange,
        conditionMax = ctx.conditionMax,
        condition = ctx.condition,
        conditionRatio = ctx.conditionRatio,
        weight = ctx.weight,
        useDelta = ctx.useDelta,
        maxUses = ctx.maxUses,
        remainingUsesRatio = ctx.remainingUsesRatio,
        replaceOnUse = ctx.replaceOnUse,
        replaceOnUseOn = ctx.replaceOnUseOn,
        isDisappearOnUse = ctx.isDisappearOnUse,
        yieldStatus = yield.status,
        yieldRecipe = yield.recipe,
        yieldOutputCount = type(yield.outputs) == "table" and #yield.outputs or 0,
        staticMetricsAvailable = {
            classification = details.primary ~= nil and details.primary ~= "",
            medicalLoot = ctx.isMedicalLoot ~= nil,
            bandagePower = ctx.bandagePower ~= nil,
            infectionTreatment = ctx.reduceInfectionPower ~= nil,
            alcoholPower = ctx.alcoholPower ~= nil,
            symptomRelief = ctx.painReduction ~= nil or ctx.fluReduction ~= nil
                or ctx.foodSicknessChange ~= nil,
            bandageCapability = ctx.canBandage ~= nil,
            conditionMax = ctx.conditionMax ~= nil,
            weight = ctx.weight ~= nil,
            uses = ctx.useDelta ~= nil or ctx.maxUses ~= nil,
            replacement = ctx.replaceOnUse ~= nil or ctx.replaceOnUseOn ~= nil,
            deterministicYield = details.yieldResolution ~= nil,
        },
        plannedPositiveAnchors = {
            "verified treatment effect and patient-facing outcome",
            "wound coverage, bandage power, and infection reduction",
            "pain, flu, food-sickness, or other verified symptom relief",
            "deterministic doses, remaining uses, and replacement output",
            "sterility or clean-use state when mechanically verified",
            "repair, crafting, or reusable medical utility when explicitly resolved",
            "deterministic child-item yield multiplied by output quantity",
        },
        plannedNegativeAnchors = {
            "weight, bulk, and handling cost per treatment delivered",
            "depleted uses, consumed-on-use state, or missing replacement",
            "broken, damaged, expired, or unusable state when exposed",
            "side effects, toxicity, addiction, or operating risk when evidenced",
            "narrow treatment compatibility or patient-condition restrictions",
            "ambiguous medical names, rarity, or display labels without effect evidence",
        },
    }
end

return MedicalPricing
