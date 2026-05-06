require "MarketSense/MS_Debug"
require "MarketSense/MS_ItemsRegistry"

MarketSense  = MarketSense  or {}
DynamicTrading = DynamicTrading or {}

local PropReader   = MarketSense.PropertyReader
local Cache        = MarketSense.RuntimeCache
local StaticCatalog = MarketSense.StaticCatalog
local Pricing      = MarketSense.Pricing
local Stock        = MarketSense.Stock
local TagUtils     = MarketSense.TagUtils
local RuntimeRules = MarketSense.RuntimeRules

local function log(msg)
    if DynamicTrading.Log then DynamicTrading.Log(msg) end
end

-- ───────────────────────────────────────────────
-- Public API — all exposed under DynamicTrading.*
-- (this is the DT integration surface; keep names)
-- ───────────────────────────────────────────────

function DynamicTrading.GetPriceDetails(fullType, withAudit)
    local cached = Cache.getDetails(fullType)
    if cached then return cached end
    local details = Pricing.calculateDetails(fullType, withAudit)
    Cache.setDetails(fullType, details)
    return details
end

function DynamicTrading.GetPrice(fullType)
    return (DynamicTrading.GetPriceDetails(fullType) or {}).price or 0
end

function DynamicTrading.GetStockRange(fullType)
    return (DynamicTrading.GetPriceDetails(fullType) or {}).stock or { min = 0, max = 0 }
end

function DynamicTrading.GetTags(fullType)
    local details = DynamicTrading.GetPriceDetails(fullType) or {}
    return {
        primary      = details.primary,
        category     = details.category,
        tags         = details.tags,
        expandedTags = details.expandedTags,
    }
end

function DynamicTrading.RegenerateItemRegistry()
    if MarketSense.ItemsRegistry and MarketSense.ItemsRegistry.regenerate then
        return MarketSense.ItemsRegistry.regenerate()
    end
end

function DynamicTrading.EnsureRuntimeRegistryLoaded()
    if MarketSense.ItemsRegistry and MarketSense.ItemsRegistry.ensureLoaded then
        return MarketSense.ItemsRegistry.ensureLoaded()
    end
end

function DynamicTrading.ClearRuntimeCache()
    Cache.clear()
    log("[MarketSense] Runtime cache cleared.")
end

function DynamicTrading.GetRegistryDetails(fullType)
    if MarketSense.ItemsRegistry and MarketSense.ItemsRegistry.get then
        return MarketSense.ItemsRegistry.get(fullType)
    end
    return nil
end

function DynamicTrading.GetRuntimeRules()
    return RuntimeRules and RuntimeRules.getRules and RuntimeRules.getRules() or {}
end

function DynamicTrading.ApplyRuntimeRule(ruleTable)
    if RuntimeRules and RuntimeRules.apply then
        return RuntimeRules.apply(ruleTable)
    end
end

function DynamicTrading.GetAllKnownItems()
    if MarketSense.ItemsRegistry and MarketSense.ItemsRegistry.getAllKnown then
        return MarketSense.ItemsRegistry.getAllKnown()
    end
    return {}
end

function DynamicTrading.IsRuntimeDebugEnabled()
    return DynamicTrading.IsItemRuntimeDebugEnabled and DynamicTrading.IsItemRuntimeDebugEnabled() or false
end

return DynamicTrading
