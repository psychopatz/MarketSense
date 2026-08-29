-- ============================================================================
-- MARKET SENSE: REGISTRY HOOK
-- ============================================================================
-- Boots the MarketSense catalog from its persisted runtime cache.
-- Falls back to a rebuild only when the cache is missing or invalid.
-- ============================================================================

require "MarketSense/MS_PublicAPI"

Events.OnGameBoot.Add(function()
    if not MarketSense or type(MarketSense.EnsureRuntimeRegistryLoaded) ~= "function" then
        if MarketSense and type(MarketSense.Log) == "function" then
            MarketSense.Log("Error", "Init", "Missing MarketSense runtime registry loader.")
        end
        return
    end

    local ok, catalog = pcall(MarketSense.EnsureRuntimeRegistryLoaded, false)
    if not ok then
        if type(MarketSense.Log) == "function" then
            MarketSense.Log("Error", "Init", "Registry boot load failed: " .. tostring(catalog))
        end
        return
    end

    if type(MarketSense.Log) == "function" then
        local count = type(catalog) == "table" and tonumber(catalog.total) or 0
        MarketSense.Log("Info", "Init", "Loaded " .. tostring(count) .. " items into the MarketSense catalog.")
    end
end)
