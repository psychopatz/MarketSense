-- MS_filter_Origin.lua
-- Applies an Origin descriptor tag identifying whether an item is from vanilla or a mod.

MarketSense = MarketSense or {}
MarketSense.Filters = MarketSense.Filters or {}
MarketSense.Filters.Origin = MarketSense.Filters.Origin or {}

local Filter = MarketSense.Filters.Origin

-- apply(ctx, result) — mutates result.tags in-place, returns result.
function Filter.apply(ctx, result)
    result = result or {}
    local tags = result.tags or {}

    -- Skip if Origin already assigned
    for _, t in ipairs(tags) do
        if string.sub(t, 1, 7) == "Origin." then return result end
    end

    if ctx.moduleName == "Base" then
        tags[#tags + 1] = "Origin.Vanilla"
    else
        local cleanId = tostring(ctx.sourceModId or ctx.moduleName or "Modded")
        cleanId = cleanId:gsub("[%s%.%-]", "")
        if cleanId == "Base" or cleanId == "Unknown" or cleanId == "" then
            cleanId = tostring(ctx.moduleName or "Modded"):gsub("[%s%.%-]", "")
        end
        if cleanId == "" then cleanId = "Modded" end
        tags[#tags + 1] = "Origin." .. cleanId
    end

    result.tags = tags
    return result
end

return Filter
