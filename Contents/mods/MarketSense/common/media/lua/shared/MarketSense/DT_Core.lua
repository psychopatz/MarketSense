require "MarketSense/DT_Config"

DynamicTrading = DynamicTrading or {}
DynamicTrading.Core = DynamicTrading.Core or {}

local Core = DynamicTrading.Core

local function unpackArgs(args)
    if table.unpack then
        return table.unpack(args)
    end
    return unpack(args)
end

function Core.safeCall(obj, methodName, defaultValue, ...)
    if obj == nil or methodName == nil then
        return defaultValue
    end

    local method = obj[methodName]
    if type(method) ~= "function" then
        return defaultValue
    end

    local ok, result = pcall(method, obj, ...)
    if ok and result ~= nil then
        return result
    end

    return defaultValue
end

local function normalizeMethodNames(methodNames)
    if type(methodNames) == "table" then
        return methodNames
    end
    return { methodNames }
end

function Core.safeNumber(obj, methodNames, defaultValue, ...)
    local args = { ... }
    for _, methodName in ipairs(normalizeMethodNames(methodNames)) do
        local value = Core.safeCall(obj, methodName, nil, unpackArgs(args))
        value = tonumber(value)
        if value ~= nil then
            return value
        end
    end
    return tonumber(defaultValue) or 0
end

function Core.safeString(obj, methodNames, defaultValue, ...)
    local args = { ... }
    for _, methodName in ipairs(normalizeMethodNames(methodNames)) do
        local value = Core.safeCall(obj, methodName, nil, unpackArgs(args))
        if value ~= nil then
            local text = tostring(value)
            if text ~= "" then
                return text
            end
        end
    end
    return tostring(defaultValue or "")
end

function Core.safeBoolean(obj, methodNames, defaultValue, ...)
    local args = { ... }
    for _, methodName in ipairs(normalizeMethodNames(methodNames)) do
        local value = Core.safeCall(obj, methodName, nil, unpackArgs(args))
        if value ~= nil then
            return not not value
        end
    end
    return not not defaultValue
end

function Core.shallowCopy(source)
    local copy = {}
    for key, value in pairs(source or {}) do
        copy[key] = value
    end
    return copy
end

function Core.deepCopy(value, seen)
    if type(value) ~= "table" then
        return value
    end

    seen = seen or {}
    if seen[value] then
        return seen[value]
    end

    local copy = {}
    seen[value] = copy

    for key, innerValue in pairs(value) do
        copy[Core.deepCopy(key, seen)] = Core.deepCopy(innerValue, seen)
    end

    return copy
end

function Core.splitFullType(fullType)
    local text = tostring(fullType or "")
    local moduleName, typeName = string.match(text, "^([^%.]+)%.(.+)$")
    if not moduleName or not typeName then
        return "Unknown", text
    end
    return moduleName, typeName
end

function Core.clamp(value, minValue, maxValue)
    local number = tonumber(value) or 0
    if minValue ~= nil and number < minValue then
        number = minValue
    end
    if maxValue ~= nil and number > maxValue then
        number = maxValue
    end
    return number
end

function Core.round(value)
    local number = tonumber(value) or 0
    if number >= 0 then
        return math.floor(number + 0.5)
    end
    return math.ceil(number - 0.5)
end

function Core.lower(value)
    return string.lower(tostring(value or ""))
end

function Core.startsWith(text, prefix)
    text = tostring(text or "")
    prefix = tostring(prefix or "")
    return prefix ~= "" and string.sub(text, 1, #prefix) == prefix
end

function Core.contains(text, needle)
    text = Core.lower(text)
    needle = Core.lower(needle)
    return needle ~= "" and string.find(text, needle, 1, true) ~= nil
end

function Core.containsAny(text, needles)
    for _, needle in ipairs(needles or {}) do
        if Core.contains(text, needle) then
            return true, needle
        end
    end
    return false, nil
end

function Core.ctxContains(ctx, needles)
    local fields = {
        ctx and ctx.fullLower or "",
        ctx and ctx.idLower or "",
        ctx and ctx.displayCategoryLower or "",
        ctx and ctx.itemTypeLower or "",
        ctx and ctx.bodyLocationLower or "",
        ctx and ctx.ammoTypeLower or "",
        ctx and ctx.displayNameLower or "",
    }

    for _, field in ipairs(fields) do
        local matched, token = Core.containsAny(field, needles)
        if matched then
            return true, token
        end
    end

    for _, tag in ipairs(ctx and ctx.tags or {}) do
        local matched, token = Core.containsAny(tag, needles)
        if matched then
            return true, token
        end
    end

    return false, nil
end

function Core.findScriptItem(fullType)
    if type(fullType) ~= "string" or fullType == "" then
        return nil
    end

    local manager = nil
    if getScriptManager then
        local ok, result = pcall(getScriptManager)
        if ok then
            manager = result
        end
    end

    if not manager and ScriptManager and ScriptManager.instance then
        manager = ScriptManager.instance
    end

    if not manager then
        return nil
    end

    local item = Core.safeCall(manager, "FindItem", nil, fullType)
    if item then
        return item
    end

    item = Core.safeCall(manager, "getItem", nil, fullType)
    if item then
        return item
    end

    return nil
end

function Core.listFromJavaCollection(collection)
    local result = {}
    if collection == nil then
        return result
    end

    local size = Core.safeNumber(collection, "size", 0)
    if size > 0 and collection.get then
        for index = 0, size - 1 do
            local ok, value = pcall(collection.get, collection, index)
            if ok and value ~= nil then
                result[#result + 1] = tostring(value)
            end
        end
        return result
    end

    if type(collection) == "table" then
        for _, value in ipairs(collection) do
            result[#result + 1] = tostring(value)
        end
    end

    return result
end

function Core.safeTags(item)
    local tags = {}
    local collection = Core.safeCall(item, "getTags", nil)
    for _, tag in ipairs(Core.listFromJavaCollection(collection)) do
        tags[#tags + 1] = tag
    end
    return tags
end

function Core.priceClamp(value)
    local config = DynamicTrading.ItemRuntimeConfig.pricing
    return Core.clamp(value, config.minPrice, config.maxPrice)
end

return Core
