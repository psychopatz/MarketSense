-- ============================================================================
-- MARKET SENSE: REGISTRY HOOK
-- ============================================================================
-- Populates the Dynamic Trading MasterList from MarketSense's runtime catalog.
-- ============================================================================

Events.OnGameBoot.Add(function()
    if not DynamicTrading or not DynamicTrading.BuildRuntimeCatalog then
        if DynamicTrading and DynamicTrading.Log then
            DynamicTrading.Log("MarketSense", "Init", "Error", "Missing Core APIs for Registry Hook!")
        else
            print("[MarketSense] ERROR: Missing Core APIs for Registry Hook!")
        end
        return
    end

    local catalog = DynamicTrading.BuildRuntimeCatalog()
    
    -- Ensure tables exist
    DynamicTrading.Config = DynamicTrading.Config or {}
    DynamicTrading.Config.MasterList = {}
    
    local added = 0
    for fullType, details in pairs(catalog.items or {}) do
        -- Convert Market Sense output schemas to Dynamic Trading Registry schemas
        local priceNum = tonumber(details.price) or 10
        local stockData = type(details.stock) == "table" and details.stock or { min=0, max=5 }

        DynamicTrading.AddItem(fullType, {
            item = details.fullType,
            tags = details.expandedTags or details.tags or {},
            basePrice = priceNum,
            stockRange = stockData,
        })
        added = added + 1
    end
    
    if DynamicTrading.Log then
        DynamicTrading.Log("MarketSense", "Init", "Info", "Hooked " .. added .. " dynamic items into DynamicTrading MasterList.")
    else
        print("[MarketSense] Hooked " .. added .. " dynamic items into DynamicTrading Registry.")
    end
end)
