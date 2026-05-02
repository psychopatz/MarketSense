local Utils = {}

function Utils.safeText(value, fallback)
    local text = tostring(value or "")
    if text == "" and fallback ~= nil then
        return tostring(fallback)
    end
    return text
end

function Utils.safeNumber(value, fallback)
    local number = tonumber(value)
    if number == nil then
        return fallback
    end
    return number
end

function Utils.joinLines(lines)
    return table.concat(lines or {}, " <LINE> ")
end

function Utils.toRichText(lines)
    return Utils.joinLines(lines or {})
end

function Utils.lower(value)
    return string.lower(tostring(value or ""))
end

return Utils
