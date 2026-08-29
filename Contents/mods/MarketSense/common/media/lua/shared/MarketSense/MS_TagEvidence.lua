-- Shared item-script tag matching.
--
-- PZ 42.20 commonly exposes tags as Base:<tag>, while workshop authors may
-- use their own namespace.  PropertyReader keeps both the raw tag list and a
-- punctuation-stripped lookup table, so signatures must compare the suffix
-- rather than assuming the Base namespace.

MarketSense = MarketSense or {}
MarketSense.TagEvidence = MarketSense.TagEvidence or {}

local TagEvidence = MarketSense.TagEvidence

local function normalize(value)
    local text = string.lower(tostring(value or ""))
    return string.gsub(text, "[^%w]", "")
end

local function tagSuffix(value)
    local text = string.lower(tostring(value or ""))
    return string.match(text, "([^:.]+)$") or text
end

function TagEvidence.has(ctx, token)
    if not ctx then
        return false
    end

    local wanted = normalize(token)
    if wanted == "" then
        return false
    end

    local normalizedTags = ctx.normalizedTags
    if normalizedTags and (normalizedTags[wanted] == true
        or normalizedTags["base" .. wanted] == true) then
        return true
    end

    -- The raw list preserves the namespace separator. This supports both
    -- Base:<tag> and arbitrary workshop forms such as MyMod:<tag> without
    -- treating a merely similar tag name as a match.
    for _, tag in ipairs(ctx.tags or {}) do
        if normalize(tagSuffix(tag)) == wanted then
            return true
        end
    end

    return false
end

-- Return the most specific matching token from a token -> value map. Lua's
-- pairs() order is intentionally unspecified; choosing by token length and a
-- lexical tie-break keeps multi-tag items stable across runs and cache builds.
function TagEvidence.best(ctx, mapping)
    local bestToken = nil
    local bestValue = nil
    for token, value in pairs(mapping or {}) do
        local normalized = normalize(token)
        if normalized ~= "" and TagEvidence.has(ctx, token)
            and (bestToken == nil
                or #normalized > #normalize(bestToken)
                or (#normalized == #normalize(bestToken) and tostring(token) < tostring(bestToken))) then
            bestToken = token
            bestValue = value
        end
    end
    return bestToken, bestValue
end

return TagEvidence
