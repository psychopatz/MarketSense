local Shared = require "MarketSense/ItemsRegistry/MS_ItemsRegistry_Shared"
local IO = require "MarketSense/ItemsRegistry/MS_ItemsRegistry_IO"
local Build = require "MarketSense/ItemsRegistry/MS_ItemsRegistry_Build"
local Availability = require "MarketSense/MS_ItemAvailability"

local Runtime = {}
local Registry = Shared.Registry
local TagUtils = Shared.TagUtils
local Config = Shared.Config

local function registerLiveItem(fullType, data)
    MarketSense.Config = MarketSense.Config or {}
    MarketSense.Config.MasterList = MarketSense.Config.MasterList or {}
    MarketSense.Config.MasterList[fullType] = MarketSense.Core.deepCopy(data)
    MarketSense.Config.ItemRegistryRevision = (tonumber(MarketSense.Config.ItemRegistryRevision) or 0) + 1
    return true
end

local function populateMasterList(indexData, activeState)
    local runtimeRules = Shared.ensureRuntimeRules()
    if runtimeRules and runtimeRules.loadFromFile then
        runtimeRules.loadFromFile(false)
    end

    MarketSense.Config = MarketSense.Config or {}
    MarketSense.Config.MasterList = {}
    MarketSense.Config.ItemRegistryRevision = (tonumber(MarketSense.Config.ItemRegistryRevision) or 0) + 1

    local catalog = {
        items = {},
        total = 0,
        modules = {},
        categories = {},
        tags = {},
        files = Shared.copyArray(indexData and indexData.files or {}),
        activeModsHash = activeState.activeModsHash,
        generatedAt = indexData and indexData.generatedAt or nil,
        source = "lean-cache",
    }

    for _, fileEntry in ipairs(indexData and indexData.files or {}) do
        local parsed = IO.parseLeanFile(fileEntry.path)
        if parsed then
            for _, group in ipairs(parsed.groups or {}) do
                if Shared.isOriginActive(group.origin, activeState.activeModSet) then
                    local baseTags = TagUtils.unique(group.tags or {})

                    for _, row in ipairs(group.items or {}) do
                        local fullType = tostring(row[1] or "")
                        if fullType ~= "" then
                            local skip = runtimeRules and runtimeRules.shouldSkip and runtimeRules.shouldSkip(fullType) or false
                            local availability = Availability.get(fullType)
                            if availability.status ~= "obtainable" then
                                skip = true
                            end
                            if not skip then
                                local baseData = {
                                    item = fullType,
                                    basePrice = tonumber(row[2]) or (Config.pricing.minPrice or 1),
                                    tags = Shared.copyArray(baseTags),
                                    stockRange = {
                                        min = math.max(0, tonumber(row[3]) or 0),
                                        max = math.max(0, tonumber(row[4]) or 0),
                                    },
                                }

                                local liveData = Build.applyRuntimeOverride(fullType, baseData, runtimeRules)
                                liveData.availability = availability
                                registerLiveItem(fullType, liveData)

                                local liveEntry = Build.buildLiveEntry(fullType, liveData, group.origin, nil, nil)
                                catalog.items[fullType] = liveEntry
                                catalog.total = catalog.total + 1
                                catalog.modules[liveEntry.moduleName] = (catalog.modules[liveEntry.moduleName] or 0) + 1
                                catalog.categories[liveEntry.category] = (catalog.categories[liveEntry.category] or 0) + 1
                                for _, tag in ipairs(liveEntry.tags or {}) do
                                    catalog.tags[tag] = (catalog.tags[tag] or 0) + 1
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    Registry.state.loaded = true
    Registry.state.activeModsHash = activeState.activeModsHash
    Registry.state.catalog = catalog
    Registry.state.lastIndex = indexData

    return catalog
end

function Runtime.loadCatalogFromCache()
    local activeState = Shared.buildActiveModState()
    Availability.ensureBuilt()
    local indexData = IO.loadIndex()
    local valid, reason = IO.validateIndex(indexData, activeState)
    if not valid then
        Shared.debugLog("Cache load skipped because index validation failed: " .. tostring(reason))
        return nil
    end
    Shared.debugLog("Loading MS_Items cache from " .. Registry.OUTPUT_HINT .. " using hash " .. tostring(activeState.activeModsHash))
    return populateMasterList(indexData, activeState)
end

function Runtime.rebuildCache(reason)
    local runtimeRules = Shared.ensureRuntimeRules()
    if runtimeRules and runtimeRules.reset then
        runtimeRules.reset()
        runtimeRules.loaded = false
    end

    local activeState = Shared.buildActiveModState()
    local previousIndex = IO.loadIndex()
    local rebuildReason = tostring(reason or "rebuild")
    Shared.log("Info", "Rebuilding MS_Items runtime cache (" .. rebuildReason .. ") from live item data.")
    Shared.debugLog("Active mods hash: " .. tostring(activeState.activeModsHash))

    local generatedItems = Build.collectGeneratedItems()
    if not Shared.hasEntries(generatedItems) then
        Shared.log("Warn", "Runtime cache rebuild produced no live items. Falling back to the previous cache if available.")
        IO.writeRebuildRequest(rebuildReason, activeState, previousIndex, "Runtime rebuild produced no items and kept the previous MS_Items cache if one was available.")
        if previousIndex and type(previousIndex.files) == "table" and #previousIndex.files > 0 then
            return populateMasterList(previousIndex, activeState)
        end
        return Shared.buildEmptyCatalog(activeState, "runtime-rebuild-empty")
    end

    local mergedItems = generatedItems
    if previousIndex and type(previousIndex.files) == "table" and #previousIndex.files > 0 then
        mergedItems = Build.mergeStoredAndGenerated(IO.loadStoredItems(previousIndex), generatedItems, activeState)
    end

    local grouped = Build.groupForWrite(mergedItems)
    if not Shared.hasEntries(grouped) then
        Shared.log("Warn", "Runtime cache rebuild failed to group generated items for MS_Items persistence.")
        IO.writeRebuildRequest(rebuildReason, activeState, previousIndex, "Runtime rebuild failed while grouping generated MS_Items.")
        if previousIndex and type(previousIndex.files) == "table" and #previousIndex.files > 0 then
            return populateMasterList(previousIndex, activeState)
        end
        return Shared.buildEmptyCatalog(activeState, "runtime-rebuild-grouping-failed")
    end

    local sourceManifestHash = Shared.buildSourceManifestHash(mergedItems, activeState)
    local indexData = Build.writeGroupedFiles(grouped, activeState, sourceManifestHash)
    if type(indexData) ~= "table" or type(indexData.files) ~= "table" or #indexData.files == 0 then
        Shared.log("Warn", "Runtime cache rebuild could not persist MS_Items files. Falling back to the previous cache if available.")
        IO.writeRebuildRequest(rebuildReason, activeState, previousIndex, "Runtime rebuild failed while writing MS_Items files.")
        if previousIndex and type(previousIndex.files) == "table" and #previousIndex.files > 0 then
            return populateMasterList(previousIndex, activeState)
        end
        return Shared.buildEmptyCatalog(activeState, "runtime-rebuild-write-failed")
    end

    Registry.state.lastRequestKey = nil
    Shared.log("Info", "Rebuilt MS_Items runtime cache with " .. tostring(#indexData.files) .. " files for " .. tostring(activeState.activeModsHash) .. ".")
    return populateMasterList(indexData, activeState)
end

function Runtime.ensureLoaded(forceRebuild)
    local activeState = Shared.buildActiveModState()
    if not forceRebuild
        and Registry.state.loaded
        and Registry.state.activeModsHash == activeState.activeModsHash
        and type(Registry.state.catalog) == "table" then
        return Registry.state.catalog
    end

    local indexData = IO.loadIndex()
    local valid, reason = IO.validateIndex(indexData, activeState)
    if forceRebuild or not valid then
        if forceRebuild then
            Shared.log("Info", "Forced MS_Items runtime rebuild requested.")
        else
            if reason == "mods" then
                local addedMods, removedMods = Shared.diffActiveMods(indexData and indexData.activeMods or {}, activeState.activeMods)
                local parts = {}
                if #addedMods > 0 then
                    parts[#parts + 1] = "new mods found: " .. table.concat(addedMods, ", ")
                end
                if #removedMods > 0 then
                    parts[#parts + 1] = "removed mods: " .. table.concat(removedMods, ", ")
                end
                local extra = #parts > 0 and (" | " .. table.concat(parts, " | ")) or ""
                Shared.log("Warn", "MS_Items cache invalidated by active mod change; regenerating runtime cache." .. extra)
            else
                Shared.log("Warn", "MS_Items cache invalidated (" .. tostring(reason) .. "); regenerating " .. Registry.OUTPUT_HINT)
            end
        end
        return Runtime.rebuildCache(forceRebuild and "forced" or reason)
    end

    Shared.debugLog("MS_Items cache already valid; loading from " .. Registry.OUTPUT_HINT)
    return populateMasterList(indexData, activeState)
end

return Runtime
