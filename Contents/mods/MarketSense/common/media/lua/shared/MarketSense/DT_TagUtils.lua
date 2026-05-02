require "MarketSense/DT_Core"

DynamicTrading = DynamicTrading or {}
DynamicTrading.TagUtils = DynamicTrading.TagUtils or {}

local TagUtils = DynamicTrading.TagUtils

function TagUtils.unique(tags)
    local seen = {}
    local result = {}
    for _, tag in ipairs(tags or {}) do
        local text = tostring(tag or "")
        if text ~= "" and not seen[text] then
            seen[text] = true
            result[#result + 1] = text
        end
    end
    return result
end

function TagUtils.categoryFromPrimary(primary)
    local text = tostring(primary or "")
    local category = string.match(text, "^([^%.]+)")
    if not category or category == "" then
        return "Misc"
    end
    return category
end

function TagUtils.expandHierarchy(tags)
    local expanded = {}
    for _, tag in ipairs(TagUtils.unique(tags)) do
        local probe = tostring(tag)
        while probe and probe ~= "" do
            expanded[#expanded + 1] = probe
            probe = string.match(probe, "^(.*)%.")
        end
    end
    return TagUtils.unique(expanded)
end

function TagUtils.hasTag(tags, tag)
    tag = tostring(tag or "")
    for _, entry in ipairs(tags or {}) do
        if entry == tag then
            return true
        end
    end
    return false
end

function TagUtils.tagStarts(tags, prefix)
    prefix = tostring(prefix or "")
    if prefix == "" then
        return false
    end
    for _, tag in ipairs(tags or {}) do
        if tag == prefix or string.sub(tag, 1, #prefix + 1) == (prefix .. ".") then
            return true
        end
    end
    return false
end

function TagUtils.normalizeResult(result)
    result = result or {}

    local tags = TagUtils.unique(result.tags or {})
    local primary = tostring(result.primary or tags[1] or "Misc.General")
    if not TagUtils.hasTag(tags, primary) then
        tags[#tags + 1] = primary
        tags = TagUtils.unique(tags)
    end

    local normalized = {
        matched = result.matched == true,
        confidence = tonumber(result.confidence) or 0,
        category = tostring(result.category or TagUtils.categoryFromPrimary(primary) or "Misc"),
        primary = primary,
        tags = tags,
        expandedTags = result.expandedTags and TagUtils.unique(result.expandedTags) or TagUtils.expandHierarchy(tags),
        details = type(result.details) == "table" and result.details or {},
    }

    if normalized.category == "" then
        normalized.category = TagUtils.categoryFromPrimary(normalized.primary)
    end

    return normalized
end

return TagUtils
