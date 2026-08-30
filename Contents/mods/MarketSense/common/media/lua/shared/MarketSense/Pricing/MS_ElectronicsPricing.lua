-- MarketSense electronics pricing.
-- Functional evidence is preferred over names: light, radio/device data,
-- capabilities, remaining power, and portability are independently visible.

require "MarketSense/MS_Config"
require "MarketSense/MS_Core"
require "MarketSense/Pricing/MS_PricingUtils"
require "MarketSense/Pricing/MS_TransformPricing"

MarketSense = MarketSense or {}
MarketSense.ElectronicsPricing = MarketSense.ElectronicsPricing or {}

local ElectronicsPricing = MarketSense.ElectronicsPricing
local Config = MarketSense.ItemRuntimeConfig
local Core = MarketSense.Core
local Utils = require "MarketSense/Pricing/MS_PricingUtils"
local TransformPricing = MarketSense.TransformPricing

local DEFAULTS = {
    model = "electronics_v2", anchor = 14.0, floor = 1.0, ceiling = 300.0,
    capabilityWeight = 2.0, lightStrengthWeight = 1.0, lightDistanceWeight = 0.12,
    radioRangeWeight = 0.08, radioAnchor = 2.0, highTierAnchor = 2.0,
    portableAnchor = 1.5, weightPenalty = 0.8, powerPenalty = 2.0,
    missingBatteryPenalty = 3.0, conditionFloor = 0.20,
    yieldMultiplier = 1.0, yieldPremium = 0.0,
}

local function number(value, fallback)
    value = tonumber(value)
    return value ~= nil and value or fallback
end

local function settings()
    local configured = Config and Config.electronicsPricing
    if type(configured) ~= "table" then return DEFAULTS end
    local result = {}
    for key, fallback in pairs(DEFAULTS) do
        result[key] = configured[key] ~= nil and configured[key] or fallback
    end
    return result
end

local function text(value)
    return string.lower(tostring(value or ""))
end

function ElectronicsPricing.calculate(ctx, details)
    ctx = ctx or {}
    details = details or {}
    local c = settings()
    local capabilityData = type(ctx.capabilities) == "table" and ctx.capabilities or {}
    local device = type(ctx.deviceData) == "table" and ctx.deviceData or {}
    local capabilities = capabilityData.capabilities or {}
    local heuristic = {
        model = tostring(c.model or DEFAULTS.model), status = "ready",
        subtype = details.primary or "Electronics",
        reason = "Electronics value is based on verified device, light, power, and portability utility.",
        displayCategory = ctx.displayCategory, itemType = ctx.itemType,
        weight = ctx.weight, conditionMax = ctx.conditionMax,
        condition = ctx.condition, conditionRatio = ctx.conditionRatio,
        isMoveable = ctx.isMoveable == true, canBeEquipped = ctx.canBeEquipped,
        isDrainable = ctx.isDrainable == true, maxUses = ctx.maxUses,
        remainingUsesRatio = ctx.remainingUsesRatio,
        lightStrength = ctx.lightStrength, lightDistance = ctx.lightDistance,
        lightCanEmit = ctx.lightCanEmit, lightUseBattery = ctx.lightUseBattery,
        lightHasBattery = ctx.lightHasBattery, deviceDataAvailable = ctx.deviceDataAvailable == true,
        deviceIsBatteryPowered = device.isBatteryPowered, deviceHasBattery = device.hasBattery,
        deviceIsTelevision = device.isTelevision, deviceIsTwoWay = device.isTwoWay,
        deviceIsPortable = device.isPortable, deviceIsHighTier = device.isHighTier,
        deviceMinChannelRange = device.minChannelRange,
        deviceMaxChannelRange = device.maxChannelRange,
        deviceTransmitRange = device.transmitRange, devicePower = device.power,
        capabilities = capabilities, requirements = capabilityData.requirements or {},
        capabilityEvidence = capabilityData.evidence or {},
        powerSource = capabilityData.powerSource,
        positiveContributions = {}, negativeContributions = {},
        plannedPositiveAnchors = {
            "verified functional capability and player-useful role",
            "radio or transmitter range, two-way capability, and channel coverage",
            "light strength and coverage distance",
            "remaining usable power or uses when measured",
            "portable, wearable, or deployable access",
            "repair, dismantling, or exact recipe utility",
        },
        plannedNegativeAnchors = {
            "weight, bulk, and carrying or placement cost",
            "empty battery, depleted charge, broken state, or low uses",
            "electricity, fuel, or other operating requirements",
            "stationary-only access, narrow range, or poor coverage",
            "noise, visibility, risk, and maintenance burden when evidenced",
            "names or rarity without functional evidence",
        },
    }
    Utils.addYieldEvidence(heuristic, details)

    local transformScore, transform = TransformPricing.evaluate(ctx, details, {
        multiplier = c.yieldMultiplier, premium = c.yieldPremium,
        floor = c.floor, ceiling = c.ceiling,
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
    local capabilityValue = math.min(10, #capabilities * number(c.capabilityWeight, 2))
    local lightValue = math.min(8,
        number(ctx.lightStrength, 0) * number(c.lightStrengthWeight, 1)
        + number(ctx.lightDistance, 0) * number(c.lightDistanceWeight, 0.12))
    local minRange = number(device.minChannelRange, 0)
    local maxRange = number(device.maxChannelRange, 0)
    local transmitRange = number(device.transmitRange, 0)
    local radioRange = math.min(8, math.max(maxRange, transmitRange, minRange)
        * number(c.radioRangeWeight, 0.08))
    local radioValue = device.isTwoWay == true and number(c.radioAnchor, 2) or 0
    local tierValue = device.isHighTier == true and number(c.highTierAnchor, 2) or 0
    local portableValue = (device.isPortable == true or ctx.isMoveable == true)
        and number(c.portableAnchor, 1.5) or 0
    Utils.addContribution(positives, "verified capability", capabilityValue, #capabilities)
    Utils.addContribution(positives, "light output", lightValue, ctx.lightStrength)
    Utils.addContribution(positives, "radio coverage", radioRange, maxRange > 0 and maxRange or transmitRange)
    Utils.addContribution(positives, "two-way communication", radioValue, device.isTwoWay)
    Utils.addContribution(positives, "high-tier device", tierValue, device.isHighTier)
    Utils.addContribution(positives, "portable access", portableValue, device.isPortable or ctx.isMoveable)

    local weightPenalty = math.min(12, math.max(0, number(ctx.weight, 0))
        * number(c.weightPenalty, 0.8))
    local powerPenalty = (capabilityData.powerSource ~= nil
        or device.isBatteryPowered == true) and number(c.powerPenalty, 2) or 0
    local batteryPenalty = device.isBatteryPowered == true and device.hasBattery == false
        and number(c.missingBatteryPenalty, 3) or 0
    Utils.addContribution(negatives, "weight burden", weightPenalty, ctx.weight)
    Utils.addContribution(negatives, "operating requirement", powerPenalty, capabilityData.powerSource)
    Utils.addContribution(negatives, "missing battery", batteryPenalty, device.hasBattery)
    local stateFactor = Utils.runtimeStateFactor(ctx, { conditionFloor = c.conditionFloor })
    local score, summary = Utils.scoreAnchors(c.anchor, positives, negatives, {
        stateFactor = stateFactor, floor = c.floor, ceiling = c.ceiling,
    })
    for key, value in pairs(summary) do heuristic[key] = value end
    heuristic.mode = "functional_electronics"
    heuristic.score = score
    details.priceHeuristic = heuristic
    return score
end

return ElectronicsPricing
