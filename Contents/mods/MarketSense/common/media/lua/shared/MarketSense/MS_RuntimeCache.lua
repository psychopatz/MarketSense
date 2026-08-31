require "MarketSense/MS_Core"

MarketSense = MarketSense or {}
MarketSense.RuntimeCache = MarketSense.RuntimeCache or {
    prices = {},
    details = {},
    stock = {},
    tags = {},
    contexts = {},
    missing = {},
    detailOrder = {},
    detailStamps = {},
    detailClock = 0,
    detailLimit = 256,
    stats = {
        detailHits = 0,
        detailMisses = 0,
        evaluations = 0,
        failures = 0,
    },
    built = false,
    pricingRevision = 0,
}

local Cache = MarketSense.RuntimeCache
local Core = MarketSense.Core

local function touchDetail(fullType)
    Cache.detailClock = (Cache.detailClock or 0) + 1
    Cache.detailStamps = Cache.detailStamps or {}
    Cache.detailStamps[fullType] = Cache.detailClock
    local order = Cache.detailOrder or {}
    order[#order + 1] = { key = fullType, stamp = Cache.detailClock }
    Cache.detailOrder = order

    local limit = math.max(32, math.floor(tonumber(Cache.detailLimit) or 256))
    while #order > limit do
        local oldest = table.remove(order, 1)
        if oldest and Cache.details[oldest.key] ~= nil then
            if Cache.detailStamps[oldest.key] == oldest.stamp then
                Cache.details[oldest.key] = nil
                Cache.prices[oldest.key] = nil
                Cache.stock[oldest.key] = nil
                Cache.tags[oldest.key] = nil
                Cache.detailStamps[oldest.key] = nil
            end
        end
    end
end

Cache.stats = Cache.stats or {}
Cache.stats.detailHits = Cache.stats.detailHits or 0
Cache.stats.detailMisses = Cache.stats.detailMisses or 0
Cache.stats.evaluations = Cache.stats.evaluations or 0
Cache.stats.failures = Cache.stats.failures or 0

local function currentPricingRevision()
    local config = MarketSense.ItemRuntimeConfig
    return tonumber(config and config.pricingRevision) or 0
end

function Cache.ensureCurrent()
    local revision = currentPricingRevision()
    if Cache.pricingRevision ~= revision then
        Cache.clear()
    end
end

function Cache.clear()
    Cache.prices = {}
    Cache.details = {}
    Cache.stock = {}
    Cache.tags = {}
    Cache.contexts = {}
    Cache.missing = {}
    Cache.detailOrder = {}
    Cache.detailStamps = {}
    Cache.detailClock = 0
    Cache.built = false
    Cache.pricingRevision = currentPricingRevision()
end

function Cache.getDetails(fullType)
    Cache.ensureCurrent()
    local value = Cache.details[fullType]
    if value ~= nil then
        Cache.stats.detailHits = (Cache.stats.detailHits or 0) + 1
        touchDetail(fullType)
    else
        Cache.stats.detailMisses = (Cache.stats.detailMisses or 0) + 1
    end
    return value
end

function Cache.setDetails(fullType, details)
    Cache.ensureCurrent()
    if type(fullType) ~= "string" or type(details) ~= "table" then
        return nil
    end

    touchDetail(fullType)
    local stored = Core.deepCopy(details)
    Cache.details[fullType] = stored
    Cache.prices[fullType] = tonumber(stored.price) or 0
    Cache.stock[fullType] = Core.deepCopy(stored.stock or { min = 0, max = 0 })
    Cache.tags[fullType] = Core.deepCopy(stored.expandedTags or stored.tags or {})
    return stored
end

function Cache.recordEvaluation()
    Cache.ensureCurrent()
    Cache.stats.evaluations = (Cache.stats.evaluations or 0) + 1
end

function Cache.recordFailure()
    Cache.ensureCurrent()
    Cache.stats.failures = (Cache.stats.failures or 0) + 1
end

function Cache.getStats()
    Cache.ensureCurrent()
    local stats = Core.shallowCopy(Cache.stats or {})
    stats.contexts = 0
    stats.details = 0
    stats.detailLimit = math.max(32, math.floor(tonumber(Cache.detailLimit) or 256))
    stats.pending = 0
    for _ in pairs(Cache.contexts or {}) do stats.contexts = stats.contexts + 1 end
    for _ in pairs(Cache.details or {}) do stats.details = stats.details + 1 end
    stats.pricingRevision = Cache.pricingRevision
    return stats
end

function Cache.getContext(fullType)
    return Cache.contexts[fullType]
end

function Cache.setContext(fullType, context)
    if type(fullType) ~= "string" or type(context) ~= "table" then
        return nil
    end
    Cache.contexts[fullType] = Core.deepCopy(context)
    return Cache.contexts[fullType]
end

return Cache
