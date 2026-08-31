-- MarketSense vessel pricing.
--
-- A filled item has two distinct things being sold: its contents and the
-- vessel that remains usable or recoverable with it.  This module resolves
-- the vessel evidence without invoking a content scorer, then returns a
-- small dollar contribution that the balance stage can append exactly once.

require "MarketSense/MS_Config"
require "MarketSense/MS_Core"

MarketSense = MarketSense or {}
MarketSense.VesselPricing = MarketSense.VesselPricing or {}

local VesselPricing = MarketSense.VesselPricing
local Config = MarketSense.ItemRuntimeConfig
local Core = MarketSense.Core

local DEFAULTS = {
    model = "vessel_v1",
    enabled = true,
    baseValue = 0,
    capacityValue = 1.0,
    weightPenalty = 0.25,
    openedPenalty = 1.0,
    sealedBonus = 0,
    retainedBonus = 0,
    unknownValue = 1,
}

local PROFILE_RULES = {
    { key = "hydration_backpack", name = "Hydration backpack", value = 7,
        markers = { "hydrationbackpack" } },
    { key = "jerrycan", name = "Jerry can", value = 7,
        markers = { "jerrycan", "gascan" } },
    { key = "bucket", name = "Bucket", value = 5,
        markers = { "bucket" } },
    { key = "watering_can", name = "Watering can", value = 5,
        markers = { "wateringcan" } },
    { key = "pot", name = "Pot", value = 12,
        markers = { "pot", "saucepan", "kettle" } },
    { key = "canteen", name = "Canteen", value = 4,
        markers = { "canteen", "leatherwaterbag", "waterskin" } },
    { key = "flask", name = "Flask", value = 3,
        markers = { "flask" } },
    { key = "baking_pan", name = "Baking pan", value = 3,
        markers = { "bakingpan", "bakingtray", "muffintray", "tray" } },
    { key = "tin_can", name = "Tin can", value = 2,
        markers = { "tincan", "canned", "tinned" } },
    { key = "glass_bottle", name = "Glass bottle", value = 3,
        markers = { "bottleglass" } },
    { key = "beer_bottle", name = "Bottle", value = 2,
        markers = { "bottlebeer" } },
    { key = "plastic_bottle", name = "Plastic bottle", value = 2,
        markers = { "bottleplastic", "sportsbottle", "bottle" } },
    { key = "can", name = "Can", value = 2,
        markers = { "canpop", "canbeer", "sodacan", "can" } },
    { key = "carton", name = "Carton", value = 1,
        markers = { "smallcarton", "carton", "juicebox" } },
    { key = "dish", name = "Dish", value = 1,
        markers = { "dish", "bowl", "mug", "teacup", "cup" } },
    { key = "jar", name = "Jar", value = 2,
        markers = { "jar", "mayonnaiseempty", "remouladeempty" } },
    { key = "pan", name = "Pan", value = 4,
        markers = { "pan" } },
}

local VESSEL_MARKERS = {
    "pot", "pan", "sauce", "kettle", "bucket", "bowl", "dish", "tray",
    "muffin", "baking", "jar", "can", "bottle", "carton", "canteen",
    "flask", "bag", "cup", "mug", "tumbler", "glass", "watering",
    "jerry", "gascan", "crucible", "mayonnaiseempty", "remouladeempty",
}

local function number(value, fallback)
    value = tonumber(value)
    return value ~= nil and value or fallback
end

local function firstNonEmpty(...)
    for index = 1, select("#", ...) do
        local value = select(index, ...)
        if value ~= nil and tostring(value) ~= "" then
            return tostring(value)
        end
    end
    return ""
end

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function containsAny(value, markers)
    local text = lower(value)
    for _, marker in ipairs(markers or {}) do
        if string.find(text, marker, 1, true) then return true end
    end
    return false
end

local function lastPart(value)
    local text = tostring(value or "")
    return string.match(text, "([^%.]+)$") or text
end

local function fullType(value, moduleName)
    local text = tostring(value or "")
    if text == "" then return "" end
    if string.find(text, ".", 1, true) then return text end
    local module = tostring(moduleName or "Base")
    return module ~= "" and module .. "." .. text or text
end

local function settings()
    local configured = Config and Config.vesselPricing
    local result = {}
    for key, fallback in pairs(DEFAULTS) do
        result[key] = type(configured) == "table" and configured[key] ~= nil
            and configured[key] or fallback
    end
    return result, type(configured) == "table" and configured.profiles or nil
end

local function configuredProfile(rule, profiles)
    local result = {
        key = rule.key,
        name = rule.name,
        value = rule.value,
    }
    local override = profiles and profiles[rule.key]
    if type(override) == "table" then
        if override.name ~= nil then result.name = tostring(override.name) end
        if override.value ~= nil then result.value = number(override.value, result.value) end
    elseif override ~= nil then
        result.value = number(override, result.value)
    end
    return result
end

local function profileFor(name, profiles, unknownValue)
    local text = lower(name)
    for _, rule in ipairs(PROFILE_RULES) do
        if containsAny(text, rule.markers) then
            return configuredProfile(rule, profiles)
        end
    end
    return {
        key = "generic",
        name = "Generic vessel",
        value = number(unknownValue, DEFAULTS.unknownValue),
    }
end

local function isLikelyVessel(value)
    return containsAny(value, VESSEL_MARKERS)
end

local function isFood(details)
    local category = tostring(details and details.category or "")
    return category == "Food" or category == "Beverage"
end

local function hasTag(details, wanted)
    for _, tag in ipairs(details and details.expandedTags or {}) do
        if tostring(tag) == wanted then return true end
    end
    for _, tag in ipairs(details and details.tags or {}) do
        if tostring(tag) == wanted then return true end
    end
    return false
end

local function isCanned(details, ctx)
    return hasTag(details, "FoodNonPerishableCanned")
        or containsAny(firstNonEmpty(ctx and ctx.idLower,
            ctx and ctx.typeName, ctx and ctx.fullType), { "canned", "tinned", "tin" })
end

local function isOpened(ctx)
    return containsAny(firstNonEmpty(ctx and ctx.idLower,
        ctx and ctx.typeName, ctx and ctx.fullType), { "open", "opened" })
end

local function readVesselContext(vesselFullType)
    local reader = MarketSense.PropertyReader
    if not reader or type(reader.buildContext) ~= "function" then return nil end
    local ok, result = pcall(reader.buildContext, vesselFullType, nil, true)
    return ok and type(result) == "table" and result or nil
end

local function vesselFromFluidContainer(ctx)
    local name = tostring(ctx and ctx.fluidContainerName or "")
    if name == "" or ctx.isFluidContainer ~= true then return nil end
    return {
        name = name,
        fullType = nil,
        source = "fluid_container",
        state = ctx.isActualLiquid == true and "filled" or "empty",
        capacity = math.max(0, number(ctx.fluidCapacity, 0)),
        weight = 0,
    }
end

local function vesselFromReplacement(ctx, source, state)
    local replacement = firstNonEmpty(ctx and ctx.replaceOnUse,
        ctx and ctx.replaceOnUseOn, ctx and ctx.replaceOnCooked)
    if replacement == "" or not isLikelyVessel(replacement) then return nil end

    local replacementFullType = fullType(replacement, ctx.moduleName)
    local replacementContext = readVesselContext(replacementFullType)
    local name = replacementContext and replacementContext.fluidContainerName or ""
    if name == "" then name = lastPart(replacementFullType) end
    return {
        name = name,
        fullType = replacementFullType,
        source = source or "replace_on_use",
        state = state or (isOpened(ctx) and "opened" or "retained"),
        capacity = replacementContext
            and math.max(number(replacementContext.capacity, 0),
                number(replacementContext.fluidCapacity, 0)) or 0,
        weight = replacementContext and number(replacementContext.weight, 0) or 0,
    }
end

local function vesselFromVariant(ctx, details)
    if isOpened(ctx) or not isCanned(details, ctx) then return nil end
    local evidence = ctx and ctx.foodVariantEvidence
    if type(evidence) ~= "table" then
        evidence = details and details.foodVariantEvidence
    end
    if type(evidence) ~= "table"
        or (evidence.status ~= "verified" and evidence.status ~= "corroborated")
        or tostring(evidence.sourceFullType or "") == ""
    then
        return nil
    end

    -- Some preserved foods expose an opened counterpart by name but have no
    -- openingRecipe. Resolve that counterpart's returned vessel so the
    -- sealed item still carries the same can/jar value as its open form.
    local openedContext = readVesselContext(evidence.sourceFullType)
    local vessel = vesselFromReplacement(openedContext, "variant_replacement", "sealed")
    return vessel
end

local function vesselFromOpeningRecipe(ctx, details)
    if not isFood(details) or not isCanned(details, ctx) then return nil end
    if tostring(ctx and ctx.openingRecipe or "") == "" then return nil end
    return {
        name = "TinCanEmpty",
        fullType = fullType("TinCanEmpty", "Base"),
        source = "opening_recipe",
        state = "sealed",
        capacity = 0,
        weight = 0,
    }
end

function VesselPricing.resolve(ctx, details)
    ctx = ctx or {}
    details = details or {}

    local direct = vesselFromFluidContainer(ctx)
    if direct then return direct end

    if isFood(details) then
        local retained = vesselFromReplacement(ctx)
        if retained then return retained end
        local variant = vesselFromVariant(ctx, details)
        if variant then return variant end
        local sealed = vesselFromOpeningRecipe(ctx, details)
        if sealed then return sealed end
    end
    return nil
end

function VesselPricing.calculate(ctx, details)
    ctx = ctx or {}
    details = details or {}
    local c, profiles = settings()
    local result = {
        model = tostring(c.model or DEFAULTS.model),
        value = 0,
        status = "not_applicable",
        source = "none",
        state = "none",
        vesselName = nil,
        vesselFullType = nil,
        vesselProfile = nil,
        capacity = 0,
        weight = 0,
    }
    if c.enabled == false then
        result.status = "disabled"
        return result
    end

    local vessel = VesselPricing.resolve(ctx, details)
    if not vessel then return result end

    -- Empty Container roots already use the full container scorer.  The
    -- separate component is for content-bearing liquids and food only.
    local category = tostring(details.category or "")
    if category ~= "Liquid" and not isFood(details) then return result end
    if category == "Liquid" and ctx.isActualLiquid ~= true then return result end

    local profile = profileFor(vessel.name, profiles, c.unknownValue)
    local capacity = math.max(number(vessel.capacity, 0), 0)
    local weight = math.max(number(vessel.weight, 0), 0)
    local value = number(profile.value, 0) + number(c.baseValue, 0)
        + (math.sqrt(capacity) * number(c.capacityValue, 0))
        - (weight * number(c.weightPenalty, 0))
    if vessel.state == "opened" then
        value = value - number(c.openedPenalty, 0)
    elseif vessel.state == "sealed" then
        value = value + number(c.sealedBonus, 0)
    elseif vessel.state == "retained" then
        value = value + number(c.retainedBonus, 0)
    end

    result.status = "ready"
    result.value = math.max(0, Core.round(value))
    result.source = vessel.source
    result.state = vessel.state
    result.vesselName = vessel.name
    result.vesselFullType = vessel.fullType
    result.vesselProfile = profile.key
    result.capacity = capacity
    result.weight = weight
    return result
end

VesselPricing.profileRules = PROFILE_RULES
return VesselPricing
