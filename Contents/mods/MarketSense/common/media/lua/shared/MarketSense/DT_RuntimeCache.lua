require "MarketSense/DT_Core"

DynamicTrading = DynamicTrading or {}
DynamicTrading.RuntimeCache = DynamicTrading.RuntimeCache or {
    prices = {},
    details = {},
    stock = {},
    tags = {},
    contexts = {},
    missing = {},
    built = false
}

local Cache = DynamicTrading.RuntimeCache
local Core = DynamicTrading.Core

function Cache.clear()
    Cache.prices = {}
    Cache.details = {}
    Cache.stock = {}
    Cache.tags = {}
    Cache.contexts = {}
    Cache.missing = {}
    Cache.built = false
end

function Cache.getDetails(fullType)
    return Cache.details[fullType]
end

function Cache.setDetails(fullType, details)
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
