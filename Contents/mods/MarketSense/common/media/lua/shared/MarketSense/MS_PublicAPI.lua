require "MarketSense/MS_Debug"
require "MarketSense/MS_ItemsRegistry"
require "MarketSense/MS_RuntimeRules"

MarketSense = MarketSense or {}

local PropReader   = MarketSense.PropertyReader
local Cache        = MarketSense.RuntimeCache
local StaticCatalog = MarketSense.StaticCatalog
local Pricing      = MarketSense.Pricing
local Stock        = MarketSense.Stock
local TagUtils     = MarketSense.TagUtils
local RuntimeRules = MarketSense.RuntimeRules
local API           = MarketSense

-- Stable semantic interface for future consumers.  This returns the
-- world-object analysis without exposing or changing PZ's native item
-- category fields.
function MarketSense.GetItemCapabilities(fullType)
    local ctx = PropReader.buildContext(fullType)
    return {
        fullType = ctx.fullType,
        worldObjectEvidence = ctx.worldObjectEvidence,
        capabilities = ctx.capabilities,
        requirements = ctx.capabilityRequirements,
        evidence = ctx.capabilityEvidence,
    }
end

function API.GetPriceDetails(fullType, withAudit)
    if type(fullType) ~= "string" or fullType == "" then
        return nil
    end
    local cached = Cache.getDetails(fullType)
    if cached and (withAudit ~= true or type(cached.balanceAudit) == "table") then
        return cached
    end
    local details = Pricing.calculateDetails(fullType, withAudit)
    Cache.setDetails(fullType, details)
    return details
end

-- Evaluate a concrete InventoryItem without contaminating the definition
-- cache. Static catalog prices remain deterministic; this method applies
-- instance state such as current condition to the same Lua price model.
function API.GetPriceDetailsForInstance(fullType, inventoryItem, withAudit)
    if type(fullType) ~= "string" or fullType == "" or inventoryItem == nil then
        return nil
    end
    return Pricing.calculateDetails(fullType, withAudit == true, inventoryItem)
end

function API.GetPrice(fullType)
    return (API.GetPriceDetails(fullType) or {}).price or 0
end

function API.GetStockRange(fullType)
    return (API.GetPriceDetails(fullType) or {}).stock or { min = 0, max = 0 }
end

function API.GetTags(fullType)
    local details = API.GetPriceDetails(fullType) or {}
    return {
        primary      = details.primary,
        category     = details.category,
        tags         = details.tags,
        expandedTags = details.expandedTags,
        weaponEvidence = details.weaponEvidence,
    }
end

-- Expose recipe-yield evidence separately from price details so tooling can
-- inspect exact, heuristic, ambiguous, and unresolved bundle matches.
function API.GetYieldResolution(fullType)
    if type(fullType) ~= "string" or fullType == "" then
        return nil
    end
    local context = PropReader.buildContext(fullType)
    return MarketSense.YieldResolver and MarketSense.YieldResolver.resolve(context) or nil
end

function API.RegenerateItemRegistry()
    if MarketSense.ItemsRegistry and MarketSense.ItemsRegistry.regenerate then
        return MarketSense.ItemsRegistry.regenerate()
    end
end

function API.EnsureRuntimeRegistryLoaded(forceRebuild)
    if MarketSense.ItemsRegistry and MarketSense.ItemsRegistry.ensureLoaded then
        return MarketSense.ItemsRegistry.ensureLoaded(forceRebuild == true)
    end
end

function API.ClearRuntimeCache()
    Cache.clear()
end

function API.GetRegistryDetails(fullType)
    if MarketSense.ItemsRegistry and MarketSense.ItemsRegistry.get then
        return MarketSense.ItemsRegistry.get(fullType)
    end
    return nil
end

function API.GetRuntimeRules()
    return RuntimeRules and RuntimeRules.getRules and RuntimeRules.getRules() or {}
end

function API.ApplyRuntimeRule(ruleTable)
    if RuntimeRules and RuntimeRules.apply then
        local applied = RuntimeRules.apply(ruleTable)
        if applied then
            -- Runtime rules change both lazy details and the materialized
            -- registry. Drop both views so callers cannot observe stale data.
            Cache.clear()
            if MarketSense.ItemsRegistry and MarketSense.ItemsRegistry.state then
                MarketSense.ItemsRegistry.state.loaded = false
                MarketSense.ItemsRegistry.state.catalog = nil
            end
            if MarketSense.Config then
                MarketSense.Config.MasterList = {}
            end
        end
        return applied
    end
end

function API.GetAllKnownItems()
    if MarketSense.ItemsRegistry and MarketSense.ItemsRegistry.getAllKnown then
        return MarketSense.ItemsRegistry.getAllKnown()
    end
    return {}
end

function API.GetItemAvailability(fullType)
    if MarketSense.ItemsRegistry and MarketSense.ItemsRegistry.getAvailability then
        return MarketSense.ItemsRegistry.getAvailability(fullType)
    end
    return nil
end

function API.GetItemAvailabilitySummary()
    if MarketSense.ItemsRegistry and MarketSense.ItemsRegistry.getAvailabilitySummary then
        return MarketSense.ItemsRegistry.getAvailabilitySummary()
    end
    return {}
end

function API.IsRuntimeDebugEnabled()
    return API.IsItemRuntimeDebugEnabled and API.IsItemRuntimeDebugEnabled() or false
end

return API
