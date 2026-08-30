require "MarketSense/MS_Config"

-- MarketSense electronics pricing.
-- The numerical electronics model is intentionally pending calibration.

MarketSense = MarketSense or {}
MarketSense.ElectronicsPricing = MarketSense.ElectronicsPricing or {}

local ElectronicsPricing = MarketSense.ElectronicsPricing
local Config = MarketSense.ItemRuntimeConfig

local function configuredModel()
    local configured = Config and Config.electronicsPricing
    local model = type(configured) == "table" and configured.model or nil
    if type(model) ~= "string" or model == "" then
        return "electronics_v2_pending"
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

function ElectronicsPricing.buildPendingHeuristic(ctx, details)
    ctx = ctx or {}
    details = details or {}

    local classification = type(details.classificationDetails) == "table"
        and details.classificationDetails or {}
    local capabilities = type(ctx.capabilities) == "table"
        and ctx.capabilities or {}
    local device = type(ctx.deviceData) == "table" and ctx.deviceData or {}

    return {
        model = configuredModel(),
        status = "pending",
        reason = "Legacy electronics scoring removed; awaiting calibrated functional anchors.",
        subtype = details.primary or "Electronics",
        classifierSource = classification.source,
        classifierTag = classification.tag,
        displayCategory = ctx.displayCategory,
        itemType = ctx.itemType,
        weight = ctx.weight,
        conditionMax = ctx.conditionMax,
        condition = ctx.condition,
        conditionRatio = ctx.conditionRatio,
        isMoveable = ctx.isMoveable == true,
        canBeEquipped = ctx.canBeEquipped,
        isDrainable = ctx.isDrainable == true,
        maxUses = ctx.maxUses,
        remainingUsesRatio = ctx.remainingUsesRatio,
        lightStrength = ctx.lightStrength,
        lightDistance = ctx.lightDistance,
        lightCanEmit = ctx.lightCanEmit,
        lightUseBattery = ctx.lightUseBattery,
        lightHasBattery = ctx.lightHasBattery,
        deviceDataAvailable = ctx.deviceDataAvailable == true,
        deviceIsBatteryPowered = device.isBatteryPowered,
        deviceHasBattery = device.hasBattery,
        deviceIsTelevision = device.isTelevision,
        deviceIsTwoWay = device.isTwoWay,
        deviceIsPortable = device.isPortable,
        deviceIsHighTier = device.isHighTier,
        deviceMinChannelRange = device.minChannelRange,
        deviceMaxChannelRange = device.maxChannelRange,
        deviceTransmitRange = device.transmitRange,
        devicePower = device.power,
        deviceIsTurnedOn = device.isTurnedOn,
        capabilities = list(capabilities.capabilities),
        requirements = list(capabilities.requirements),
        capabilityEvidence = list(capabilities.evidence),
        powerSource = capabilities.powerSource,
        worldEvidenceAvailable = capabilities.available == true,
        staticMetricsAvailable = {
            classification = details.primary ~= nil and details.primary ~= "",
            weight = ctx.weight ~= nil,
            conditionMax = ctx.conditionMax ~= nil,
            lightStrength = ctx.lightStrength ~= nil,
            lightDistance = ctx.lightDistance ~= nil,
            lightState = ctx.lightCanEmit ~= nil,
            lightBattery = ctx.lightUseBattery ~= nil or ctx.lightHasBattery ~= nil,
            radioDeviceData = ctx.deviceDataAvailable == true,
            radioRange = device.transmitRange ~= nil
                or device.minChannelRange ~= nil or device.maxChannelRange ~= nil,
            powerState = device.power ~= nil or device.isBatteryPowered ~= nil,
            worldCapabilities = capabilities.available == true,
        },
        plannedPositiveAnchors = {
            "verified functional capability and player-useful role",
            "radio or transmitter range, two-way capability, and channel coverage",
            "light strength and coverage distance",
            "battery capacity or remaining usable power when measured",
            "generator output and fuel efficiency when exposed by the world object",
            "portable, wearable, or deployable access when mechanically verified",
            "repair, dismantling, or reusable recipe utility when explicitly resolved",
        },
        plannedNegativeAnchors = {
            "weight, bulk, and carrying or placement cost",
            "empty battery, depleted charge, broken state, or low remaining uses",
            "electricity, fuel, water, or other operating requirements",
            "stationary-only access, narrow range, or poor coverage",
            "noise, visibility, risk, and maintenance burden when mechanically evidenced",
            "ambiguous name/tag classification or rarity without functional evidence",
        },
    }
end

return ElectronicsPricing
