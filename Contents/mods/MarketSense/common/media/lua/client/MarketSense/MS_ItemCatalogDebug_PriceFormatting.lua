MarketSense = MarketSense or {}

local function demandText(value)
        if value == nil then return "-" end
        return string.format("%.2f", tonumber(value) or 0)
    end

local function formatFood(heuristic)
        return string.format(
            "Pricing: %s | subtype=%s | role=%s | ration=%s | hunger=%s | thirst=%s | freshness=%s | yield=%s",
            tostring(heuristic.status or "unknown"),
            tostring(heuristic.subtype or "Food"),
            tostring(heuristic.role or "edible"),
            demandText(heuristic.rationUnits),
            demandText(heuristic.hungerChange),
            demandText(heuristic.thirstChange),
            tostring(heuristic.freshnessState or "-"),
            tostring(heuristic.yieldStatus or "not_detected"))
end

local function formatLiterature(heuristic)
        return string.format(
            "Pricing: %s | subtype=%s | skill=%s | level=%s | recipes=%s | read=%s",
            tostring(heuristic.status or "pending"),
            tostring(heuristic.subtype or "Literature"),
            tostring(heuristic.skill or "-"),
            tostring(heuristic.skillLevel ~= nil and heuristic.skillLevel or "-"),
            tostring(heuristic.learnedRecipeCount ~= nil
                and heuristic.learnedRecipeCount or "-"),
            tostring(heuristic.readType or "-"))
end

local function formatLiquid(heuristic)
        local fluid = heuristic.fluidTypeString or heuristic.fluidType or "-"
        local mixture = heuristic.fluidIsMixture and "yes" or "no"
        return string.format(
            "Pricing: %s | subtype=%s | fluid=%s | amount=%s | primary=%s | ratio=%s | mixture=%s | yield=%s",
            tostring(heuristic.status or "pending"),
            tostring(heuristic.subtype or "LiquidUnknown"),
            tostring(fluid),
            tostring(heuristic.fluidAmount ~= nil and heuristic.fluidAmount or "-"),
            tostring(heuristic.fluidPrimaryAmount ~= nil
                and heuristic.fluidPrimaryAmount or "-"),
            demandText(heuristic.fluidFilledRatio),
            mixture,
            tostring(heuristic.yieldStatus or "not_detected"))
end

local function formatResource(heuristic)
        local yield = tostring(heuristic.yieldStatus or "not_detected")
        local outputs = tostring(heuristic.yieldOutputCount ~= nil
            and heuristic.yieldOutputCount or 0)
        local stack = heuristic.canStack
        if stack == nil or stack == "" then stack = "-" end
        return string.format(
            "Pricing: %s | subtype=%s | family=%s | form=%s | stack=%s | yield=%s (%s outputs, qty=%s)",
            tostring(heuristic.status or "pending"),
            tostring(heuristic.subtype or "ResourceUnknown"),
            tostring(heuristic.materialFamily or "-"),
            tostring(heuristic.materialForm or "unknown"),
            tostring(stack),
            yield,
            outputs,
            tostring(heuristic.yieldOutputQuantity ~= nil
                and heuristic.yieldOutputQuantity or 0))
end

local function formatMisc(heuristic)
        local signals = heuristic.signals or {}
        local signalText = signals[1] or "-"
        if signals[2] then signalText = signalText .. "," .. tostring(signals[2]) end
        local uses = heuristic.remainingUsesRatio
        if uses == nil then uses = heuristic.maxUses end
        local result = string.format(
            "Pricing: %s | subtype=%s | signals=%s | uses=%s | weight=%s | yield=%s (%s outputs, qty=%s)",
            tostring(heuristic.status or "pending"),
            tostring(heuristic.subtype or "Misc"),
            tostring(signalText),
            tostring(uses ~= nil and uses or "-"),
            tostring(heuristic.weight ~= nil and heuristic.weight or "-"),
            tostring(heuristic.yieldStatus or "not_detected"),
            tostring(heuristic.yieldOutputCount ~= nil
                and heuristic.yieldOutputCount or 0),
            tostring(heuristic.yieldOutputQuantity ~= nil
                and heuristic.yieldOutputQuantity or 0))
        if heuristic.mode ~= nil then
            result = result .. " | mode=" .. tostring(heuristic.mode)
        end
        if heuristic.yieldValue ~= nil then
            result = result .. " | value=" .. tostring(heuristic.yieldValue)
        end
        return result
end

local function formatWeapon(heuristic)
        local demand = heuristic.recipeDemand or {}
        return string.format(
            "Pricing: %s | class=%s | recipes=%s | reusable=%s | demand=%s | role=%s",
            tostring(heuristic.status or "pending"),
            tostring(heuristic.mechanicalClass or "-"),
            tostring(demand.recipeCount ~= nil and demand.recipeCount or "-"),
            tostring(demand.reusableRecipeCount ~= nil
                and demand.reusableRecipeCount or "-"),
            demandText(heuristic.recipeDemandScore),
            tostring(heuristic.marketRole or heuristic.role or "-"))
end

local function formatClothing(heuristic)
        return string.format(
            "Pricing: %s | subtype=%s | slot=%s | bite=%s | scratch=%s | bullet=%s",
            tostring(heuristic.status or "pending"),
            tostring(heuristic.subtype or "Clothing"),
            tostring(heuristic.bodyLocationToken or heuristic.bodyLocation or "-"),
            tostring(heuristic.biteDefense ~= nil and heuristic.biteDefense or "-"),
            tostring(heuristic.scratchDefense ~= nil and heuristic.scratchDefense or "-"),
            tostring(heuristic.bulletDefense ~= nil and heuristic.bulletDefense or "-"))
end

local function formatContainer(heuristic)
        local yieldStatus = heuristic.yieldStatus or heuristic.contentYieldStatus
        return string.format(
            "Pricing: %s | subtype=%s | capacity=%s | reduction=%s | weight=%s | yield=%s",
            tostring(heuristic.status or "pending"),
            tostring(heuristic.subtype or "Container"),
            tostring(heuristic.capacity ~= nil and heuristic.capacity or "-"),
            tostring(heuristic.weightReduction ~= nil and heuristic.weightReduction or "-"),
            tostring(heuristic.weight ~= nil and heuristic.weight or "-"),
            tostring(yieldStatus or "not_detected"))
end

local function formatElectronics(heuristic)
        local capabilities = heuristic.capabilities or {}
        local capability = capabilities[1] or "-"
        local device = heuristic.deviceDataAvailable and "device" or "no-device"
        local light = heuristic.lightStrength ~= nil
            and tostring(heuristic.lightStrength) or "-"
        return string.format(
            "Pricing: %s | subtype=%s | capability=%s | light=%s | %s",
            tostring(heuristic.status or "pending"),
            tostring(heuristic.subtype or "Electronics"),
            tostring(capability), light, device)
end

local function formatMedical(heuristic)
        local treatment = heuristic.bandagePower
            or heuristic.reduceInfectionPower
            or heuristic.painReduction
            or heuristic.fluReduction
            or heuristic.foodSicknessChange
        local effect = treatment ~= nil and tostring(treatment) or "-"
        return string.format(
            "Pricing: %s | subtype=%s | bandage=%s | infection=%s | effect=%s | yield=%s",
            tostring(heuristic.status or "pending"),
            tostring(heuristic.subtype or "Medical"),
            tostring(heuristic.bandagePower ~= nil and heuristic.bandagePower or "-"),
            tostring(heuristic.reduceInfectionPower ~= nil
                and heuristic.reduceInfectionPower or "-"),
            effect,
            tostring(heuristic.yieldStatus or "not_detected"))
end

local function formatBuilding(heuristic)
        local capabilities = heuristic.capabilities or {}
        local capability = capabilities[1] or "-"
        local evidence = heuristic.capabilityEvidence or {}
        local evidenceSource = evidence[1] or "-"
        local requirements = heuristic.requirements or {}
        local requirement = requirements[1] or "-"
        local capacity = heuristic.worldContainerCapacity
        if capacity == nil or capacity <= 0 then
            capacity = heuristic.capacity
        end
        local world = heuristic.worldEvidenceAvailable and "available" or "unavailable"
        return string.format(
            "Pricing: %s | subtype=%s | capability=%s | evidence=%s | requirement=%s | capacity=%s | world=%s | yield=%s",
            tostring(heuristic.status or "pending"),
            tostring(heuristic.subtype or "Building"),
            tostring(capability),
            tostring(evidenceSource),
            tostring(requirement),
            tostring(capacity ~= nil and capacity or "-"),
            world,
            tostring(heuristic.yieldStatus or "not_detected"))
end

local function formatTool(heuristic)
        local demand = heuristic.recipeDemand or {}
        return string.format(
            "Pricing: %s | subtype=%s | recipes=%s | reusable=%s | criticality=%s | demand=%s",
            tostring(heuristic.status or "ready"),
            tostring(heuristic.subtype or "Tool"),
            tostring(demand.recipeCount ~= nil and demand.recipeCount or "-"),
            tostring(demand.reusableRecipeCount ~= nil
                and demand.reusableRecipeCount or "-"),
            tostring(heuristic.recipeCriticality or "none"),
            demandText(heuristic.recipeDemandScore))
end

local MODEL_FORMATTERS = {
    ["food_v2"] = formatFood,
    ["food_v2_bundle"] = formatFood,
    ["literature_v2"] = formatLiterature,
    ["liquid_v2"] = formatLiquid,
    ["resource_v2"] = formatResource,
    ["misc_v2"] = formatMisc,
    ["misc_v2_bundle"] = formatMisc,
    ["weapon_v2"] = formatWeapon,
    ["clothing_v2"] = formatClothing,
    ["container_v2"] = formatContainer,
    ["electronics_v2"] = formatElectronics,
    ["medical_v2"] = formatMedical,
    ["building_v2"] = formatBuilding,
    ["tool_v2"] = formatTool,
}

local function priceHeuristicSummary(details)
    local heuristic = details and details.priceHeuristic
    if type(heuristic) ~= "table" then return nil end
    local formatter = MODEL_FORMATTERS[tostring(heuristic.model or "")]
    return formatter and formatter(heuristic) or nil
end

return {
    priceHeuristicSummary = priceHeuristicSummary,
}
