-- ============================================================================
-- MARKET SENSE: RUNTIME ITEM AVAILABILITY
-- ============================================================================
--
-- This is intentionally part of the mod runtime.  A script item existing in
-- ScriptManager is not enough to make it a sensible market item: PZ also
-- carries engine-owned acquisition state for loot, crafting and foraging.
--
-- The registry uses this module as a hard gate.  The Python application may
-- compare its static source audit with this result, but it must not decide
-- which rows enter the MarketSense catalog and its optional consumer bridges.
-- ============================================================================

require "MarketSense/MS_Core"

MarketSense = MarketSense or {}
MarketSense.ItemAvailability = MarketSense.ItemAvailability or {}

local Availability = MarketSense.ItemAvailability
local Core = MarketSense.Core

Availability.VERSION = 1
Availability.CHANNEL_LABELS = {
    loot = "loot/distribution",
    craft = "craft recipe output",
    evolved_recipe = "evolved recipe output",
    forage = "foraging",
    farming = "farming/harvest",
    fishing = "fishing catch",
    trapping = "trapping catch",
    animal = "animal/butchering output",
    scripted = "scripted game output",
}

Availability.state = Availability.state or {
    built = false,
    records = {},
    counts = {},
    itemCount = 0,
    sourceCount = 0,
    engineSignals = {},
    itemsByFullType = {},
    itemsByName = {},
}

local function trim(value)
    return Core.trim and Core.trim(value) or tostring(value or "")
end

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function addUnique(list, value)
    value = trim(value)
    if value == "" then return end
    for _, existing in ipairs(list or {}) do
        if existing == value then return end
    end
    list[#list + 1] = value
end

local function copyList(source)
    local out = {}
    for _, value in ipairs(source or {}) do
        out[#out + 1] = value
    end
    return out
end

local function callValue(object, methodName, ...)
    if object == nil or type(methodName) ~= "string" then return nil end
    local method = object[methodName]
    if type(method) ~= "function" then return nil end
    local ok, value = pcall(method, object, ...)
    return ok and value or nil
end

local function callBoolean(object, methodName)
    local value = callValue(object, methodName)
    if value == nil then return nil end
    if type(value) == "string" then
        local token = lower(value)
        if token == "false" or token == "0" or token == "no" then return false end
        if token == "true" or token == "1" or token == "yes" then return true end
    end
    return not not value
end

local function fullTypeOf(item)
    if item == nil then return "" end
    local fullType = callValue(item, "getFullName")
    if fullType == nil or trim(fullType) == "" then
        local moduleName = trim(callValue(item, "getModuleName"))
        local typeName = trim(callValue(item, "getName"))
        if moduleName ~= "" and typeName ~= "" then
            fullType = moduleName .. "." .. typeName
        end
    end
    return trim(fullType)
end

local function resolveItem(value)
    local token = trim(value)
    if token == "" then return nil, "" end

    local indexed = Availability.state.itemsByFullType[token]
    if indexed then return indexed, fullTypeOf(indexed) end
    if string.find(token, ".", 1, true) == nil then
        local baseItem = Availability.state.itemsByFullType["Base." .. token]
        if baseItem then return baseItem, fullTypeOf(baseItem) end
        local byName = Availability.state.itemsByName[token]
        if byName and #byName == 1 then
            return byName[1], fullTypeOf(byName[1])
        end
    end

    local item = Core.findScriptItem(token)
    if item then return item, fullTypeOf(item) end

    if string.find(token, "%.", 1, true) == nil then
        item = Core.findScriptItem("Base." .. token)
        if item then return item, fullTypeOf(item) end
    end

    return nil, ""
end

local function ensureRecord(fullType)
    local record = Availability.state.records[fullType]
    if record then return record end
    record = {
        fullType = fullType,
        channels = {},
        references = {},
        exclusions = {},
        engineSignals = {},
    }
    Availability.state.records[fullType] = record
    return record
end

local function addChannel(fullType, channel, reference)
    fullType = trim(fullType)
    channel = trim(channel)
    if fullType == "" or channel == "" then return end

    local record = ensureRecord(fullType)
    record.channels[channel] = true
    addUnique(record.references, reference or ("runtime:" .. channel))
end

local function addExclusion(fullType, reason)
    fullType = trim(fullType)
    if fullType == "" then return end
    addUnique(ensureRecord(fullType).exclusions, reason)
end

local function addEngineSignal(fullType, signal)
    local record = ensureRecord(fullType)
    addUnique(record.engineSignals, signal)
end

local function hasEntries(map)
    for _ in pairs(map or {}) do
        return true
    end
    return false
end

local function looksInternal(item, fullType)
    local name = lower(fullType)
    local displayCategory = lower(callValue(item, "getDisplayCategory"))
    local displayName = lower(callValue(item, "getDisplayName"))
    local tooltip = lower(callValue(item, "getTooltip"))

    if callBoolean(item, "getObsolete") == true then
        return "engine:obsolete"
    end
    if callBoolean(item, "isHidden") == true then
        return "engine:hidden"
    end
    if displayCategory == "hidden" or displayCategory == "debug"
        or displayCategory == "internal" or displayCategory == "zeddmg" then
        return "display category: " .. displayCategory
    end
    if string.find(name, "zeddmg_", 1, true)
        or string.find(name, ".wound_", 1, true)
        or string.find(name, ".bandage_", 1, true)
        or string.find(name, "debug", 1, true)
        or string.find(name, "dummy", 1, true)
        or string.find(name, "placeholder", 1, true) then
        return "internal/debug item name"
    end
    if string.find(displayName, "dummy item", 1, true)
        or string.find(displayName, "do not spawn", 1, true)
        or string.find(displayName, "do not use", 1, true)
        or string.find(tooltip, "dummy item", 1, true)
        or string.find(tooltip, "do not spawn", 1, true)
        or string.find(tooltip, "do not use", 1, true) then
        return "tooltip explicitly marks item as non-spawnable"
    end

    return nil
end

local function inspectScriptItem(item)
    local fullType = fullTypeOf(item)
    if fullType == "" then return end

    local exclusion = looksInternal(item, fullType)
    if exclusion then
        addExclusion(fullType, exclusion)
    end

    local signals = {
        { method = "canSpawnAsLoot", channel = "loot", label = "Item.canSpawnAsLoot" },
        { method = "isCraftRecipeProduct", channel = "craft", label = "Item.isCraftRecipeProduct" },
        { method = "canBeForaged", channel = "forage", label = "Item.canBeForaged" },
    }
    for _, signal in ipairs(signals) do
        local value = callBoolean(item, signal.method)
        if value ~= nil then
            Availability.state.engineSignals[signal.method] = true
            if value then
                addChannel(fullType, signal.channel, "engine:" .. signal.label)
                addEngineSignal(fullType, signal.label)
            end
        end
    end
end

local function eachValue(collection, callback)
    if collection == nil or type(callback) ~= "function" then return end

    local size = callValue(collection, "size")
    if tonumber(size) ~= nil and type(collection.get) == "function" then
        for index = 0, tonumber(size) - 1 do
            local ok, value = pcall(collection.get, collection, index)
            if ok and value ~= nil then callback(value, index) end
        end
        return
    end

    if type(collection) == "table" then
        for index, value in ipairs(collection) do
            callback(value, index)
        end
    end
end

local function scanRegularRecipes(manager)
    local recipes = callValue(manager, "getAllRecipes")
    eachValue(recipes, function(recipe, index)
        local result = callValue(recipe, "getResult")
        local item = result and resolveItem(callValue(result, "getFullType")) or nil
        if not item and result then
            local resultType = trim(callValue(result, "getType"))
            item = resolveItem(resultType)
        end
        if item then
            addChannel(fullTypeOf(item), "craft", "regular recipe #" .. tostring(index))
        end
    end)
end

local function scanCraftRecipes(manager)
    local recipes = callValue(manager, "getAllCraftRecipes")
    eachValue(recipes, function(recipe, recipeIndex)
        local outputs = callValue(recipe, "getOutputs")
        eachValue(outputs, function(output, outputIndex)
            local resultItems = callValue(output, "getPossibleResultItems")
            eachValue(resultItems, function(item)
                local fullType = fullTypeOf(item)
                if fullType ~= "" then
                    addChannel(fullType, "craft", "craft recipe #" .. tostring(recipeIndex)
                        .. ".output#" .. tostring(outputIndex))
                end
            end)
        end)
    end)
end

local function scanEvolvedRecipes(manager)
    local recipes = callValue(manager, "getAllEvolvedRecipesList")
    if recipes == nil then
        recipes = callValue(manager, "getAllEvolvedRecipes")
    end
    eachValue(recipes, function(recipe, index)
        local fullType = trim(callValue(recipe, "getFullResultItem"))
        local item = resolveItem(fullType)
        if not item then
            item = resolveItem(callValue(recipe, "getResultItem"))
        end
        if item then
            addChannel(fullTypeOf(item), "evolved_recipe", "evolved recipe #" .. tostring(index))
        end
    end)
end

local function scanRuntimeTable(value, channel, source, seen, depth)
    if type(value) ~= "table" or depth > 10 then return end
    seen = seen or {}
    if seen[value] then return end
    seen[value] = true

    for _, child in pairs(value) do
        if type(child) == "string" then
            local item = resolveItem(child)
            if item then
                addChannel(fullTypeOf(item), channel, "runtime:" .. source)
            end
        elseif type(child) == "table" then
            scanRuntimeTable(child, channel, source, seen, depth + 1)
        end
    end
end

local RUNTIME_SOURCES = {
    -- 42.20 keeps direct room/container entries in Distributions and the
    -- procedural tables below it.  Keep both: some valid items are only
    -- present in one of these layers.
    { name = "Distributions", channel = "loot" },
    { name = "ProceduralDistributions", channel = "loot" },
    { name = "SuburbsDistributions", channel = "loot" },
    { name = "VehicleDistributions", channel = "loot" },
    { name = "ForageSystem", channel = "forage" },
    { name = "forageSystem", channel = "forage" },
    { name = "farming_vegetableconf", channel = "farming" },
    { name = "Fishing", channel = "fishing" },
    { name = "TrapAnimals", channel = "trapping" },
    { name = "AnimalPartsDefinitions", channel = "animal" },
    { name = "AnimalDefinitions", channel = "animal" },
}

local function scanRuntimeSources()
    for _, source in ipairs(RUNTIME_SOURCES) do
        local value = _G[source.name]
        if type(value) == "table" then
            Availability.state.sourceCount = Availability.state.sourceCount + 1
            scanRuntimeTable(value, source.channel, source.name, {}, 0)
        end
    end
end

function Availability.register(fullType, channel, reference)
    local item, resolved = resolveItem(fullType)
    if item then
        addChannel(resolved, channel, reference or "registered provider")
        return true
    end
    return false
end

function Availability.rebuild(allItems)
    Availability.state = {
        built = false,
        records = {},
        counts = {},
        itemCount = 0,
        sourceCount = 0,
        engineSignals = {},
        itemsByFullType = {},
        itemsByName = {},
    }

    eachValue(allItems or (type(getAllItems) == "function" and getAllItems() or nil), function(item)
        Availability.state.itemCount = Availability.state.itemCount + 1
        local itemFullType = fullTypeOf(item)
        if itemFullType ~= "" then
            Availability.state.itemsByFullType[itemFullType] = item
            local _, itemName = Core.splitFullType(itemFullType)
            Availability.state.itemsByName[itemName] = Availability.state.itemsByName[itemName] or {}
            Availability.state.itemsByName[itemName][#Availability.state.itemsByName[itemName] + 1] = item
        end
        inspectScriptItem(item)
    end)

    local manager = nil
    if type(getScriptManager) == "function" then
        local ok, result = pcall(getScriptManager)
        if ok then manager = result end
    end
    if not manager and ScriptManager and ScriptManager.instance then
        manager = ScriptManager.instance
    end
    if manager then
        scanRegularRecipes(manager)
        scanCraftRecipes(manager)
        scanEvolvedRecipes(manager)
    end
    scanRuntimeSources()

    local total = 0
    for _, record in pairs(Availability.state.records) do
        total = total + 1
        local status = #record.exclusions > 0 and "excluded"
            or hasEntries(record.channels) and "obtainable" or "uncertain"
        Availability.state.counts[status] = (Availability.state.counts[status] or 0) + 1
    end
    Availability.state.itemCount = math.max(Availability.state.itemCount, total)
    Availability.state.built = true
    return Availability.state
end

function Availability.ensureBuilt(allItems)
    if not Availability.state.built then
        return Availability.rebuild(allItems)
    end
    return Availability.state
end

function Availability.get(fullType)
    Availability.ensureBuilt()
    local item, resolved = resolveItem(fullType)
    resolved = resolved ~= "" and resolved or trim(fullType)
    local record = Availability.state.records[resolved]
    local channels = {}
    local references = {}
    local exclusions = {}
    local engineSignals = {}
    if record then
        for channel in pairs(record.channels) do channels[#channels + 1] = channel end
        references = copyList(record.references)
        exclusions = copyList(record.exclusions)
        engineSignals = copyList(record.engineSignals)
    end
    table.sort(channels)
    table.sort(references)
    table.sort(exclusions)
    table.sort(engineSignals)

    local status = #exclusions > 0 and "excluded"
        or #channels > 0 and "obtainable" or "uncertain"
    local labels = {}
    for _, channel in ipairs(channels) do
        labels[#labels + 1] = Availability.CHANNEL_LABELS[channel] or channel
    end
    local reason = "no runtime acquisition evidence was found"
    if status == "excluded" then
        reason = "hard exclusion: " .. table.concat(exclusions, "; ")
    elseif status == "obtainable" then
        reason = "runtime acquisition evidence: " .. table.concat(labels, ", ")
    end

    return {
        fullType = resolved,
        status = status,
        obtainable = status == "obtainable",
        confidence = status == "excluded" and 1.0 or status == "obtainable" and 0.99 or 0.0,
        channels = channels,
        channelLabels = labels,
        references = references,
        exclusions = exclusions,
        engineSignals = engineSignals,
        reason = reason,
        source = "MarketSense.ItemAvailability v" .. tostring(Availability.VERSION),
    }
end

function Availability.isEligible(fullType)
    return Availability.get(fullType).status == "obtainable"
end

function Availability.getSummary()
    Availability.ensureBuilt()
    return {
        version = Availability.VERSION,
        built = Availability.state.built == true,
        itemCount = Availability.state.itemCount,
        sourceCount = Availability.state.sourceCount,
        counts = Core.shallowCopy(Availability.state.counts),
        engineSignals = Core.shallowCopy(Availability.state.engineSignals),
    }
end

return Availability
