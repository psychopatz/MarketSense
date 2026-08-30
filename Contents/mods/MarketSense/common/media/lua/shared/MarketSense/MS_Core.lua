require "MarketSense/MS_Config"

MarketSense = MarketSense or {}
MarketSense.Core = MarketSense.Core or {}

local Core = MarketSense.Core

local function unpackArgs(args)
    return unpack(args)
end

function Core.safeCall(obj, methodName, defaultValue, ...)
    if obj == nil or methodName == nil then
        return defaultValue
    end

    -- Keep optional, version-dependent metadata reads non-throwing. Known
    -- Project Zomboid collection APIs are handled directly below instead of
    -- probing them through this wrapper.
    local lookupOk, method = pcall(function()
        return obj[methodName]
    end)
    if not lookupOk then
        return defaultValue
    end
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
            if type(value) == "string" then
                local lower = string.lower(value)
                if lower == "false" or lower == "0" or lower == "no" then
                    return false
                end
                if lower == "true" or lower == "1" or lower == "yes" then
                    return true
                end
            end
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
        ctx and ctx.descriptionLower or "",
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

function Core.createTemporaryInstance(fullType)
    if type(fullType) ~= "string" or fullType == "" then return nil end
    local scriptItem = Core.findScriptItem(fullType)
    if not scriptItem then return nil end

    if type(instanceItem) ~= "function" then return nil end
    local ok, result = pcall(instanceItem, scriptItem)
    return ok and result or nil
end

function Core.releaseTemporaryInstance(instance)
    if instance and type(instance.Remove) == "function" then
        pcall(instance.Remove, instance)
    end
end

function Core.forEachCollection(collection, callback)
    if collection == nil or type(callback) ~= "function" then
        return
    end

    -- Lua fixtures and Kahlua tables are already directly iterable.  A
    -- fixture may also expose a Java-shaped toArray() method, so keep that
    -- compatibility path after the safe representations below.
    if type(collection) == "table" then
        local size = collection.size
        local get = collection.get
        if type(size) == "function" and type(get) == "function" then
            local count = tonumber(collection:size()) or 0
            for index = 0, count - 1 do
                local value = collection:get(index)
                if value ~= nil then callback(value, index + 1) end
            end
            return
        end
        local count = 0
        for index, value in ipairs(collection) do
            if value ~= nil then
                count = count + 1
                callback(value, index)
            end
        end
        if count > 0 then return end

        -- Some Kahlua Java Set proxies are represented as tables whose only
        -- reliable representation is their bracketed string form.  Do this
        -- before trying toArray(): a few Set implementations expose a
        -- zero-argument bridge that throws when invoked from Lua.
        local printed = tostring(collection)
        if string.sub(printed, 1, 1) == "["
            and string.sub(printed, -1) == "]" then
            local inner = string.sub(printed, 2, -2)
            local index = 0
            for value in string.gmatch(inner, "[^,%s]+") do
                index = index + 1
                callback(value, index)
            end
            return
        end

        local toArray = collection.toArray
        if type(toArray) == "function" then
            local array = collection:toArray()
            for index, value in ipairs(array) do
                if value ~= nil then callback(value, index) end
            end
        end
        return
    end

    -- ArrayList-like values are exposed by PZ with size()/get().  Use those
    -- methods directly; probing an unsupported method through pcall still
    -- causes the PZ debugger to stop on the underlying Java exception.
    local size = collection.size
    local get = collection.get
    if type(size) == "function" and type(get) == "function" then
        local count = tonumber(collection:size()) or 0
        for index = 0, count - 1 do
            local value = collection:get(index)
            if value ~= nil then callback(value, index + 1) end
        end
        return
    end

    -- Set-like values (notably Item.getTags()) may expose iterator() but not
    -- get() or a zero-argument toArray().
    local iteratorFactory = collection.iterator
    if type(iteratorFactory) == "function" then
        local iterator = collection:iterator()
        local hasNext = iterator and iterator.hasNext
        local nextValue = iterator and iterator.next
        if type(hasNext) == "function" and type(nextValue) == "function" then
            local index = 0
            while iterator:hasNext() do
                index = index + 1
                local value = iterator:next()
                if value ~= nil then callback(value, index) end
            end
            return
        end
    end

    -- Kahlua can expose a Java Set only through its stable string form (for
    -- example "[Beverage]") while leaving the zero-argument toArray bridge
    -- unusable.  This is sufficient for ItemTag/enum sets and, importantly,
    -- avoids calling a method that would stop the PZ debugger.
    local printed = tostring(collection)
    if string.sub(printed, 1, 1) == "["
        and string.sub(printed, -1) == "]" then
        local inner = string.sub(printed, 2, -2)
        local index = 0
        for value in string.gmatch(inner, "[^,%s]+") do
            index = index + 1
            callback(value, index)
        end
        return
    end

    -- Do not call toArray() on an opaque Java object here.  PZ's Java Set
    -- proxies can advertise that method but throw for the zero-argument Lua
    -- bridge; the safe size/get, iterator, and printed forms above cover the
    -- collections used by item and recipe metadata.
end

function Core.listFromJavaCollection(collection)
    local result = {}
    Core.forEachCollection(collection, function(value)
        result[#result + 1] = tostring(value)
    end)
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
    local config = MarketSense.ItemRuntimeConfig.pricing
    return Core.clamp(value, config.minPrice, config.maxPrice)
end

return Core
