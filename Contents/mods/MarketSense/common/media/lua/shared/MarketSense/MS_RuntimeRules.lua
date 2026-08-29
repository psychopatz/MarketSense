require "MarketSense/MS_HeuristicsDB"

local DATA_MODULE = "MarketSense/Items/MS_RuntimeRules_Data"
local TAG_DATA_MODULE = "MarketSense/Common/Pricing/MS_TagPriceAdditions_Data"

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

MarketSense.RuntimeRules = MarketSense.RuntimeRules or {
    loaded = false,
    blacklist = {},
    whitelist = {},
    appliedItems = {},
    appliedTags = {},
    previousTagData = {},
    overrideData = {},
    tagAdditionData = {},
}

local RuntimeRules = MarketSense.RuntimeRules
local DB = MarketSense.HeuristicsDB

local function ensureArray(value)
    if type(value) == "table" then
        return value
    end
    return {}
end

local function matchesPatterns(fullType, patterns)
    local input = tostring(fullType or "")
    for _, pattern in ipairs(patterns or {}) do
        if type(pattern) == "string" and pattern ~= "" then
            local ok, matched = pcall(string.match, input, pattern)
            if ok and matched then
                return true
            end
        end
    end
    return false
end

local function normalizeOverride(entry)
    if type(entry) ~= "table" then
        return nil
    end

    local override = {}

    if type(entry.price) == "number" then
        override.price = entry.price
    end
    if type(entry.add) == "number" then
        override.add = entry.add
    end
    if type(entry.mult) == "number" then
        override.mult = entry.mult
    end
    if type(entry.minPrice) == "number" then
        override.minPrice = entry.minPrice
    elseif type(entry.min) == "number" then
        override.min = entry.min
    end

    if type(entry.tags) == "table" and #entry.tags > 0 then
        override.tags = entry.tags
    end

    if type(entry.addTags) == "table" and #entry.addTags > 0 then
        override.addTags = entry.addTags
    end

    if type(entry.removeTags) == "table" and #entry.removeTags > 0 then
        override.removeTags = entry.removeTags
    end

    local stock = nil
    if type(entry.stock) == "table" then
        stock = {
            min = entry.stock.min,
            max = entry.stock.max,
        }
    end

    local sMin = type(entry.stockMin) == "number" and entry.stockMin or (stock and stock.min or nil)
    local sMax = type(entry.stockMax) == "number" and entry.stockMax or (stock and stock.max or nil)
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

    local hasOverride = false
    for _ in pairs(override) do
        hasOverride = true
        break
    end
    if not hasOverride then
        return nil
    end

    return override
end

local function applyOverride(itemId, override)
    if type(itemId) ~= "string" or itemId == "" or type(override) ~= "table" then
        return
    end
    DB.registerItem(itemId, override)
    RuntimeRules.appliedItems[itemId] = true
    RuntimeRules.overrideData[itemId] = override
end

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
    RuntimeRules.blacklistPatterns = {}
    RuntimeRules.whitelistPatterns = {}
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

    if force and MarketSense.Config and type(MarketSense.Config.reloadExported) == "function" then
        MarketSense.Config.reloadExported()
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
    for _, pattern in ipairs(data.blacklistPatterns or {}) do
        if type(pattern) == "string" and pattern ~= "" then
            RuntimeRules.blacklistPatterns[#RuntimeRules.blacklistPatterns + 1] = pattern
        end
    end

    -- Whitelist
    for _, itemId in ipairs(data.whitelist or {}) do
        if type(itemId) == "string" and itemId ~= "" then
            RuntimeRules.whitelist[itemId] = true
        end
    end
    for _, pattern in ipairs(data.whitelistPatterns or {}) do
        if type(pattern) == "string" and pattern ~= "" then
            RuntimeRules.whitelistPatterns[#RuntimeRules.whitelistPatterns + 1] = pattern
        end
    end

    -- Item overrides
    local listOverrides = ensureArray(data.overrides)
    for _, entry in ipairs(listOverrides) do
        local itemId = type(entry) == "table" and entry.id or nil
        if type(itemId) == "string" and itemId ~= "" then
            local override = normalizeOverride(entry)
            if override then
                applyOverride(itemId, override)
            end
        end
    end

    -- Map-based overrides format:
    -- overridesById = { ["Base.Battery"] = { price = 50, addTags = {...}, removeTags = {...}, stock = {min=1,max=4} } }
    for itemId, entry in pairs(data.overridesById or {}) do
        if type(itemId) == "string" and itemId ~= "" then
            local override = normalizeOverride(entry)
            if override then
                applyOverride(itemId, override)
            end
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
    if matchesPatterns(fullType, RuntimeRules.whitelistPatterns) then
        return true
    end
    return RuntimeRules.whitelist[fullType] == true
end

function RuntimeRules.isBlacklisted(fullType)
    RuntimeRules.loadFromFile(false)
    if RuntimeRules.isWhitelisted(fullType) then
        return false
    end
    if matchesPatterns(fullType, RuntimeRules.blacklistPatterns) then
        return true
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

function RuntimeRules.getRules()
    RuntimeRules.loadFromFile(false)
    return {
        blacklist = cloneMap(RuntimeRules.blacklist),
        whitelist = cloneMap(RuntimeRules.whitelist),
        blacklistPatterns = cloneMap(RuntimeRules.blacklistPatterns),
        whitelistPatterns = cloneMap(RuntimeRules.whitelistPatterns),
        overridesById = cloneMap(RuntimeRules.overrideData),
        tagAdditions = cloneMap(RuntimeRules.tagAdditionData),
    }
end

function RuntimeRules.apply(ruleTable)
    if type(ruleTable) ~= "table" then
        return false
    end

    RuntimeRules.loadFromFile(false)

    for _, itemId in ipairs(ruleTable.blacklist or {}) do
        if type(itemId) == "string" and itemId ~= "" then
            RuntimeRules.blacklist[itemId] = true
        end
    end

    for _, itemId in ipairs(ruleTable.whitelist or {}) do
        if type(itemId) == "string" and itemId ~= "" then
            RuntimeRules.whitelist[itemId] = true
        end
    end

    for _, pattern in ipairs(ruleTable.blacklistPatterns or {}) do
        if type(pattern) == "string" and pattern ~= "" then
            RuntimeRules.blacklistPatterns[#RuntimeRules.blacklistPatterns + 1] = pattern
        end
    end

    for _, pattern in ipairs(ruleTable.whitelistPatterns or {}) do
        if type(pattern) == "string" and pattern ~= "" then
            RuntimeRules.whitelistPatterns[#RuntimeRules.whitelistPatterns + 1] = pattern
        end
    end

    for itemId, entry in pairs(ruleTable.overridesById or {}) do
        local override = normalizeOverride(entry)
        if override then
            applyOverride(itemId, override)
        end
    end

    for _, entry in ipairs(ruleTable.overrides or {}) do
        local itemId = type(entry) == "table" and entry.id or nil
        local override = normalizeOverride(entry)
        if type(itemId) == "string" and itemId ~= "" and override then
            applyOverride(itemId, override)
        end
    end

    return true
end

return RuntimeRules
