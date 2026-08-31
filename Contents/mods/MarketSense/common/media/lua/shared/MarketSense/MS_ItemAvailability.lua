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

Availability.VERSION = 2
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
    building = false,
    records = {},
    counts = {},
    itemCount = 0,
    sourceCount = 0,
    engineSignals = {},
    itemsByFullType = {},
    itemsByName = {},
}

local function collectionSize(collection)
    if collection == nil then return 0 end
    if type(collection) == "table" then
        if type(collection.size) == "function" then
            local value = collection.size(collection)
            return math.max(0, tonumber(value) or 0)
        end
        return #collection
    end
    local size = collection.size
    if type(size) == "function" then
        local value = size(collection)
        return math.max(0, tonumber(value) or 0)
    end
    return 0
end

local function collectionValue(collection, index)
    if collection == nil then return nil end
    local get = collection.get
    if type(get) == "function" then
        return get(collection, index)
    end
    if type(collection) == "table" then
        return collection[index + 1]
    end
    return nil
end

local function timestampMs()
    if type(getTimestampMs) ~= "function" then return nil end
    return tonumber(getTimestampMs())
end

local function budgetReached(startedAt, maxMs, processed, maxItems)
    if processed >= maxItems then return true end
    if startedAt == nil or maxMs == nil then return false end
    local now = timestampMs()
    return now ~= nil and now - startedAt >= maxMs
end

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
    -- This is the one Java-proxy boundary in the availability scanner. PZ
    -- exposes optional getters differently across versions, and a rejected
    -- Java call must not abort the rest of the availability scan.
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

    local itemsByFullType = Availability.state.itemsByFullType or {}
    local itemsByName = Availability.state.itemsByName or {}
    local indexed = itemsByFullType[token]
    if indexed then return indexed, fullTypeOf(indexed) end
    if string.find(token, ".", 1, true) == nil then
        local baseItem = itemsByFullType["Base." .. token]
        if baseItem then return baseItem, fullTypeOf(baseItem) end
        local byName = itemsByName[token]
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
        lootSources = {},
        lootEntryCount = 0,
        lootWeightedEntryCount = 0,
        lootWeightSum = 0,
        lootRelativeWeightSum = 0,
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

local function addLootEvidence(fullType, source, reference, weight, relativeWeight)
    fullType = trim(fullType)
    if fullType == "" then return end

    local record = ensureRecord(fullType)
    addChannel(fullType, "loot", reference or ("runtime:" .. tostring(source or "loot")))
    source = trim(source)
    if source ~= "" then record.lootSources[source] = true end
    record.lootEntryCount = (record.lootEntryCount or 0) + 1

    weight = tonumber(weight)
    if weight ~= nil and weight >= 0 then
        record.lootWeightedEntryCount = (record.lootWeightedEntryCount or 0) + 1
        record.lootWeightSum = (record.lootWeightSum or 0) + weight
        relativeWeight = tonumber(relativeWeight)
        if relativeWeight ~= nil and relativeWeight >= 0 then
            record.lootRelativeWeightSum = (record.lootRelativeWeightSum or 0) + relativeWeight
        end
    end
end

-- The offline evaluator projects the static scanner's aggregate loot evidence
-- onto this optional bridge-only item method. Import it lazily from get(),
-- after real PZ distributions have been scanned, so real PZ distributions are
-- authoritative and the bridge cannot double-count them.
local function importProjectedLootEvidence(item)
    local imported = callValue(item, "getMarketSenseLootEvidence")
    if type(imported) ~= "table" or imported.status ~= "observed" then return end

    local entryCount = tonumber(imported.entryCount) or 0
    local fullType = fullTypeOf(item)
    if fullType == "" or entryCount <= 0 then return end

    local record = ensureRecord(fullType)
    if (tonumber(record.lootEntryCount) or 0) > 0 then return end

    addChannel(fullType, "loot", "offline:" .. tostring(imported.source or "loot_distribution"))
    local references = imported.references
    if type(references) == "table" then
        for _, reference in ipairs(references) do
            addUnique(record.references, reference)
        end
    end

    local sourceCount = math.max(1, tonumber(imported.sourceCount) or 1)
    for index = 1, sourceCount do
        record.lootSources["imported:" .. tostring(index)] = true
    end
    record.lootEntryCount = entryCount
    record.lootWeightedEntryCount = tonumber(imported.weightedEntryCount) or 0
    record.lootWeightSum = tonumber(imported.weightSum) or 0
    record.lootRelativeWeightSum = tonumber(imported.relativeWeight) or 0
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
    Core.forEachCollection(collection, callback)
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

local function scanLootList(value, source, path)
    if type(value) ~= "table" then return end

    local length = #value
    if length < 2 then return end
    local entries = {}
    local totalWeight = 0
    for index = 1, length, 2 do
        local itemName = value[index]
        local weight = tonumber(value[index + 1])
        if weight ~= nil then totalWeight = totalWeight + math.max(0, weight) end
        if type(itemName) == "string" then
            local item = resolveItem(itemName)
            if item then
                weight = weight and math.max(0, weight) or nil
                entries[#entries + 1] = {
                    fullType = fullTypeOf(item),
                    weight = weight,
                }
            end
        end
    end

    for _, entry in ipairs(entries) do
        local relativeWeight
        if totalWeight > 0 and entry.weight ~= nil then
            relativeWeight = entry.weight / totalWeight
        end
        local lootSource = tostring(source) .. ":" .. tostring(path or "items")
        addLootEvidence(entry.fullType, lootSource,
            "runtime:" .. tostring(source) .. ":" .. tostring(path or "items"),
            entry.weight, relativeWeight)
    end
end

local function scanRuntimeTable(value, channel, source, seen, depth, path)
    if type(value) ~= "table" or depth > 10 then return end
    seen = seen or {}
    if seen[value] then return end
    seen[value] = true

    for key, child in pairs(value) do
        local keyText = tostring(key or "")
        if channel == "loot" and keyText == "items" and type(child) == "table" then
            scanLootList(child, source, path and (path .. ".items") or "items")
        elseif type(child) == "string" then
            local item = resolveItem(child)
            if item then
                addChannel(fullTypeOf(item), channel, "runtime:" .. source)
            end
        elseif type(child) == "table" then
            local childPath = path and (path .. "." .. keyText) or keyText
            scanRuntimeTable(child, channel, source, seen, depth + 1, childPath)
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
            scanRuntimeTable(value, source.channel, source.name, {}, 0, source.name)
        end
    end
end

local function lootRarity(record)
    local entries = tonumber(record and record.lootEntryCount) or 0
    local sources = 0
    for _ in pairs(record and record.lootSources or {}) do sources = sources + 1 end

    if entries <= 0 then
        return "Common", "fallback_default", 0.20, {
            status = "not_detected",
            rarity = "Common",
            source = "fallback_default",
            confidence = 0.20,
            sourceCount = sources,
            entryCount = 0,
            weightedEntryCount = 0,
            weightSum = 0,
            relativeWeight = 0,
        }
    end

    local weighted = tonumber(record.lootWeightedEntryCount) or 0
    local relative = tonumber(record.lootRelativeWeightSum) or 0
    local averageRelative = weighted > 0 and relative / weighted or nil
    -- A missing chance proves presence only; do not call an unweighted entry
    -- Rare without normalized local loot-table evidence.
    local rareWeight = averageRelative ~= nil and averageRelative <= 0.10
    local uncommonWeight = averageRelative == nil or averageRelative <= 0.25
    local rarity = "Common"
    if entries <= 1 and sources <= 1 and rareWeight then
        rarity = "Rare"
    elseif entries <= 4 and sources <= 2 and uncommonWeight then
        rarity = "Uncommon"
    end

    local confidence = math.min(0.96, 0.62 + 0.06 * math.min(sources, 3)
        + 0.03 * math.min(entries, 4))
    return rarity, "loot_distribution", confidence, {
        status = "observed",
        rarity = rarity,
        source = "loot_distribution",
        confidence = confidence,
        sourceCount = sources,
        entryCount = entries,
        weightedEntryCount = weighted,
        weightSum = tonumber(record.lootWeightSum) or 0,
        relativeWeight = relative,
        averageRelativeWeight = averageRelative,
    }
end

function Availability.register(fullType, channel, reference)
    local item, resolved = resolveItem(fullType)
    if item then
        addChannel(resolved, channel, reference or "registered provider")
        return true
    end
    return false
end

local function resetState()
    Availability.state = {
        built = false,
        building = true,
        records = {},
        counts = {},
        itemCount = 0,
        sourceCount = 0,
        engineSignals = {},
        itemsByFullType = {},
        itemsByName = {},
    }
    return Availability.state
end

function Availability.beginRebuild(allItems)
    if allItems == nil and type(getAllItems) == "function" then
        allItems = getAllItems()
    end

    resetState()
    local job = {
        allItems = allItems,
        index = 0,
        total = collectionSize(allItems),
        phase = "items",
        sourceIndex = 1,
        manager = nil,
        done = false,
    }
    Availability.state.rebuildJob = job
    return job
end

local function finishRebuild(job)
    local total = 0
    for _, record in pairs(Availability.state.records) do
        total = total + 1
        local status = #record.exclusions > 0 and "excluded"
            or hasEntries(record.channels) and "obtainable" or "uncertain"
        Availability.state.counts[status] = (Availability.state.counts[status] or 0) + 1
    end
    Availability.state.itemCount = math.max(Availability.state.itemCount, total)
    Availability.state.built = true
    Availability.state.building = false
    Availability.state.rebuildJob = nil
    job.done = true
    job.phase = "done"
end

-- Advance only the item-definition phase by a bounded number of entries. The
-- recipe and runtime-table phases are intentionally separate ticks so a cold
-- boot never pays the complete acquisition scan in one frame.
function Availability.stepRebuild(job, maxItems, maxMs)
    if type(job) ~= "table" or job.done then return true end
    maxItems = math.max(1, math.floor(tonumber(maxItems) or 1))
    maxMs = tonumber(maxMs)
    local startedAt = maxMs and timestampMs() or nil

    if job.phase == "items" then
        local processed = 0
        while job.index < job.total and not budgetReached(startedAt, maxMs, processed, maxItems) do
            local item = collectionValue(job.allItems, job.index)
            job.index = job.index + 1
            processed = processed + 1
            if item ~= nil then
                Availability.state.itemCount = Availability.state.itemCount + 1
                local itemFullType = fullTypeOf(item)
                if itemFullType ~= "" then
                    Availability.state.itemsByFullType[itemFullType] = item
                    local _, itemName = Core.splitFullType(itemFullType)
                    Availability.state.itemsByName[itemName] = Availability.state.itemsByName[itemName] or {}
                    Availability.state.itemsByName[itemName][#Availability.state.itemsByName[itemName] + 1] = item
                end
                inspectScriptItem(item)
            end
        end
        if job.index < job.total then return false end
        job.phase = "regularRecipes"
        return false
    end

    if job.phase == "regularRecipes" then
        local manager = job.manager
        if manager == nil and type(getScriptManager) == "function" then
            manager = getScriptManager()
        end
        if manager == nil and ScriptManager and ScriptManager.instance then
            manager = ScriptManager.instance
        end
        job.manager = manager
        if manager then scanRegularRecipes(manager) end
        job.phase = "craftRecipes"
        return false
    end

    if job.phase == "craftRecipes" then
        if job.manager then scanCraftRecipes(job.manager) end
        job.phase = "evolvedRecipes"
        return false
    end

    if job.phase == "evolvedRecipes" then
        if job.manager then scanEvolvedRecipes(job.manager) end
        job.phase = "runtimeSources"
        return false
    end

    if job.phase == "runtimeSources" then
        local source = RUNTIME_SOURCES[job.sourceIndex]
        if source then
            local value = _G[source.name]
            if type(value) == "table" then
                Availability.state.sourceCount = Availability.state.sourceCount + 1
                scanRuntimeTable(value, source.channel, source.name, {}, 0, source.name)
            end
            job.sourceIndex = job.sourceIndex + 1
            return false
        end
        job.phase = "finalize"
        return false
    end

    if job.phase == "sources" then
        -- Backward-compatible state name for jobs created by an older module
        -- instance during a Lua reload.
        local manager = nil
        if type(getScriptManager) == "function" then
            manager = getScriptManager()
        end
        if not manager and ScriptManager and ScriptManager.instance then
            manager = ScriptManager.instance
        end
        if manager then scanRegularRecipes(manager) end
        scanRuntimeSources()
        job.phase = "finalize"
        return false
    end

    finishRebuild(job)
    return true
end

function Availability.rebuild(allItems)
    local job = Availability.beginRebuild(allItems)
    while not Availability.stepRebuild(job, math.max(1, job.total)) do end
    return Availability.state
end

function Availability.ensureBuilt(allItems)
    if Availability.state.building then
        return Availability.state
    end
    if not Availability.state.built then
        return Availability.rebuild(allItems)
    end
    return Availability.state
end

function Availability.get(fullType)
    Availability.ensureBuilt()
    local item, resolved = resolveItem(fullType)
    resolved = resolved ~= "" and resolved or trim(fullType)
    if item then importProjectedLootEvidence(item) end
    local record = Availability.state.records[resolved]
    local channels = {}
    local references = {}
    local exclusions = {}
    local engineSignals = {}
    local recordRarity, raritySource, rarityConfidence, rarityEvidence
    if record then
        for channel in pairs(record.channels) do channels[#channels + 1] = channel end
        references = copyList(record.references)
        exclusions = copyList(record.exclusions)
        engineSignals = copyList(record.engineSignals)
        recordRarity, raritySource, rarityConfidence, rarityEvidence = lootRarity(record)
    else
        recordRarity, raritySource, rarityConfidence, rarityEvidence = lootRarity(nil)
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
        rarity = recordRarity,
        raritySource = raritySource,
        rarityConfidence = rarityConfidence,
        rarityEvidence = rarityEvidence,
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
