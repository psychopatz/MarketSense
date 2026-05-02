require "MarketSense/DT_HeuristicsDB"

-- Data module paths inside the MarketSense mod (common/media/lua/shared/):
--   DT/MarketSense/Items/MS_RuntimeRules_Data.lua
--   DT/MarketSense/Pricing/MS_TagPriceAdditions_Data.lua
-- Written by DynamicTrading ModManager. Do not hand-edit while manager is running.
local DATA_MODULE = "DT/MarketSense/Items/MS_RuntimeRules_Data"
local TAG_DATA_MODULE = "DT/MarketSense/Pricing/MS_TagPriceAdditions_Data"

local function cloneMap(source)
    local out = {}
    for key, value in pairs(source or {}) do
        if type(value) == "table" then
            local inner = {}
            for k, v in pairs(value) do
                inner[k] = v
            end
            out[key] = inner
        else
            out[key] = value
        end
    end
    return out
end

DynamicTrading = DynamicTrading or {}
DynamicTrading.RuntimeRules = DynamicTrading.RuntimeRules or {
    loaded = false,
    blacklist = {},
    whitelist = {},
    appliedItems = {},
    appliedTags = {},
    previousTagData = {},
    overrideData = {},
    tagAdditionData = {},
}

local RuntimeRules = DynamicTrading.RuntimeRules
local DB = DynamicTrading.HeuristicsDB

function RuntimeRules.reset()
    for itemId, _ in pairs(RuntimeRules.appliedItems or {}) do
        DB.items[itemId] = nil
    end

    for tag, _ in pairs(RuntimeRules.appliedTags or {}) do
        local previous = RuntimeRules.previousTagData and RuntimeRules.previousTagData[tag] or false
        if previous == false then
            DB.tags[tag] = nil
        else
            DB.tags[tag] = cloneMap(previous)
        end
    end

    RuntimeRules.blacklist = {}
    RuntimeRules.whitelist = {}
    RuntimeRules.appliedItems = {}
    RuntimeRules.appliedTags = {}
    RuntimeRules.previousTagData = {}
    RuntimeRules.overrideData = {}
    RuntimeRules.tagAdditionData = {}
end

function RuntimeRules.loadFromFile(force)
    if RuntimeRules.loaded and not force then
        return true
    end

    RuntimeRules.reset()

    -- Force-reload clears the require cache so the updated file is re-read.
    if force and package and package.loaded then
        package.loaded[DATA_MODULE] = nil
        package.loaded[TAG_DATA_MODULE] = nil
    end

    local ok, data = pcall(require, DATA_MODULE)
    if not ok or type(data) ~= "table" then
        RuntimeRules.loaded = true
        return false
    end

    -- Blacklist
    for _, itemId in ipairs(data.blacklist or {}) do
        if type(itemId) == "string" and itemId ~= "" then
            RuntimeRules.blacklist[itemId] = true
        end
    end

    -- Whitelist
    for _, itemId in ipairs(data.whitelist or {}) do
        if type(itemId) == "string" and itemId ~= "" then
            RuntimeRules.whitelist[itemId] = true
        end
    end

    -- Item overrides
    for _, entry in ipairs(data.overrides or {}) do
        local itemId = entry.id
        if type(itemId) == "string" and itemId ~= "" then
            local override = {}

            if type(entry.price) == "number" then
                override.price = entry.price
            end

            if type(entry.tags) == "table" and #entry.tags > 0 then
                override.tags = entry.tags
            end

            local sMin = type(entry.stockMin) == "number" and entry.stockMin or nil
            local sMax = type(entry.stockMax) == "number" and entry.stockMax or nil
            if sMin ~= nil or sMax ~= nil then
                override.stock = {}
                if sMin ~= nil then
                    override.stock.min = math.max(0, math.floor(sMin))
                end
                if sMax ~= nil then
                    override.stock.max = math.max(0, math.floor(sMax))
                end
                if override.stock.min ~= nil and override.stock.max ~= nil and override.stock.min > override.stock.max then
                    override.stock.min = override.stock.max
                end
            end

            DB.registerItem(itemId, override)
            RuntimeRules.appliedItems[itemId] = true
            RuntimeRules.overrideData[itemId] = override
        end
    end

    -- Tag additions exported from ModManager Tag Pricing page.
    local okTags, tagData = pcall(require, TAG_DATA_MODULE)
    if okTags and type(tagData) == "table" then
        for tag, addition in pairs(tagData.tagAdditions or {}) do
            local numeric = tonumber(addition)
            if type(tag) == "string" and tag ~= "" and numeric ~= nil then
                if RuntimeRules.previousTagData[tag] == nil then
                    local existing = DB.getTag and DB.getTag(tag) or DB.tags[tag]
                    RuntimeRules.previousTagData[tag] = existing and cloneMap(existing) or false
                end

                local tagRule = cloneMap(DB.getTag and DB.getTag(tag) or DB.tags[tag] or {})
                tagRule.add = numeric
                DB.registerTag(tag, tagRule)

                RuntimeRules.appliedTags[tag] = true
                RuntimeRules.tagAdditionData[tag] = numeric
            end
        end
    end

    RuntimeRules.loaded = true
    return true
end

function RuntimeRules.isWhitelisted(fullType)
    RuntimeRules.loadFromFile(false)
    return RuntimeRules.whitelist[fullType] == true
end

function RuntimeRules.isBlacklisted(fullType)
    RuntimeRules.loadFromFile(false)
    if RuntimeRules.whitelist[fullType] == true then
        return false
    end
    return RuntimeRules.blacklist[fullType] == true
end

function RuntimeRules.shouldSkip(fullType)
    return RuntimeRules.isBlacklisted(fullType)
end

function RuntimeRules.getOverride(fullType)
    RuntimeRules.loadFromFile(false)
    return RuntimeRules.overrideData[fullType]
end

function RuntimeRules.getTagAddition(tag)
    RuntimeRules.loadFromFile(false)
    return RuntimeRules.tagAdditionData[tag]
end

return RuntimeRules
