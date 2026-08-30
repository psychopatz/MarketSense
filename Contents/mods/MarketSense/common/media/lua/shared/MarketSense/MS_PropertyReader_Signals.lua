require "MarketSense/MS_Core"

local Core = MarketSense.Core
local Signals = {}

local function positiveMagnitude(value)
    return math.abs(tonumber(value) or 0)
end

local function normalizeToken(value)
    local text = Core.lower(value)
    text = string.gsub(text, "[^%w]", "")
    return text
end

local function readNumber(obj, methodNames)
    if obj == nil or methodNames == nil then
        return nil
    end

    local methods = type(methodNames) == "table" and methodNames or { methodNames }
    for _, methodName in ipairs(methods) do
        local value = Core.safeCall(obj, methodName, nil)
        value = tonumber(value)
        if value ~= nil then
            return value
        end
    end
    return nil
end

local function preferNumber(primaryObj, fallbackObj, methodNames, defaultValue)
    local value = readNumber(primaryObj, methodNames)
    if value ~= nil then
        return value
    end

    value = readNumber(fallbackObj, methodNames)
    if value ~= nil then
        return value
    end

    return tonumber(defaultValue) or 0
end

local function optionalNumber(primaryObj, fallbackObj, methodNames)
    local value = readNumber(primaryObj, methodNames)
    if value ~= nil then
        return value
    end
    return readNumber(fallbackObj, methodNames)
end

local function preferString(primaryObj, fallbackObj, methodNames, defaultValue)
    local value = Core.safeString(primaryObj, methodNames, "")
    if value ~= "" then
        return value
    end
    return Core.safeString(fallbackObj, methodNames, defaultValue or "")
end

-- InventoryItem:getReplaceOnUseOnString() assumes its backing value is not
-- nil and calls String.split() directly.  Probe the nullable raw value first
-- so ordinary items do not turn an optional metadata read into a Java error.
local function readReplaceOnUseOn(obj)
    local rawValue = Core.safeString(obj, "getReplaceOnUseOn", "")
    if rawValue == "" then
        return ""
    end
    return Core.safeString(obj, "getReplaceOnUseOnString", rawValue)
end

local function preferReplaceOnUseOn(primaryObj, fallbackObj)
    local value = readReplaceOnUseOn(primaryObj)
    if value ~= "" then
        return value
    end
    return readReplaceOnUseOn(fallbackObj)
end

local function isSentinelSpoilage(value)
    return (tonumber(value) or 0) >= 365000
end

local function readFluidCategories(fluid)
    local categories = {}
    if fluid == nil or FluidCategory == nil then
        return categories
    end

    -- Fluid:getCategories() returns a Guava ImmutableSet. Kahlua cannot
    -- safely enumerate that implementation, while the public PZ API gives
    -- us a stable category list and the supported isCategory predicate.
    local categoryList = FluidCategory.getList()
    for index = 0, categoryList:size() - 1 do
        local category = categoryList:get(index)
        if fluid:isCategory(category) then
            categories[#categories + 1] = tostring(category)
        end
    end
    return categories
end


return {
    positiveMagnitude = positiveMagnitude,
    normalizeToken = normalizeToken,
    readNumber = readNumber,
    preferNumber = preferNumber,
    optionalNumber = optionalNumber,
    preferString = preferString,
    preferReplaceOnUseOn = preferReplaceOnUseOn,
    isSentinelSpoilage = isSentinelSpoilage,
    readFluidCategories = readFluidCategories,
}
