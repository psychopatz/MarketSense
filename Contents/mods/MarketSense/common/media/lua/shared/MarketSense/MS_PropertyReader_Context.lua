require "MarketSense/MS_RuntimeCache"
require "MarketSense/MS_PropertyReader_Signals"
require "MarketSense/MS_PropertyReader_Facts"
require "MarketSense/MS_PropertyReader_ContextModel"
require "MarketSense/MS_PropertyReader_Enrichment"
require "MarketSense/MS_FoodVariantEvidence"

MarketSense = MarketSense or {}

local ContextBuilder = {}
local Core = MarketSense.Core
local Cache = MarketSense.RuntimeCache
local FactReader = require "MarketSense/MS_PropertyReader_Facts"
local ContextModel = require "MarketSense/MS_PropertyReader_ContextModel"
local Enrichment = require "MarketSense/MS_PropertyReader_Enrichment"
local FoodVariantEvidence = require "MarketSense/MS_FoodVariantEvidence"

local function buildVariantContext(fullType)
    return ContextBuilder.buildContext(fullType, nil, true)
end

local function isLiveInstanceContext(context)
    if type(context) ~= "table" or context.isInventoryItemInstance ~= true then
        return false
    end

    -- ContextModel now records this directly. The trace check keeps old
    -- cached contexts safe while a running session migrates to the new field.
    if context.isTemporary == true then
        return false
    end
    if context.foodFactTrace and context.foodFactTrace.isTemporary == true then
        return false
    end
    return true
end

function ContextBuilder.buildContext(scriptItemOrFullType, inventoryItem, skipFoodVariantEvidence)
    if type(scriptItemOrFullType) == "table" and scriptItemOrFullType.fullType and scriptItemOrFullType.item ~= nil then
        return scriptItemOrFullType
    end

    local scriptItem = nil
    local fullType = nil
    local instance = inventoryItem
    local isTemporary = false

    if type(scriptItemOrFullType) == "string" then
        fullType = scriptItemOrFullType
        -- A cached context is definition-level data. An explicit inventory
        -- instance carries live state (condition, weight, etc.) and must
        -- always be read afresh.
        if inventoryItem == nil then
            local cached = Cache.getContext(fullType)
            if cached and isLiveInstanceContext(cached) then
                cached = nil
            end
            if cached then
                if cached.foodVariantEvidence == nil and not skipFoodVariantEvidence then
                    FoodVariantEvidence.apply(cached, buildVariantContext)
                    Cache.setContext(cached.fullType or fullType, cached)
                end
                return Core.deepCopy(cached)
            end
        end
        scriptItem = Core.findScriptItem(fullType)
    else
        scriptItem = scriptItemOrFullType
        fullType = Core.safeString(scriptItem, { "getFullName", "getName" }, "")
    end

    local moduleName, typeName = Core.splitFullType(fullType)
    if scriptItem then
        local readModuleName = Core.safeString(scriptItem, "getModuleName", moduleName)
        if readModuleName ~= "" then moduleName = readModuleName end
        local readTypeName = Core.safeString(scriptItem, { "getName", "getTypeString", "getDisplayName" }, typeName)
        if readTypeName ~= "" then typeName = readTypeName end
        if moduleName ~= "" and moduleName ~= "Unknown" and typeName ~= "" then
            fullType = moduleName .. "." .. typeName
        end
    end

    if not instance then
        instance = Core.createTemporaryInstance(fullType)
        isTemporary = instance ~= nil
    end

    local facts = FactReader.read(scriptItem, instance, inventoryItem, moduleName, typeName)
    local context = ContextModel.build(
        facts, scriptItem, fullType, moduleName, typeName, instance, isTemporary
    )
    Enrichment.apply(context)
    if not skipFoodVariantEvidence then
        FoodVariantEvidence.apply(context, buildVariantContext)
    end

    if isTemporary then Core.releaseTemporaryInstance(instance) end
    -- An explicit inventory instance is live state, not a reusable item
    -- definition. Caching it would let a later static lookup inherit its
    -- vessel, condition, freshness, or exact-price behavior.
    if inventoryItem == nil then
        Cache.setContext(context.fullType, context)
    end
    return Core.deepCopy(context)
end


return ContextBuilder
