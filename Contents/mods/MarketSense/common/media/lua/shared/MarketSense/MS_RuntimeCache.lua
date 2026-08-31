require "MarketSense/MS_Core"

MarketSense = MarketSense or {}
MarketSense.RuntimeCache = MarketSense.RuntimeCache or {
    prices = {},
    details = {},
    stock = {},
    tags = {},
    contexts = {},
    missing = {},
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
    Cache.built = false
    Cache.pricingRevision = currentPricingRevision()
end

function Cache.getDetails(fullType)
    Cache.ensureCurrent()
    local value = Cache.details[fullType]
    if value ~= nil then
        Cache.stats.detailHits = (Cache.stats.detailHits or 0) + 1
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
