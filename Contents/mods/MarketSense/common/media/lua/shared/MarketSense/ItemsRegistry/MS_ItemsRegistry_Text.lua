local Text = {}

function Text.trim(value)
    local text = tostring(value or "")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    return text
end

function Text.startsWith(text, prefix)
    text = tostring(text or "")
    prefix = tostring(prefix or "")
    return prefix ~= "" and string.sub(text, 1, #prefix) == prefix
end

function Text.split(text, delimiter)
    local result = {}
    local source = tostring(text or "")
    local token = ""
    delimiter = tostring(delimiter or "|")

    if delimiter == "" then
        if source ~= "" then
            result[1] = source
        end
        return result
    end

    local index = 1
    while index <= #source do
        local chunk = string.sub(source, index, index + #delimiter - 1)
        if chunk == delimiter then
            result[#result + 1] = token
            token = ""
            index = index + #delimiter
        else
            token = token .. string.sub(source, index, index)
            index = index + 1
        end
    end

    result[#result + 1] = token
    return result
end

function Text.join(list, delimiter)
    return table.concat(list or {}, delimiter or "|")
end

function Text.copyArray(source)
    local out = {}
    for _, value in ipairs(source or {}) do
        out[#out + 1] = value
    end
    return out
end

function Text.sanitizeOriginTag(origin)
    local text = Text.trim(origin)
    if text == "" or text == "Base" or text == "Vanilla" then
        return "Vanilla"
    end

    text = string.gsub(text, "[^%w_%-]", "")
    if text == "" then
        text = "Modded"
    end

    return text
end

function Text.stableHash(parts)
    local hash = 5381
    for _, part in ipairs(parts or {}) do
        local text = tostring(part or "")
        for index = 1, #text do
            hash = ((hash * 33) + string.byte(text, index)) % 4294967296
        end
        hash = ((hash * 33) + 124) % 4294967296
    end
    return string.format("%08x", hash)
end

function Text.quoteString(value)
    local text = tostring(value or "")
    text = string.gsub(text, "\\", "\\\\")
    text = string.gsub(text, "\"", "\\\"")
    return "\"" .. text .. "\""
end

function Text.jsonString(value)
    local text = tostring(value or "")
    text = string.gsub(text, "\\", "\\\\")
    text = string.gsub(text, "\"", "\\\"")
    text = string.gsub(text, "\r", "\\r")
    text = string.gsub(text, "\n", "\\n")
    return "\"" .. text .. "\""
end

function Text.sanitizePathPart(value, fallback)
    local text = Text.trim(value)
    if text == "" then
        return fallback or "General"
    end
    text = string.gsub(text, "[^%w_%-]", "")
    if text == "" then
        return fallback or "General"
    end
    return text
end

return Text
