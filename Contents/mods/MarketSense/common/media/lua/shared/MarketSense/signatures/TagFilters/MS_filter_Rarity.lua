-- MS_filter_Rarity.lua
-- Applies rarity from explicit overrides first, then runtime loot evidence.
-- Name cues are only a low-confidence compatibility fallback for items that
-- have no distribution evidence (common for mod-specific scripted items).

require "MarketSense/MS_ItemAvailability"

MarketSense = MarketSense or {}
MarketSense.Filters = MarketSense.Filters or {}
MarketSense.Filters.Rarity = MarketSense.Filters.Rarity or {}

local Filter = MarketSense.Filters.Rarity
local Availability = MarketSense.ItemAvailability

local LEGENDARY_NEEDLES = { "legendary", "artifact", "unique", "rare_item" }
local RARE_NEEDLES      = { "katana", "machete", "generator", "military", "diamond", "gold", "hitech", "vintage" }
local UNCOMMON_NEEDLES  = { "pistol", "rifle", "shotgun", "revolver", "backpack", "radio", "walkie", "medical", "reinforced", "industrial" }

local FALLBACK_FIELDS = {
    { name = "fullType", key = "fullLower" },
    { name = "itemId", key = "idLower" },
    { name = "displayName", key = "displayNameLower" },
    { name = "itemType", key = "itemTypeLower" },
}

local function matchTerm(text, term)
    text = string.lower(tostring(text or ""))
    term = string.lower(tostring(term or ""))
    local start = string.find(text, term, 1, true)
    while start do
        local before = string.sub(text, start - 1, start - 1)
        if start == 1 or string.match(before, "[^a-z]") or #term >= 5 then
            return true
        end
        start = string.find(text, term, start + 1, true)
    end
    return false
end

local function ctxContainsAny(ctx, needles)
    for _, field in ipairs(FALLBACK_FIELDS) do
        local text = ctx and ctx[field.key] or ""
        for _, needle in ipairs(needles or {}) do
            if matchTerm(text, needle) then
                return true, field.name, needle
            end
        end
    end
    return false, nil, nil
end

local function hasRarityTag(tags)
    for _, tag in ipairs(tags or {}) do
        if string.sub(tostring(tag), 1, 7) == "Rarity." then
            return tostring(tag)
        end
    end
    return nil
end

local function setEvidence(result, evidence)
    result.details = result.details or {}
    result.details.rarityEvidence = evidence
end

local function explicitEvidence(tag)
    return {
        status = "explicit",
        rarity = string.sub(tag, 8),
        source = "explicit_tag",
        confidence = 1.0,
    }
end

local function lootEvidence(ctx)
    if not Availability or type(Availability.get) ~= "function" then return nil end
    return Availability.get(ctx and ctx.fullType)
end

-- apply(ctx, result) — mutates result.tags in-place, returns result.
function Filter.apply(ctx, result)
    result = result or {}
    local tags = result.tags or {}
    local explicit = hasRarityTag(tags)
    if explicit then
        setEvidence(result, explicitEvidence(explicit))
        result.tags = tags
        return result
    end

    local availability = lootEvidence(ctx)
    local loot = availability and availability.rarityEvidence or nil
    if loot and loot.status == "observed" and loot.rarity then
        tags[#tags + 1] = "Rarity." .. tostring(loot.rarity)
        setEvidence(result, {
            status = loot.status,
            rarity = loot.rarity,
            source = loot.source or availability.raritySource or "loot_distribution",
            confidence = tonumber(loot.confidence)
                or tonumber(availability.rarityConfidence) or 0,
            sourceCount = loot.sourceCount,
            entryCount = loot.entryCount,
            weightedEntryCount = loot.weightedEntryCount,
            weightSum = loot.weightSum,
            averageRelativeWeight = loot.averageRelativeWeight,
            references = loot.references or availability.references,
        })
        result.tags = tags
        return result
    end

    local matched, field, term = ctxContainsAny(ctx, LEGENDARY_NEEDLES)
    if matched then
        tags[#tags + 1] = "Rarity.Legendary"
        setEvidence(result, {
            status = "fallback",
            rarity = "Legendary",
            source = "name_fallback",
            confidence = 0.30,
            field = field,
            token = term,
        })
    else
        matched, field, term = ctxContainsAny(ctx, RARE_NEEDLES)
        if matched then
            tags[#tags + 1] = "Rarity.Rare"
            setEvidence(result, {
                status = "fallback",
                rarity = "Rare",
                source = "name_fallback",
                confidence = 0.26,
                field = field,
                token = term,
            })
        else
            matched, field, term = ctxContainsAny(ctx, UNCOMMON_NEEDLES)
            if matched then
                tags[#tags + 1] = "Rarity.Uncommon"
                setEvidence(result, {
                    status = "fallback",
                    rarity = "Uncommon",
                    source = "name_fallback",
                    confidence = 0.22,
                    field = field,
                    token = term,
                })
            else
                tags[#tags + 1] = "Rarity.Common"
                setEvidence(result, {
                    status = "not_detected",
                    rarity = "Common",
                    source = "fallback_default",
                    confidence = availability and 0.20 or 0.10,
                    reason = "no loot distribution entry was observed",
                })
            end
        end
    end

    result.tags = tags
    return result
end

return Filter
