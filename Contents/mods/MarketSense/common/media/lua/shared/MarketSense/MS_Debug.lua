require "MarketSense/MS_Pricing"
require "MarketSense/MS_ItemAvailability"

MarketSense = MarketSense or {}
MarketSense.DebugTools = MarketSense.DebugTools or {}

local Debug       = MarketSense.DebugTools
local Core        = MarketSense.Core
local PropReader  = MarketSense.PropertyReader
local Cache       = MarketSense.RuntimeCache
local Catalog     = MarketSense.StaticCatalog
local AutoTag     = MarketSense.AutoTag
local Pricing     = MarketSense.Pricing
local YieldResolver = MarketSense.YieldResolver
local Availability = MarketSense.ItemAvailability

local function descriptorValues(tags, prefix)
    local values = {}
    local marker = tostring(prefix or "") .. "."
    for _, tag in ipairs(tags or {}) do
        local text = tostring(tag or "")
        if string.sub(text, 1, #marker) == marker then
            values[#values + 1] = string.sub(text, #marker + 1)
        end
    end
    return values
end

local function safeLog(...)
    if MarketSense.IsItemRuntimeDebugEnabled and MarketSense.IsItemRuntimeDebugEnabled()
        and type(MarketSense.Log) == "function" then
        MarketSense.Log("Debug", "DebugTools", tostring((...) or ""))
    end
end

function Debug.inspectItem(fullType, withAudit)
    local ctx     = PropReader.buildContext(fullType)
    local details = Pricing.calculateDetails(ctx, withAudit ~= false)
    local availability = Availability and Availability.get and Availability.get(ctx.fullType) or nil
    local out = {
        fullType = ctx.fullType,
        category = details.category,
        primary  = details.primary,
        tags     = details.tags,
        expandedTags = details.expandedTags,
        themes = descriptorValues(details.expandedTags, "Theme"),
        descriptorEvidence = details.descriptorEvidence,
        descriptorRejected = details.descriptorRejected,
        rarityEvidence = details.rarityEvidence,
        price    = details.price,
        rawScore = details.rawScore,
        weaponEvidence = details.weaponEvidence,
        priceHeuristic = details.priceHeuristic,
        yieldResolution = details.yieldResolution,
        yieldResolverStats = YieldResolver and YieldResolver.getStats
            and YieldResolver.getStats() or nil,
        stock    = details.stock,
        source   = details.source,
        confidence = details.confidence,
        audit    = details.balanceAudit,
        availability = availability,
        marketEligible = availability and availability.status == "obtainable" or false,
        worldObjectEvidence = ctx.worldObjectEvidence,
        capabilities = ctx.capabilities,
        capabilityRequirements = ctx.capabilityRequirements,
        capabilityEvidence = ctx.capabilityEvidence,
    }
    safeLog("[MarketSense] DebugTools.inspectItem → " .. tostring(fullType))
    return out
end

function Debug.inspectCapabilities(fullType)
    local ctx = PropReader.buildContext(fullType)
    return {
        fullType = ctx.fullType,
        worldObjectEvidence = ctx.worldObjectEvidence,
        capabilities = ctx.capabilities,
        requirements = ctx.capabilityRequirements,
        evidence = ctx.capabilityEvidence,
    }
end

function Debug.scanAll(itemList, withAudit)
    local items = itemList or {}
    local results = {}
    for _, fullType in ipairs(items) do
        local ok, result = pcall(Debug.inspectItem, fullType, withAudit)
        results[fullType] = ok and result or { error = tostring(result) }
    end
    return results
end

function Debug.exportCatalog(catalog)
    local entries = catalog or Catalog or {}
    local out = {}
    for fullType, entry in pairs(entries) do
        out[#out + 1] = {
            fullType = fullType,
            category = entry.category,
            primary  = entry.primary,
            tags     = entry.tags,
            price    = entry.price,
            availability = entry.availability,
            marketEligible = entry.availability and entry.availability.status == "obtainable" or false,
            source   = "static_catalog",
        }
    end
    return out
end

function Debug.compareTagMethods(fullType)
    local ctx = PropReader.buildContext(fullType)
    local autoResult = AutoTag.generate(ctx)
    local staticEntry = Catalog and Catalog[fullType] or nil
    return {
        fullType = ctx.fullType,
        auto = autoResult,
        static = staticEntry,
        match = (autoResult and staticEntry
            and autoResult.primary == staticEntry.primary
            and autoResult.category == staticEntry.category) or false,
    }
end

function Debug.cacheStats()
    return Cache.getStats and Cache.getStats() or { note = "No stats available" }
end

MarketSense.DebugItem          = function(fullType, withAudit) return Debug.inspectItem(fullType, withAudit) end
MarketSense.DebugScanAll       = function(items, withAudit)   return Debug.scanAll(items, withAudit) end
MarketSense.ExportCatalogDebug = function(catalog)            return Debug.exportCatalog(catalog) end

return Debug
