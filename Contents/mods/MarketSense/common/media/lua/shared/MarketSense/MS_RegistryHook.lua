-- ============================================================================
-- MARKET SENSE: REGISTRY HOOK
-- ============================================================================
-- Populates the Dynamic Trading MasterList from the persisted DT_Items cache.
-- Falls back to a rebuild only when the cache is missing or invalid.
-- ============================================================================

require "MarketSense/MS_PublicAPI"

Events.OnGameBoot.Add(function()
    if not DynamicTrading or not DynamicTrading.EnsureRuntimeRegistryLoaded then
        if DynamicTrading and DynamicTrading.LogError then
            DynamicTrading.LogError("MarketSense", "Init", "RegistryHook", "Missing runtime registry loader for Registry Hook!")
        elseif DynamicTrading and DynamicTrading.Log then
            DynamicTrading.Log("MarketSense", "Init", "Error", "Missing runtime registry loader for Registry Hook!")
        end
        return
    end

    local ok, catalog = pcall(DynamicTrading.EnsureRuntimeRegistryLoaded, false)
    if not ok then
        local err = tostring(catalog)
        if DynamicTrading and DynamicTrading.LogError then
            DynamicTrading.LogError("MarketSense", "Init", "RegistryHook", "Registry boot load failed: " .. err)
        elseif DynamicTrading and DynamicTrading.Log then
            DynamicTrading.Log("MarketSense", "Init", "Error", "Registry boot load failed: " .. err)
        end
        return
    end

    local count = type(catalog) == "table" and tonumber(catalog.total) or 0

    if DynamicTrading and DynamicTrading.Log then
        DynamicTrading.Log("MarketSense", "Init", "RegistryHook", "Loaded " .. tostring(count) .. " live items into DynamicTrading MasterList.")
    end
end)
