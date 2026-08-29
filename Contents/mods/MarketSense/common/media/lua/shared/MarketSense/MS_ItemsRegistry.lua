require "MarketSense/MS_Config"
require "MarketSense/MS_Core"
require "MarketSense/MS_PropertyReader"
require "MarketSense/MS_AutoTag"
require "MarketSense/MS_Pricing"
require "MarketSense/MS_Stock"
require "MarketSense/MS_TagUtils"
require "MarketSense/MS_ItemAvailability"
require "MarketSense/signatures/tags/MS_TagMapper"

local Shared = require "MarketSense/ItemsRegistry/MS_ItemsRegistry_Shared"
require "MarketSense/ItemsRegistry/MS_ItemsRegistry_IO"
require "MarketSense/ItemsRegistry/MS_ItemsRegistry_Build"
local Runtime = require "MarketSense/ItemsRegistry/MS_ItemsRegistry_Runtime"

local Registry = Shared.Registry
MarketSense = MarketSense or {}
MarketSense.ItemsRegistry = Registry
local Availability = MarketSense.ItemAvailability

Registry.loadCatalogFromCache = Runtime.loadCatalogFromCache
Registry.rebuildCache = Runtime.rebuildCache
Registry.ensureLoaded = Runtime.ensureLoaded
Registry.regenerate = Runtime.rebuildCache

function Registry.getAvailability(fullType)
    if not Availability or type(Availability.get) ~= "function" then
        return nil
    end
    return Availability.get(fullType)
end

function Registry.isMarketEligible(fullType)
    return Availability and Availability.isEligible
        and Availability.isEligible(fullType) == true or false
end

function Registry.getAvailabilitySummary()
    if Availability and Availability.getSummary then
        return Availability.getSummary()
    end
    return {}
end

function Registry.get(fullType)
    if type(fullType) ~= "string" or fullType == "" then
        return nil
    end

    local masterList = DynamicTrading.Config and DynamicTrading.Config.MasterList
    if type(masterList) == "table" and type(masterList[fullType]) == "table" then
        return MarketSense.Core.deepCopy(masterList[fullType])
    end

    local catalog = Registry.state and Registry.state.catalog
    if type(catalog) == "table" and type(catalog.items) == "table" then
        return MarketSense.Core.deepCopy(catalog.items[fullType])
    end

    return nil
end

function Registry.getAllKnown()
    local catalog = Registry.state and Registry.state.catalog
    if type(catalog) == "table" and type(catalog.items) == "table" then
        return MarketSense.Core.deepCopy(catalog.items)
    end

    local masterList = DynamicTrading.Config and DynamicTrading.Config.MasterList
    if type(masterList) == "table" then
        return MarketSense.Core.deepCopy(masterList)
    end

    return {}
end

return Registry
