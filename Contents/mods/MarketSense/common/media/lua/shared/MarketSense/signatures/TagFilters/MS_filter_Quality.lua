-- MS_filter_Quality.lua
-- Applies a Quality descriptor tag based on item context heuristics.
-- Tag is dot-notation (Quality.*) — descriptor overlays, not primary taxonomy tokens.

MarketSense = MarketSense or {}
MarketSense.Filters = MarketSense.Filters or {}
MarketSense.Filters.Quality = MarketSense.Filters.Quality or {}

local Filter = MarketSense.Filters.Quality

local WASTE_NEEDLES  = { "broken", "trash", "junk", "worn", "rusty", "damaged", "dirty" }
local LUXURY_NEEDLES = { "gold", "diamond", "luxury", "premium", "whiskey", "wine", "pristine", "masterwork" }
local STERILE_NEEDLES = { "sterile", "medical", "surgical" }
local STERILE_EXCLUDE = { "unsterile", "used" }

local function ctxContainsAny(ctx, needles)
    local Core = MarketSense.Core
    return Core and Core.ctxContains(ctx, needles)
end

-- apply(ctx, result) — mutates result.tags in-place, returns result.
function Filter.apply(ctx, result)
    result = result or {}
    local tags = result.tags or {}

    -- Skip if Quality already assigned
    for _, t in ipairs(tags) do
        if string.sub(t, 1, 8) == "Quality." then return result end
    end

    if ctxContainsAny(ctx, WASTE_NEEDLES) then
        tags[#tags + 1] = "Quality.Waste"
    elseif ctxContainsAny(ctx, LUXURY_NEEDLES) then
        tags[#tags + 1] = "Quality.Luxury"
    elseif ctxContainsAny(ctx, STERILE_NEEDLES) and not ctxContainsAny(ctx, STERILE_EXCLUDE) then
        tags[#tags + 1] = "Quality.Sterile"
    else
        tags[#tags + 1] = "Quality.Standard"
    end

    result.tags = tags
    return result
end

return Filter
