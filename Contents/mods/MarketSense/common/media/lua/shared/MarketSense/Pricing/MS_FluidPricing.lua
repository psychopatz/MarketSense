require "MarketSense/MS_Config"

MarketSense = MarketSense or {}
MarketSense.FluidPricing = MarketSense.FluidPricing or {}

local FluidPricing = MarketSense.FluidPricing
local Core = MarketSense.Core
local Config = MarketSense.ItemRuntimeConfig

local DATA_MODULE = "MarketSense/Pricing/MS_LiquidPricing_Data"
local OVERRIDE_MODULE = "MarketSense/Pricing/MS_LiquidPricing_Overrides_Data"
local definitions = {}
local primaryDefaults = {}
local primaryDefaultSources = {}
local defaultPricePerLiter = 5.0
local defaultPriceSource = "base"

local function normalize(value)
    local text = string.lower(tostring(value or ""))
    -- Fluid APIs may expose Base.Water or Base:Water; the data table uses the
    -- stable short fluid type because the item vessel is irrelevant here.
    local lastDot = nil
    for index = 1, #text do
        local char = string.sub(text, index, index)
        if char == "." or char == ":" then lastDot = index end
    end
    if lastDot then text = string.sub(text, lastDot + 1) end
    text = string.gsub(text, "[%s_%-]", "")
    return text
end

local function number(value, fallback)
    local parsed = tonumber(value)
    return parsed ~= nil and parsed or fallback
end

local function copyDefinition(definition, key, source)
    local result = Core.deepCopy(definition or {})
    result.key = result.key or key
    result.pricePerLiter = math.max(0, number(
        result.pricePerLiter or result.price_per_liter, defaultPricePerLiter
    ))
    result.source = result.source or source
    return result
end

function FluidPricing.register(fluidType, definition)
    local key = normalize(fluidType)
    if key == "" or type(definition) ~= "table" then return false end
    definitions[key] = copyDefinition(definition, tostring(fluidType), "registered")
    return true
end

local function loadData()
    definitions = {}
    primaryDefaults = {}
    primaryDefaultSources = {}
    defaultPricePerLiter = 5.0
    defaultPriceSource = "base"
    local ok, data = pcall(require, DATA_MODULE)
    if not ok or type(data) ~= "table" then return end
    defaultPricePerLiter = math.max(0, number(data.defaultPricePerLiter, 5.0))
    for key, definition in pairs(data.liquids or {}) do
        if type(definition) == "table" then
            definitions[normalize(key)] = copyDefinition(definition, tostring(key), "base")
        end
    end
    for key, value in pairs(data.primaryDefaults or {}) do
        primaryDefaults[tostring(key)] = math.max(0, number(value, defaultPricePerLiter))
    end

    -- User edits are kept in a separate optional data module.  This keeps
    -- shipped anchors upgrade-safe and makes the editor's scope explicit:
    -- only fluid content prices are changed here, never container/category
    -- sandbox values.
    local overrideOk, overrides = pcall(require, OVERRIDE_MODULE)
    if not overrideOk or type(overrides) ~= "table" then return end
    if overrides.defaultPricePerLiter ~= nil then
        defaultPricePerLiter = math.max(0, number(
            overrides.defaultPricePerLiter, defaultPricePerLiter
        ))
        defaultPriceSource = "override"
    end
    for key, override in pairs(overrides.liquids or {}) do
        local normalized = normalize(key)
        if normalized ~= "" then
            local existing = definitions[normalized] or {}
            local merged = Core.deepCopy(existing)
            if type(override) == "table" then
                for field, value in pairs(override) do merged[field] = value end
            elseif override ~= nil then
                merged.pricePerLiter = override
            end
            merged.source = "override"
            definitions[normalized] = copyDefinition(merged, tostring(key), "override")
        end
    end
    for key, override in pairs(overrides.primaryDefaults or {}) do
        local parsed = tonumber(override)
        if parsed ~= nil then
            primaryDefaults[tostring(key)] = math.max(0, parsed)
            primaryDefaultSources[tostring(key)] = "override"
        end
    end
end

local function configuredLiquidMap()
    local exported = Config and (Config.liquidPricing or Config.liquids)
    if type(exported) ~= "table" then return nil end
    return exported.liquids or exported
end

local function getDefinition(ctx, details)
    local configured = configuredLiquidMap()
    -- Do not use ipairs on a table whose first slot may be nil: Lua stops
    -- iteration at that hole and would silently skip the fluidType fallback.
    local candidates = {}
    if ctx.fluidTypeString ~= nil then candidates[#candidates + 1] = ctx.fluidTypeString end
    if ctx.fluidType ~= nil then candidates[#candidates + 1] = ctx.fluidType end
    for _, candidate in ipairs(candidates) do
        local key = normalize(candidate)
        if key ~= "" then
            local definition = configured and (configured[candidate] or configured[key])
            if type(definition) == "table" then
                return copyDefinition(definition, tostring(candidate), "config")
            end
            if definitions[key] then
                return Core.deepCopy(definitions[key])
            end
        end
    end

    local primary = details and details.primary or ""
    local familyPrice = primaryDefaults[primary]
    if familyPrice ~= nil then
        return {
            key = primary,
            primary = primary,
            pricePerLiter = familyPrice,
            source = primaryDefaultSources[primary] or "primary_default",
        }
    end
    return {
        key = "Unknown",
        primary = primary,
        pricePerLiter = defaultPricePerLiter,
        source = defaultPriceSource == "override" and "default_override" or "default",
    }
end

local function getVolume(ctx)
    local capacity = math.max(0, number(ctx.fluidCapacity, 0))
    local primary = math.max(0, number(ctx.fluidPrimaryAmount, 0))
    local amount = math.max(0, number(ctx.fluidAmount, 0))
    if primary > 0 then
        return capacity > 0 and math.min(primary, capacity) or primary, "primary_amount"
    end
    if amount > 0 then
        return capacity > 0 and math.min(amount, capacity) or amount, "total_amount"
    end
    local ratio = math.max(0, math.min(1, number(ctx.fluidFilledRatio, 0)))
    if capacity > 0 and ratio > 0 then
        return capacity * ratio, "filled_ratio"
    end
    return 0, "missing_volume"
end

function FluidPricing.getDefinition(ctx, details)
    return getDefinition(ctx or {}, details or {})
end

function FluidPricing.getVolume(ctx)
    return getVolume(ctx or {})
end

function FluidPricing.calculate(ctx, details)
    ctx = ctx or {}
    details = details or {}
    local definition = getDefinition(ctx, details)
    local volume, volumeSource = getVolume(ctx)
    local value = definition.pricePerLiter * volume
    local fluidType = ctx.fluidTypeString or ""
    if fluidType == "" then fluidType = ctx.fluidType or "" end
    details.priceHeuristic = {
        model = "liquid_content_per_liter_v1",
        fluidType = fluidType,
        pricingKey = definition.key,
        pricingSource = definition.source,
        pricePerLiter = definition.pricePerLiter,
        volume = volume,
        volumeSource = volumeSource,
        amount = number(ctx.fluidAmount, 0),
        capacity = number(ctx.fluidCapacity, 0),
        primaryAmount = number(ctx.fluidPrimaryAmount, 0),
        filledRatio = number(ctx.fluidFilledRatio, 0),
        mixture = ctx.fluidIsMixture == true,
        unit = "liter",
        vesselIndependent = true,
        contentValue = value,
    }
    return value
end

function FluidPricing.reload()
    -- Useful for an in-game debug/reload flow.  The ordinary game boot path
    -- calls this module once; the offline harness starts a fresh Lua process.
    loadData()
    return true
end

loadData()

return FluidPricing
