require "MarketSense/MS_Debug"
require "MarketSense/MS_ItemsRegistry"
require "MarketSense/MS_RuntimeRules"
require "MarketSense/Pricing/MS_MarketModifiers"

MarketSense = MarketSense or {}

local PropReader   = MarketSense.PropertyReader
local Cache        = MarketSense.RuntimeCache
local StaticCatalog = MarketSense.StaticCatalog
local Pricing      = MarketSense.Pricing
local Stock        = MarketSense.Stock
local TagUtils     = MarketSense.TagUtils
local RuntimeRules = MarketSense.RuntimeRules
local MarketModifiers = MarketSense.MarketModifiers

local function invalidatePricingViews()
    Cache.clear()
    if MarketSense.ItemsRegistry and MarketSense.ItemsRegistry.state then
        MarketSense.ItemsRegistry.state.loaded = false
        MarketSense.ItemsRegistry.state.catalog = nil
        MarketSense.ItemsRegistry.state.knownSnapshot = nil
    end
end
local API           = MarketSense

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

local function getCachedPriceDetails(fullType, withAudit, source)
    if type(fullType) ~= "string" or fullType == "" then
        return nil
    end
    local cached = Cache.getDetails(fullType)
    if cached and (withAudit ~= true or type(cached.balanceAudit) == "table") then
        return cached
    end

    Cache.recordEvaluation()
    local details = Pricing.calculateDetails(source or fullType, withAudit)
    if type(details) ~= "table" then
        Cache.recordFailure()
        return nil
    end

    return Cache.setDetails(fullType, details)
end

function API.GetPriceDetails(fullType, withAudit)
    return getCachedPriceDetails(fullType, withAudit)
end

function API.GetPriceDetailsForContext(context, withAudit)
    if type(context) ~= "table" then return nil end
    return getCachedPriceDetails(context.fullType, withAudit, context)
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

function API.GetPriceForInstance(fullType, inventoryItem)
    local details = API.GetPriceDetailsForInstance(fullType, inventoryItem, false)
    return details and details.price or 0
end

function API.GetPrice(fullType, inventoryItem)
    if inventoryItem ~= nil then
        return API.GetPriceForInstance(fullType, inventoryItem)
    end
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
        themes       = descriptorValues(details.expandedTags, "Theme"),
        descriptorEvidence = details.descriptorEvidence,
        rarityEvidence = details.rarityEvidence,
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

-- Queue definition-level pricing requests across ticks. Project Zomboid Lua
-- is single-threaded, so this is cooperative batching rather than unsafe Lua
-- threads. Duplicate types in one or many queued requests share the cache.
local requestQueue = MarketSense._priceRequestQueue or {
    nextId = 0,
    requests = {},
    handler = nil,
}
MarketSense._priceRequestQueue = requestQueue

local function stopRequestQueue()
    if requestQueue.handler and Events and Events.OnTick
        and type(Events.OnTick.Remove) == "function" then
        Events.OnTick.Remove(requestQueue.handler)
    end
    requestQueue.handler = nil
end

local function processRequestQueue()
    local request = requestQueue.requests[1]
    if not request then
        stopRequestQueue()
        return
    end

    local processed = 0
    local startedAt = nil
    if type(getTimestampMs) == "function" then
        startedAt = tonumber(getTimestampMs())
    end
    while request.index <= #request.types and processed < 8 do
        local fullType = request.types[request.index]
        request.index = request.index + 1
        processed = processed + 1
        request.results[fullType] = API.GetPriceDetails(fullType, request.withAudit)
        if startedAt and type(getTimestampMs) == "function" then
            local now = tonumber(getTimestampMs())
            if now and now - startedAt >= 2 then break end
        end
    end

    if request.index <= #request.types then return end
    table.remove(requestQueue.requests, 1)
    request.done = true
    if type(request.callback) == "function" then
        -- Consumer callbacks are outside MarketSense; isolate them so one
        -- third-party handler cannot abort the request queue.
        pcall(request.callback, request.results, request)
    end
end

function API.RequestPriceDetails(fullTypes, callback, withAudit)
    if type(fullTypes) ~= "table" then return nil end

    local types = {}
    local seen = {}
    for _, fullType in ipairs(fullTypes) do
        if type(fullType) == "string" and fullType ~= "" and not seen[fullType] then
            seen[fullType] = true
            types[#types + 1] = fullType
        end
    end

    requestQueue.nextId = requestQueue.nextId + 1
    local request = {
        id = requestQueue.nextId,
        types = types,
        index = 1,
        results = {},
        callback = callback,
        withAudit = withAudit == true,
        done = false,
    }
    requestQueue.requests[#requestQueue.requests + 1] = request

    if not requestQueue.handler and Events and Events.OnTick
        and type(Events.OnTick.Add) == "function" then
        requestQueue.handler = processRequestQueue
        Events.OnTick.Add(requestQueue.handler)
    elseif not requestQueue.handler then
        while not request.done do processRequestQueue() end
    end
    return request
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

-- Extension hooks for other mods. These affect lazy pricing immediately and
-- invalidate materialized details so a registered special item cannot retain
-- an earlier price.
function API.RegisterMarketTagModifier(tag, rule)
    if not MarketModifiers or type(MarketModifiers.registerTag) ~= "function" then
        return nil
    end
    local result = MarketModifiers.registerTag(tag, rule)
    invalidatePricingViews()
    return result
end

function API.RegisterMarketCategoryModifier(category, rule)
    if not MarketModifiers or type(MarketModifiers.registerCategory) ~= "function" then
        return nil
    end
    local result = MarketModifiers.registerCategory(category, rule)
    invalidatePricingViews()
    return result
end

function API.RegisterMarketSubcategoryModifier(subcategory, rule)
    if not MarketModifiers or type(MarketModifiers.registerSubcategory) ~= "function" then
        return nil
    end
    local result = MarketModifiers.registerSubcategory(subcategory, rule)
    invalidatePricingViews()
    return result
end

function API.RegisterMarketItemModifier(fullType, rule)
    if not MarketModifiers or type(MarketModifiers.registerItem) ~= "function" then
        return nil
    end
    local result = MarketModifiers.registerItem(fullType, rule)
    invalidatePricingViews()
    return result
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
                MarketSense.ItemsRegistry.state.knownSnapshot = nil
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
