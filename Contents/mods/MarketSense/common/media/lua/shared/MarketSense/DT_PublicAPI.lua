require "MarketSense/DT_Config"
require "MarketSense/DT_Core"
require "MarketSense/DT_RuntimeCache"
require "MarketSense/DT_PropertyReader"
require "MarketSense/DT_TagUtils"
require "MarketSense/DT_StaticCatalog"
require "MarketSense/DT_HeuristicsDB"
require "MarketSense/signatures/DT_Signature_Weapon"
require "MarketSense/signatures/DT_Signature_Fishing"
require "MarketSense/signatures/DT_Signature_Clothing"
require "MarketSense/signatures/DT_Signature_Food"
require "MarketSense/signatures/DT_Signature_Tool"
require "MarketSense/signatures/DT_Signature_Electronics"
require "MarketSense/signatures/DT_Signature_Medical"
require "MarketSense/signatures/DT_Signature_Container"
require "MarketSense/signatures/DT_Signature_Resource"
require "MarketSense/signatures/DT_Signature_Building"
require "MarketSense/DT_AutoTag"
require "MarketSense/DT_Stock"
require "MarketSense/DT_Pricing"
require "MarketSense/DT_Debug"

DynamicTrading = DynamicTrading or {}

local Core = DynamicTrading.Core
local Cache = DynamicTrading.RuntimeCache
local Config = DynamicTrading.ItemRuntimeConfig

local NO_RUNTIME_RULES = {
    loadFromFile = function() return false end,
    shouldSkip = function() return false end,
}

local function getRuntimeRules()
    local rules = DynamicTrading.RuntimeRules
    if type(rules) ~= "table" then
        return NO_RUNTIME_RULES
    end
    if type(rules.loadFromFile) ~= "function" then
        rules.loadFromFile = NO_RUNTIME_RULES.loadFromFile
    end
    if type(rules.shouldSkip) ~= "function" then
        rules.shouldSkip = NO_RUNTIME_RULES.shouldSkip
    end
    return rules
end

local function emptyCatalog()
    return {
        items = {},
        total = 0,
        modules = {},
        categories = {},
        tags = {},
    }
end

local function cloneWithSource(details, source)
    local copy = Core.deepCopy(details or {})
    copy.source = source or copy.source
    return copy
end

local function fallbackDetails(fullType)
    local ctx = DynamicTrading.PropertyReader.buildContext(fullType)
    local details = {
        fullType = ctx.fullType,
        moduleName = ctx.moduleName,
        typeName = ctx.typeName,
        sourceModId = ctx.sourceModId,
        sourceModName = ctx.sourceModName,
        category = "Misc",
        primary = "Misc.General",
        tags = { "Misc.General" },
        expandedTags = { "Misc.General", "Misc" },
        confidence = 0,
        rawScore = Config.pricing.minPrice,
        price = Config.pricing.minPrice,
        stock = { min = 0, max = 0 },
        source = "lazy",
    }
    return details
end

local function blacklistedDetails(fullType)
    local details = fallbackDetails(fullType)
    details.stock = { min = 0, max = 0 }
    details.source = "runtime-rules:blacklist"
    return details
end

function DynamicTrading.ClearRuntimeCache()
    Cache.clear()
end

function DynamicTrading.GetPriceDetails(fullType)
    if type(fullType) ~= "string" or fullType == "" then
        return {
            fullType = tostring(fullType or ""),
            category = "Misc",
            primary = "Misc.General",
            tags = { "Misc.General" },
            expandedTags = { "Misc.General", "Misc" },
            confidence = 0,
            rawScore = Config.pricing.minPrice,
            price = Config.pricing.minPrice,
            stock = { min = 0, max = 0 },
            source = "lazy",
        }
    end

    local runtimeRules = getRuntimeRules()
    runtimeRules.loadFromFile(false)
    if runtimeRules.shouldSkip(fullType) then
        return blacklistedDetails(fullType)
    end

    local cached = Cache.getDetails(fullType)
    if cached then
        return cloneWithSource(cached, "cache")
    end

    local staticDetails = DynamicTrading.StaticCatalog[fullType]
    if staticDetails then
        local resolved = DynamicTrading.Pricing.applyOverridesOnly(fullType, staticDetails)
        Cache.setDetails(fullType, resolved)
        return cloneWithSource(resolved, resolved.source or "static")
    end

    if not Config.server.allowLazyGeneration then
        return cloneWithSource(fallbackDetails(fullType), "lazy")
    end

    local generated = DynamicTrading.Pricing.generateDetailsOnce(fullType)
    if Config.server.cacheLazyItems ~= false then
        Cache.setDetails(fullType, generated)
        Cache.missing[fullType] = true
    end
    return cloneWithSource(generated, generated.source or "lazy")
end

function DynamicTrading.GetPrice(fullType)
    local details = DynamicTrading.GetPriceDetails(fullType)
    return tonumber(details.price) or Config.pricing.minPrice
end

function DynamicTrading.GetStockRange(fullType)
    local details = DynamicTrading.GetPriceDetails(fullType)
    return Core.deepCopy(details.stock or { min = 0, max = 0 })
end

function DynamicTrading.GetTags(fullType)
    local details = DynamicTrading.GetPriceDetails(fullType)
    return Core.deepCopy(details.tags or {})
end

function DynamicTrading.BuildRuntimeCatalog()
    local runtimeRules = getRuntimeRules()
    runtimeRules.loadFromFile(false)
    local result = emptyCatalog()
    local ok, allItems = pcall(function()
        return getAllItems and getAllItems() or nil
    end)

    if not ok or allItems == nil then
        return result
    end

    for index = 0, allItems:size() - 1 do
        local scriptItem = allItems:get(index)
        local ctx = DynamicTrading.PropertyReader.buildContext(scriptItem)
        if ctx and ctx.fullType ~= "" and not runtimeRules.shouldSkip(ctx.fullType) then
            local details = DynamicTrading.Pricing.generateDetailsOnce(ctx)
            Cache.setDetails(ctx.fullType, details)

            result.items[ctx.fullType] = {
                fullType = details.fullType,
                moduleName = details.moduleName,
                typeName = details.typeName,
                sourceModId = details.sourceModId,
                sourceModName = details.sourceModName,
                category = details.category,
                primary = details.primary,
                tags = Core.deepCopy(details.tags),
                expandedTags = Core.deepCopy(details.expandedTags),
                price = details.price,
                rawScore = details.rawScore,
                confidence = details.confidence,
                stock = Core.deepCopy(details.stock),
            }

            result.total = result.total + 1
            result.modules[ctx.moduleName] = (result.modules[ctx.moduleName] or 0) + 1
            result.categories[details.category] = (result.categories[details.category] or 0) + 1
            for _, tag in ipairs(details.tags or {}) do
                result.tags[tag] = (result.tags[tag] or 0) + 1
            end
        end
    end

    Cache.built = true
    return result
end

function DynamicTrading.AdminRebuildCatalog()
    DynamicTrading.ClearRuntimeCache()
    return DynamicTrading.BuildRuntimeCatalog()
end

function DynamicTrading.ReloadRuntimeRules()
    local runtimeRules = getRuntimeRules()
    runtimeRules.loadFromFile(true)
    DynamicTrading.ClearRuntimeCache()
end

function DynamicTrading.ReloadRuntimeRegistry()
    if not DynamicTrading.ItemsRegistry then
        pcall(require, "MarketSense/MS_ItemsRegistry")
    end
    
    if DynamicTrading.ItemsRegistry and DynamicTrading.ItemsRegistry.load then
        DynamicTrading.ItemsRegistry.load()
        DynamicTrading.ClearRuntimeCache()
        return true
    end
    return false
end

function DynamicTrading.GetRuntimeCatalog()
    if not Cache.built then
        return nil
    end

    local result = emptyCatalog()
    for fullType, details in pairs(Cache.details) do
        result.items[fullType] = Core.deepCopy(details)
        result.total = result.total + 1
        result.modules[details.moduleName or "Unknown"] = (result.modules[details.moduleName or "Unknown"] or 0) + 1
        result.categories[details.category or "Misc"] = (result.categories[details.category or "Misc"] or 0) + 1
        for _, tag in ipairs(details.tags or {}) do
            result.tags[tag] = (result.tags[tag] or 0) + 1
        end
    end
    return result
end

return DynamicTrading
