require "MarketSense/MS_Pricing"

MarketSense = MarketSense or {}
MarketSense.DebugTools = MarketSense.DebugTools or {}

local Debug       = MarketSense.DebugTools
local Core        = MarketSense.Core
local PropReader  = MarketSense.PropertyReader
local Cache       = MarketSense.RuntimeCache
local Catalog     = MarketSense.StaticCatalog
local AutoTag     = MarketSense.AutoTag
local Pricing     = MarketSense.Pricing

local function safeLog(...)
    if DynamicTrading and DynamicTrading.Log then
        DynamicTrading.Log(...)
    end
end

function Debug.inspectItem(fullType, withAudit)
    local ctx     = PropReader.buildContext(fullType)
    local details = Pricing.calculateDetails(ctx, withAudit ~= false)
    local out = {
        fullType = ctx.fullType,
        category = details.category,
        primary  = details.primary,
        tags     = details.tags,
        expandedTags = details.expandedTags,
        price    = details.price,
        rawScore = details.rawScore,
        stock    = details.stock,
        source   = details.source,
        confidence = details.confidence,
        audit    = details.balanceAudit,
    }
    safeLog("[MarketSense] DebugTools.inspectItem → " .. tostring(fullType))
    return out
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

-- DynamicTrading-namespace debug wrappers (expected by DT debug panel and console helpers)
DynamicTrading = DynamicTrading or {}
DynamicTrading.DebugItem         = function(fullType, withAudit) return Debug.inspectItem(fullType, withAudit) end
DynamicTrading.DebugScanAll      = function(items, withAudit)   return Debug.scanAll(items, withAudit) end
DynamicTrading.ExportCatalogDebug = function(catalog)           return Debug.exportCatalog(catalog) end

return Debug
