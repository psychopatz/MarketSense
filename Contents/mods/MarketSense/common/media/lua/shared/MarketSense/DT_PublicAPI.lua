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
require "MarketSense/DT_Stock"
require "MarketSense/DT_Debug"
require "MarketSense/MS_RuntimeRules"
require "MarketSense/MS_ItemsRegistry"
require "MarketSense/MS_RegistryHook"

DynamicTrading = DynamicTrading or {}

local Core = DynamicTrading.Core
local TagUtils = DynamicTrading.TagUtils
local Cache = DynamicTrading.RuntimeCache
local Registry = DynamicTrading.ItemsRegistry
local Config = DynamicTrading.ItemRuntimeConfig
local DESCRIPTOR_ROOTS = {
    Origin = true,
    Quality = true,
    Rarity = true,
    Theme = true,
}

local function getRuntimeRules()
    local rules = DynamicTrading.RuntimeRules
    if type(rules) ~= "table" then
        return nil
    end
    if type(rules.loadFromFile) == "function" then
        rules.loadFromFile(false)
    end
    return rules
end

local function buildFallbackDetails(fullType)
    local ctx = DynamicTrading.PropertyReader.buildContext(fullType)
    return {
        fullType = ctx.fullType,
        moduleName = ctx.moduleName,
        typeName = ctx.typeName,
        sourceModId = ctx.sourceModId,
        sourceModName = ctx.sourceModName,
        category = "Misc",
        primary = "Misc.General",
        tags = { "Misc.General" },
        expandedTags = { "Misc.General", "Misc" },
        basePrice = Config.pricing.minPrice,
        price = Config.pricing.minPrice,
        rawScore = Config.pricing.minPrice,
        confidence = 0,
        stock = { min = 0, max = 0 },
        source = "fallback",
    }
end

local function getPrimaryTag(tags)
    for _, tag in ipairs(tags or {}) do
        local root = string.match(tostring(tag), "^([^%.]+)")
        if root and not DESCRIPTOR_ROOTS[root] then
            return tag
        end
    end
    return tostring(tags and tags[1] or "Misc.General")
end

local function buildDetailsFromMasterList(fullType, itemData)
    local ctx = DynamicTrading.PropertyReader.buildContext(fullType)
    local tags = TagUtils.unique(itemData and itemData.tags or { "Misc.General" })
    local primary = getPrimaryTag(tags)
    local category = TagUtils.categoryFromPrimary(primary)

    local price = tonumber(itemData and itemData.basePrice) or Config.pricing.minPrice
    if DynamicTrading.PriceConfig and DynamicTrading.PriceConfig.GetEffectiveBasePrice then
        price = DynamicTrading.PriceConfig.GetEffectiveBasePrice(fullType, itemData)
    end

    local stock = itemData and itemData.stockRange or { min = 0, max = 0 }
    if DynamicTrading.Stock and DynamicTrading.Stock.calculate then
        stock = DynamicTrading.Stock.calculate(fullType, ctx, {
            category = category,
            primary = primary,
            tags = tags,
            expandedTags = TagUtils.expandHierarchy(tags),
        })
    end

    return {
        fullType = ctx.fullType,
        moduleName = ctx.moduleName,
        typeName = ctx.typeName,
        sourceModId = ctx.sourceModId,
        sourceModName = ctx.sourceModName,
        category = category,
        primary = primary,
        tags = tags,
        expandedTags = TagUtils.expandHierarchy(tags),
        basePrice = tonumber(itemData and itemData.basePrice) or Config.pricing.minPrice,
        price = tonumber(price) or Config.pricing.minPrice,
        rawScore = tonumber(itemData and itemData.basePrice) or Config.pricing.minPrice,
        confidence = 1,
        stock = {
            min = math.max(0, tonumber(stock and stock.min) or 0),
            max = math.max(0, tonumber(stock and stock.max) or 0),
        },
        source = "registry",
    }
end

function DynamicTrading.ClearRuntimeCache()
    Cache.clear()
    if Registry and Registry.state then
        Registry.state.loaded = false
        Registry.state.catalog = nil
        Registry.state.activeModsHash = nil
        Registry.state.lastIndex = nil
    end
end

function DynamicTrading.RegenerateItemRegistry(reason)
    local why = tostring(reason or "manual")
    if DynamicTrading.Log then
        DynamicTrading.Log("MarketSense", "Registry", "Info", "Manual DT_Items cache rebuild requested (" .. why .. ").")
    end
    DynamicTrading.ClearRuntimeCache()
    return DynamicTrading.EnsureRuntimeRegistryLoaded(true)
end

function DynamicTrading.RequestRegenerateItemRegistry(reason)
    if isClient() and not isServer() then
        local player = getPlayer and getPlayer() or (getSpecificPlayer and getSpecificPlayer(0)) or nil
        if player then
            sendClientCommand(player, "DynamicTrading", "RegenerateItemRegistry", {
                reason = tostring(reason or "manual"),
            })
            return nil, "requested"
        end
        return nil, "missing_player"
    end

    return DynamicTrading.RegenerateItemRegistry(reason or "manual")
end

function DynamicTrading.EnsureRuntimeRegistryLoaded(forceRebuild)
    if Registry and Registry.ensureLoaded then
        return Registry.ensureLoaded(forceRebuild == true)
    end
    return {
        items = {},
        total = 0,
        modules = {},
        categories = {},
        tags = {},
    }
end

function DynamicTrading.GetPriceDetails(fullType)
    if type(fullType) ~= "string" or fullType == "" then
        return buildFallbackDetails(fullType)
    end

    DynamicTrading.EnsureRuntimeRegistryLoaded(false)

    local rules = getRuntimeRules()
    if rules and rules.shouldSkip and rules.shouldSkip(fullType) then
        local skipped = buildFallbackDetails(fullType)
        skipped.source = "runtime-rules:blacklist"
        return skipped
    end

    local masterList = DynamicTrading.Config and DynamicTrading.Config.MasterList or {}
    local itemData = masterList[fullType]
    if itemData then
        return buildDetailsFromMasterList(fullType, itemData)
    end

    local staticDetails = DynamicTrading.StaticCatalog and DynamicTrading.StaticCatalog[fullType] or nil
    if type(staticDetails) == "table" then
        local moduleName, typeName = Core.splitFullType(fullType)
        return {
            fullType = staticDetails.fullType or fullType,
            moduleName = staticDetails.moduleName or moduleName,
            typeName = staticDetails.typeName or typeName,
            sourceModId = staticDetails.sourceModId or "StaticCatalog",
            sourceModName = staticDetails.sourceModName or "Static Catalog",
            category = staticDetails.category or "Misc",
            primary = staticDetails.primary or "Misc.General",
            tags = TagUtils.unique(staticDetails.tags or { staticDetails.primary or "Misc.General" }),
            expandedTags = TagUtils.unique(staticDetails.expandedTags or TagUtils.expandHierarchy(staticDetails.tags or { staticDetails.primary or "Misc.General" })),
            basePrice = tonumber(staticDetails.basePrice or staticDetails.price) or Config.pricing.minPrice,
            price = tonumber(staticDetails.price or staticDetails.basePrice) or Config.pricing.minPrice,
            rawScore = tonumber(staticDetails.rawScore or staticDetails.basePrice or staticDetails.price) or Config.pricing.minPrice,
            confidence = tonumber(staticDetails.confidence) or 1,
            stock = Core.deepCopy(staticDetails.stock or { min = 0, max = 0 }),
            source = "static",
        }
    end

    return buildFallbackDetails(fullType)
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
    return DynamicTrading.EnsureRuntimeRegistryLoaded(false)
end

function DynamicTrading.AdminRebuildCatalog()
    return DynamicTrading.RegenerateItemRegistry("admin_rebuild")
end

function DynamicTrading.ReloadRuntimeRules()
    local rules = getRuntimeRules()
    if rules and rules.loadFromFile then
        rules.loadFromFile(true)
    end
    DynamicTrading.ClearRuntimeCache()
    return DynamicTrading.EnsureRuntimeRegistryLoaded(false)
end

local function canRegenerateForPlayer(player)
    if not isClient() and not isServer() then
        return true
    end

    if DynamicTrading.PriceConfig and DynamicTrading.PriceConfig.CanEdit then
        return DynamicTrading.PriceConfig.CanEdit(player)
    end

    if not player or not player.getAccessLevel then
        return false
    end

    local accessLevel = tostring(player:getAccessLevel() or "")
    return string.lower(accessLevel) == "admin"
end

local function onClientCommand(module, command, player, args)
    if module ~= "DynamicTrading" or command ~= "RegenerateItemRegistry" then
        return
    end

    if not canRegenerateForPlayer(player) then
        if isServer() and sendServerCommand then
            sendServerCommand(player, "DynamicTrading", "RegenerateItemRegistryResult", {
                success = false,
                message = "Unauthorized: admin access required.",
            })
        end
        return
    end

    local ok, catalog = pcall(DynamicTrading.RegenerateItemRegistry, tostring(args and args.reason or "client_request"))
    local payload = {
        success = ok == true and type(catalog) == "table",
        total = ok == true and type(catalog) == "table" and tonumber(catalog.total) or 0,
        message = ok == true and type(catalog) == "table"
            and ("DT_Items registry rebuild requested. Cached items currently loaded: " .. tostring(catalog.total or 0))
            or ("Failed to rebuild DT_Items registry: " .. tostring(catalog)),
    }

    if isServer() and sendServerCommand then
        sendServerCommand(player, "DynamicTrading", "RegenerateItemRegistryResult", payload)
    end
end

local function onServerCommand(module, command, args)
    if module ~= "DynamicTrading" or command ~= "RegenerateItemRegistryResult" then
        return
    end

    if LuaEventManager and LuaEventManager.OnDynamicTradingItemRegistryRegenerated then
        triggerEvent("OnDynamicTradingItemRegistryRegenerated", args or {})
    end

    if DynamicTrading.Log then
        DynamicTrading.Log(
            "MarketSense",
            "Registry",
            (args and args.success) and "Info" or "Warn",
            tostring(args and args.message or "Item registry regeneration result received.")
        )
    end
end

Events.OnClientCommand.Add(onClientCommand)
Events.OnServerCommand.Add(onServerCommand)

return DynamicTrading
