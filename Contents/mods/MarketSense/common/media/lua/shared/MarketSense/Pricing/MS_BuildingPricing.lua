require "MarketSense/MS_Config"

-- MarketSense Building pricing.
-- The numerical building model is intentionally pending calibration.

MarketSense = MarketSense or {}
MarketSense.BuildingPricing = MarketSense.BuildingPricing or {}

local BuildingPricing = MarketSense.BuildingPricing
local Config = MarketSense.ItemRuntimeConfig

local function configuredModel()
    local configured = Config and Config.buildingPricing
    local model = type(configured) == "table" and configured.model or nil
    if type(model) ~= "string" or model == "" then
        return "building_v2_pending"
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

function BuildingPricing.buildPendingHeuristic(ctx, details)
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

    return {
        model = configuredModel(),
        status = "pending",
        reason = "Legacy building scoring removed; awaiting calibrated function anchors.",
        subtype = details.primary or "Building",
        classifierSource = classification.source,
        classifierTag = classification.tag,
        displayCategory = ctx.displayCategory,
        itemType = ctx.itemType,
        isMoveable = ctx.isMoveable == true,
        canBeEquipped = ctx.canBeEquipped,
        weight = ctx.weight,
        conditionMax = ctx.conditionMax,
        condition = ctx.condition,
        conditionRatio = ctx.conditionRatio,
        capacity = ctx.capacity,
        weightReduction = ctx.weightReduction,
        worldEvidenceAvailable = world.available == true,
        worldObjectSprite = ctx.worldObjectSprite,
        worldStaticModel = ctx.worldStaticModel,
        worldObjectClass = world.objectClass,
        worldCustomName = world.customName,
        worldGroupName = world.groupName,
        worldContainerType = world.containerType,
        worldContainerCapacity = world.containerCapacity,
        worldSurface = world.surface,
        worldIsTable = world.isTable == true,
        worldIsTableTop = world.isTableTop == true,
        worldGenericCraftingSurface = world.genericCraftingSurface == true,
        capabilities = list(capabilityData.capabilities),
        requirements = list(capabilityData.requirements),
        capabilityEvidence = list(capabilityData.evidence),
        powerSource = capabilityData.powerSource,
        yieldStatus = yield.status,
        yieldRecipe = yield.recipe,
        yieldOutputCount = #yieldOutputs,
        yieldOutputQuantity = yieldQuantity,
        yieldOutputs = yieldOutputs,
        staticMetricsAvailable = {
            classification = details.primary ~= nil and details.primary ~= "",
            moveable = ctx.isMoveable ~= nil,
            weight = ctx.weight ~= nil,
            conditionMax = ctx.conditionMax ~= nil,
            inventoryCapacity = ctx.capacity ~= nil and ctx.capacity > 0,
            weightReduction = ctx.weightReduction ~= nil and ctx.weightReduction > 0,
            worldEvidence = world.available == true,
            worldContainerCapacity = world.containerCapacity ~= nil
                and world.containerCapacity > 0,
            worldCapabilities = #list(capabilityData.capabilities) > 0,
            capabilityRequirements = #list(capabilityData.requirements) > 0,
            deterministicYield = details.yieldResolution ~= nil
                and yield.status == "resolved",
        },
        plannedPositiveAnchors = {
            "verified player action or service enabled by the placed object",
            "usable storage capacity and saved carry weight",
            "crafting, processing, agriculture, medical, or recreation utility",
            "shelter, sleeping, deployability, and survival access",
            "portable or placeable access when mechanically verified",
            "durability, repairability, and reusable recipe utility",
            "deterministic child-item yield multiplied by output quantity",
        },
        plannedNegativeAnchors = {
            "weight, bulk, encumbrance, placement, and handling burden",
            "electricity, water, fuel, or other operating requirements",
            "stationary-only access, footprint, or difficult deployment",
            "broken, damaged, incomplete, or unusable state",
            "empty, ambiguous, or unresolved package contents",
            "decorative or rarity labels without mechanical utility",
        },
    }
end

return BuildingPricing
