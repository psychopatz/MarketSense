require "MarketSense/MS_Core"
require "MarketSense/signatures/tags/MS_TagMapper"

MarketSense = MarketSense or {}
MarketSense.TagUtils = MarketSense.TagUtils or {}

local TagUtils = MarketSense.TagUtils
local Mapping  = MarketSense.TagMapper

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

function TagUtils.categoryFromPrimary(token)
    local text = tostring(token or "")
    if text == "" then return "Misc" end
    return Mapping.categoryFromPrimary(text)
end

-- Expand a list of flat tokens + descriptor tags into a full hierarchy.
-- Flat tokens (no dots): expanded via TOKEN_PARENTS in TagMapper.
-- Descriptor tags (dots): kept as-is (Quality.Luxury, Rarity.Rare, etc.).
function TagUtils.expandHierarchy(tags)
    local expanded = {}
    local seen = {}
    local function add(v)
        if v ~= "" and not seen[v] then
            seen[v] = true
            expanded[#expanded + 1] = v
        end
    end
    for _, tag in ipairs(TagUtils.unique(tags)) do
        local text = tostring(tag)
        if string.find(text, "%.", 1, true) then
            -- Descriptor tag — keep as-is (no expansion)
            add(text)
        else
            -- Flat token — expand via TokenParents
            for _, derived in ipairs(Mapping.expandPrimary(text)) do
                add(derived)
            end
        end
    end
    return expanded
end

function TagUtils.hasTag(tags, tag)
    tag = tostring(tag or "")
    for _, entry in ipairs(tags or {}) do
        if entry == tag then return true end
    end
    return false
end

-- Returns true if any tag equals prefix OR is a child of prefix (flat token whose
-- expanded hierarchy contains prefix).
function TagUtils.tagStarts(tags, prefix)
    prefix = tostring(prefix or "")
    if prefix == "" then return false end
    for _, tag in ipairs(tags or {}) do
        if tag == prefix then return true end
        -- For dot-notation descriptors, check prefix match
        if string.find(tag, "%.", 1, true) then
            if string.sub(tag, 1, #prefix + 1) == (prefix .. ".") then return true end
        else
            -- For flat tokens, check expanded hierarchy
            local root = Mapping.categoryFromPrimary(tag)
            if root == prefix then return true end
            for _, parent in ipairs(Mapping.getParents(tag)) do
                if parent == prefix then return true end
            end
        end
    end
    return false
end

function TagUtils.normalizeResult(result)
    result = result or {}
    local tags = TagUtils.unique(result.tags or {})
    local primary = tostring(result.primary or tags[1] or "Misc")
    if not TagUtils.hasTag(tags, primary) then
        tags[#tags + 1] = primary
        tags = TagUtils.unique(tags)
    end
    local normalized = {
        matched      = result.matched == true,
        confidence   = tonumber(result.confidence) or 0,
        category     = tostring(result.category or TagUtils.categoryFromPrimary(primary) or "Misc"),
        primary      = primary,
        tags         = tags,
        expandedTags = result.expandedTags and TagUtils.unique(result.expandedTags)
                       or TagUtils.expandHierarchy(tags),
        details      = type(result.details) == "table" and result.details or {},
    }
    if normalized.category == "" then
        normalized.category = TagUtils.categoryFromPrimary(normalized.primary)
    end
    return normalized
end

return TagUtils
