-- MarketSense container pricing
-- The numerical container model is intentionally pending calibration.

MarketSense = MarketSense or {}
MarketSense.ContainerPricing = MarketSense.ContainerPricing or {}

local ContainerPricing = MarketSense.ContainerPricing

function ContainerPricing.buildPendingHeuristic(ctx, details)
    ctx = ctx or {}
    details = details or {}
    local yield = type(details.yieldResolution) == "table"
        and details.yieldResolution or {}

    return {
        model = "container_v2_pending",
        status = "pending",
        reason = "Legacy container scoring removed; awaiting calibrated storage anchors.",
        subtype = details.primary or "Container",
        capacity = ctx.capacity,
        weightReduction = ctx.weightReduction,
        weight = ctx.weight,
        conditionMax = ctx.conditionMax,
        condition = ctx.condition,
        conditionRatio = ctx.conditionRatio,
        canBeEquipped = ctx.canBeEquipped,
        bodyLocation = ctx.bodyLocation,
        bodyLocationToken = ctx.bodyLocationToken,
        isFluidContainer = ctx.isFluidContainer == true,
        isActualLiquid = ctx.isActualLiquid == true,
        contentYieldStatus = yield.status,
        contentYieldRecipe = yield.recipe,
        contentYieldOutputCount = type(yield.outputs) == "table"
            and #yield.outputs or 0,
        staticMetricsAvailable = {
            capacity = ctx.capacity ~= nil,
            weightReduction = ctx.weightReduction ~= nil,
            weight = ctx.weight ~= nil,
            conditionMax = ctx.conditionMax ~= nil,
            bodyLocation = ctx.bodyLocation ~= nil and ctx.bodyLocation ~= "",
            contentYield = details.yieldResolution ~= nil,
        },
        plannedPositiveAnchors = {
            "usable capacity within the container family",
            "weight reduction and saved carry weight",
            "portability or wearable access when verified",
            "verified special function such as ammo, medical, cooling, or tools",
            "deterministic child-content yield value when explicitly resolved",
            "durability and usable lifetime",
        },
        plannedNegativeAnchors = {
            "container weight relative to usable capacity",
            "low capacity or no meaningful storage utility",
            "movement and encumbrance cost",
            "broken, damaged, or inaccessible state",
            "empty or ambiguous content when a package is expected",
            "rarity, theme, or family labels without mechanical utility",
        },
    }
end

return ContainerPricing
