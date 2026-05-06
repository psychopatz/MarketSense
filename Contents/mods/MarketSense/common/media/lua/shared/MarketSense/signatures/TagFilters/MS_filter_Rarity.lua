-- MS_filter_Rarity.lua
-- Applies a Rarity descriptor tag based on item context heuristics.

MarketSense = MarketSense or {}
MarketSense.Filters = MarketSense.Filters or {}
MarketSense.Filters.Rarity = MarketSense.Filters.Rarity or {}

local Filter = MarketSense.Filters.Rarity

local LEGENDARY_NEEDLES = { "legendary", "artifact", "unique", "rare_item" }
local RARE_NEEDLES      = { "katana", "machete", "generator", "military", "diamond", "gold", "hitech", "vintage" }
local UNCOMMON_NEEDLES  = { "pistol", "rifle", "shotgun", "revolver", "backpack", "radio", "walkie", "medical", "reinforced", "industrial" }

local function ctxContainsAny(ctx, needles)
    local Core = MarketSense.Core
    return Core and Core.ctxContains(ctx, needles)
end

-- apply(ctx, result) — mutates result.tags in-place, returns result.
function Filter.apply(ctx, result)
    result = result or {}
    local tags = result.tags or {}

    -- Skip if Rarity already assigned
    for _, t in ipairs(tags) do
        if string.sub(t, 1, 7) == "Rarity." then return result end
    end

    if ctxContainsAny(ctx, LEGENDARY_NEEDLES) then
        tags[#tags + 1] = "Rarity.Legendary"
    elseif ctxContainsAny(ctx, RARE_NEEDLES) then
        tags[#tags + 1] = "Rarity.Rare"
    elseif ctxContainsAny(ctx, UNCOMMON_NEEDLES) then
        tags[#tags + 1] = "Rarity.Uncommon"
    else
        tags[#tags + 1] = "Rarity.Common"
    end

    result.tags = tags
    return result
end

return Filter
