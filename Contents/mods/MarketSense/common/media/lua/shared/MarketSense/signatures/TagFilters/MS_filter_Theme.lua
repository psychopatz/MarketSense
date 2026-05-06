-- MS_filter_Theme.lua
-- Applies an optional Theme descriptor tag based on item context heuristics.
-- Theme tags are optional — only added when a strong signal is present.

MarketSense = MarketSense or {}
MarketSense.Filters = MarketSense.Filters or {}
MarketSense.Filters.Theme = MarketSense.Filters.Theme or {}

local Filter = MarketSense.Filters.Theme

local THEME_RULES = {
    { tag = "Theme.Combat",    needles = { "tactical", "military", "combat", "assault", "swat", "riot" } },
    { tag = "Theme.Police",    needles = { "police", "officer", "sheriff", "deputy", "cop" } },
    { tag = "Theme.Militia",   needles = { "militia", "hunter", "camo", "camouflage", "ranger" } },
    { tag = "Theme.Survival",  needles = { "survival", "backpack", "camping", "hiking", "wilderness" } },
    { tag = "Theme.Winter",    needles = { "winter", "snow", "cold", "insulated", "thermal" } },
    { tag = "Theme.Industrial",needles = { "industrial", "construction", "worker", "hardhat", "workwear" } },
    { tag = "Theme.Primitive", needles = { "primitive", "stone", "flint", "crude", "improvised", "crafted" } },
}

local function ctxContainsAny(ctx, needles)
    local Core = MarketSense.Core
    return Core and Core.ctxContains(ctx, needles)
end

-- apply(ctx, result) — mutates result.tags in-place, returns result.
function Filter.apply(ctx, result)
    result = result or {}
    local tags = result.tags or {}

    -- Skip if Theme already assigned
    for _, t in ipairs(tags) do
        if string.sub(t, 1, 6) == "Theme." then return result end
    end

    for _, rule in ipairs(THEME_RULES) do
        if ctxContainsAny(ctx, rule.needles) then
            tags[#tags + 1] = rule.tag
            break
        end
    end

    result.tags = tags
    return result
end

return Filter
