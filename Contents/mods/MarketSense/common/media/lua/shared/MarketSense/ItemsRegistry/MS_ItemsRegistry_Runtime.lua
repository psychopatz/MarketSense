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

local function cachedAvailability(fullType, stale)
    return {
        fullType = fullType,
        status = stale and "stale_cache" or "cached",
        obtainable = true,
        confidence = 0,
        channels = {},
        references = {},
        exclusions = {},
        engineSignals = {},
        reason = stale and "using the previous runtime cache while live data is loading"
            or "using persisted runtime acquisition data",
        source = "MS_Items persisted cache",
    }
end

local function populateMasterList(indexData, activeState, options)
    options = options or {}
    local cacheOnly = options.cacheOnly == true
    local stale = options.stale == true
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
        pricingConfigHash = Shared.buildPricingConfigHash(),
        intrinsicConfigHash = Shared.buildIntrinsicConfigHash(),
        pricingPolicyHash = Shared.buildPricingConfigHash(),
        generatedAt = indexData and indexData.generatedAt or nil,
        source = cacheOnly and (stale and "stale-lean-cache" or "lean-cache") or "live-cache",
        stale = stale,
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
                            local availability = cacheOnly
                                and cachedAvailability(fullType, stale)
                                or Availability.get(fullType)
                            if availability.status ~= "obtainable" then
                                skip = skip or not cacheOnly
                            end
                            if not skip then
                                local baseData = {
                                    item = fullType,
                                    intrinsicScore = tonumber(row[2]) or (Config.pricing.minPrice or 1),
                                    basePrice = tonumber(row[2]) or (Config.pricing.minPrice or 1),
                                    rawScore = tonumber(row[2]) or (Config.pricing.minPrice or 1),
                                    tags = Shared.copyArray(baseTags),
                                    stockRange = {
                                        min = math.max(0, tonumber(row[3]) or 0),
                                        max = math.max(0, tonumber(row[4]) or 0),
                                    },
                                    vesselPricing = Shared.Core.deepCopy(row[5]),
                                    isActualLiquid = row[6] == true,
                                    foodState = row[7],
                                }

                                local liveData = Build.applyRuntimeOverride(fullType, baseData, runtimeRules)
                                liveData.availability = availability
                                local liveEntry = Build.buildLiveEntry(fullType, liveData, group.origin, nil, nil)
                                registerLiveItem(fullType, liveEntry)
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
    Registry.state.pricingConfigHash = catalog.pricingConfigHash
    Registry.state.intrinsicConfigHash = catalog.intrinsicConfigHash
    Registry.state.pricingPolicyHash = catalog.pricingPolicyHash
    Registry.state.catalog = catalog
    Registry.state.lastIndex = indexData
    Registry.state.stale = stale
    Registry.state.knownSnapshot = nil

    return catalog
end

-- Sandbox and modifier policy changes only require this O(n) arithmetic pass.
-- The persisted intrinsic rows remain valid and no PropertyReader/AutoTag
-- work is repeated.
function Runtime.refreshCatalogPrices()
    local catalog = Registry.state.catalog
    if type(catalog) ~= "table" or type(catalog.items) ~= "table" then
        return false
    end

    local policyHash = Shared.buildPricingConfigHash()
    if Registry.state.pricingPolicyHash == policyHash then return false end

    for fullType, entry in pairs(catalog.items) do
        local details = Shared.Pricing.finalizeIntrinsicSnapshot
            and Shared.Pricing.finalizeIntrinsicSnapshot(entry, false) or nil
        if type(details) == "table" then
            entry.price = tonumber(details.price) or entry.price or 0
            entry.pricingSource = details.source or "intrinsic-cache"
            local masterList = MarketSense.Config and MarketSense.Config.MasterList
            if type(masterList) == "table" and type(masterList[fullType]) == "table" then
                masterList[fullType].price = entry.price
                masterList[fullType].pricingSource = entry.pricingSource
            end
        end
    end

    catalog.pricingConfigHash = policyHash
    catalog.pricingPolicyHash = policyHash
    Registry.state.pricingConfigHash = policyHash
    Registry.state.pricingPolicyHash = policyHash
    Registry.state.knownSnapshot = nil
    return true
end

function Runtime.loadCatalogFromCache()
    local activeState = Shared.buildActiveModState()
    local indexData = IO.loadIndex()
    local valid, reason = IO.validateIndex(indexData, activeState)
    if not valid then
        Shared.debugLog("Cache load skipped because index validation failed: " .. tostring(reason))
        return nil
    end
    Shared.debugLog("Loading MS_Items cache from " .. Registry.OUTPUT_HINT .. " using hash " .. tostring(activeState.activeModsHash))
    return populateMasterList(indexData, activeState, { cacheOnly = true })
end

local function prepareRebuild()
    local runtimeRules = Shared.ensureRuntimeRules()
    if runtimeRules and runtimeRules.reset then
        runtimeRules.reset()
        runtimeRules.loaded = false
    end

    -- A registry rebuild can be the first evaluation after PZ finishes
    -- loading craft recipes.  Never let a resolver index built during an
    -- earlier, partially initialized phase survive into this pass.
    if MarketSense.YieldResolver and type(MarketSense.YieldResolver.clear) == "function" then
        MarketSense.YieldResolver.clear()
    end
end

local function persistGeneratedItems(generatedItems, reason, activeState, previousIndex)
    local rebuildReason = tostring(reason or "rebuild")
    activeState = activeState or Shared.buildActiveModState()
    previousIndex = previousIndex or IO.loadIndex()

    Shared.log("Info", "Rebuilding MS_Items runtime cache (" .. rebuildReason .. ") from live item data.")
    Shared.debugLog("Active mods hash: " .. tostring(activeState.activeModsHash))

    if not Shared.hasEntries(generatedItems) then
        Shared.log("Warn", "Runtime cache rebuild produced no live items. Falling back to the previous cache if available.")
        IO.writeRebuildRequest(rebuildReason, activeState, previousIndex, "Runtime rebuild produced no items and kept the previous MS_Items cache if one was available.")
        if previousIndex and type(previousIndex.files) == "table" and #previousIndex.files > 0 then
            local fallback = populateMasterList(previousIndex, activeState, {
                cacheOnly = true,
                stale = true,
            })
            -- This is a temporary view, not a successful rebuild.  PZ can
            -- call the registry before getAllItems() is ready; keeping the
            -- loaded flag set here would make Refresh catalog reuse the old
            -- cache forever and require the manual Generate button.
            Registry.state.loaded = false
            Registry.state.deferredRebuild = true
            return fallback, false
        end
        Registry.state.loaded = false
        Registry.state.deferredRebuild = true
        Registry.state.stale = true
        return Shared.buildEmptyCatalog(activeState, "runtime-rebuild-empty"), false
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
            return populateMasterList(previousIndex, activeState, {
                cacheOnly = true,
                stale = true,
            }), false
        end
        return Shared.buildEmptyCatalog(activeState, "runtime-rebuild-grouping-failed"), false
    end

    local sourceManifestHash = Shared.buildSourceManifestHash(mergedItems, activeState)
    local indexData = Build.writeGroupedFiles(grouped, activeState, sourceManifestHash)
    if type(indexData) ~= "table" or type(indexData.files) ~= "table" or #indexData.files == 0 then
        Shared.log("Warn", "Runtime cache rebuild could not persist MS_Items files. Falling back to the previous cache if available.")
        IO.writeRebuildRequest(rebuildReason, activeState, previousIndex, "Runtime rebuild failed while writing MS_Items files.")
        if previousIndex and type(previousIndex.files) == "table" and #previousIndex.files > 0 then
            return populateMasterList(previousIndex, activeState, {
                cacheOnly = true,
                stale = true,
            }), false
        end
        return Shared.buildEmptyCatalog(activeState, "runtime-rebuild-write-failed"), false
    end

    Registry.state.lastRequestKey = nil
    Registry.state.deferredRebuild = false
    Registry.state.stale = false
    Shared.log("Info", "Rebuilt MS_Items runtime cache with " .. tostring(#indexData.files) .. " files for " .. tostring(activeState.activeModsHash) .. ".")
    return populateMasterList(indexData, activeState, { cacheOnly = true }), true
end

function Runtime.rebuildCache(reason)
    Runtime.cancelPendingRebuild()
    prepareRebuild()
    local generatedItems = Build.collectGeneratedItems()
    local activeState = Shared.buildActiveModState()
    local previousIndex = IO.loadIndex()
    local result = persistGeneratedItems(generatedItems, reason, activeState, previousIndex)
    return result
end

local function removeRebuildHandler()
    local handler = Registry.state.rebuildHandler
    if handler and Events and Events.OnTick and type(Events.OnTick.Remove) == "function" then
        Events.OnTick.Remove(handler)
    end
    Registry.state.rebuildHandler = nil
    Registry.state.rebuildScheduled = false
end

function Runtime.cancelPendingRebuild()
    removeRebuildHandler()
    Registry.state.rebuildPending = false
    Registry.state.rebuildInProgress = false
    Registry.state.rebuildJob = nil
    Registry.state.rebuildReason = nil
    Registry.state.readyProbeCount = 0
    Registry.state.lastReadyItemCount = nil
end

local function liveDataReady()
    local itemCount = Build.getLiveItemCount and Build.getLiveItemCount() or 0
    if itemCount <= 0 then
        Registry.state.readyProbeCount = 0
        Registry.state.lastReadyItemCount = nil
        return false
    end

    local manager = nil
    if type(getScriptManager) == "function" then
        manager = getScriptManager()
    end
    if not manager and ScriptManager and ScriptManager.instance then
        manager = ScriptManager.instance
    end
    local managerReady = manager ~= nil
        and (type(manager.getAllCraftRecipes) == "function"
            or type(manager.getAllRecipes) == "function")
    if not managerReady then
        Registry.state.readyProbeCount = 0
        return false
    end

    if Registry.state.lastReadyItemCount == itemCount then
        Registry.state.readyProbeCount = (Registry.state.readyProbeCount or 0) + 1
    else
        Registry.state.lastReadyItemCount = itemCount
        Registry.state.readyProbeCount = 1
    end

    return Registry.state.readyProbeCount >= Registry.REBUILD_READY_STABLE_TICKS
end

local function runScheduledRebuild()
    if not Registry.state.rebuildPending then
        removeRebuildHandler()
        return
    end

    if not Registry.state.rebuildInProgress then
        if not liveDataReady() then return end

        prepareRebuild()
        local allItems = Build.getLiveItems and Build.getLiveItems() or nil
        local job = Build.beginGeneration(allItems)
        if job.invalid then
            Registry.state.readyProbeCount = 0
            Registry.state.lastReadyItemCount = nil
            return
        end
        job.reason = Registry.state.rebuildReason or "deferred"
        job.activeState = Shared.buildActiveModState()
        job.previousIndex = IO.loadIndex()
        Registry.state.rebuildJob = job
        Registry.state.rebuildInProgress = true
    end

    local job = Registry.state.rebuildJob
    local done = Build.stepGeneration(job,
        Registry.REBUILD_ITEMS_PER_TICK, Registry.REBUILD_BUDGET_MS)
    if not done then return end

    Registry.state.rebuildInProgress = false
    Registry.state.rebuildJob = nil
    local liveCount = Build.getLiveItemCount and Build.getLiveItemCount() or job.total
    if liveCount ~= job.total then
        -- The live Java collection changed while the job was running. Never
        -- persist a partial catalog; wait for another stable readiness probe.
        Shared.log("Warn", "Discarding MS_Items rebuild because live item count changed from "
            .. tostring(job.total) .. " to " .. tostring(liveCount) .. ".")
        Registry.state.rebuildPending = true
        Registry.state.deferredRebuild = true
        Registry.state.readyProbeCount = 0
        Registry.state.lastReadyItemCount = nil
        return
    end
    local catalog, success = persistGeneratedItems(
        job.generated,
        job.reason,
        Shared.buildActiveModState(),
        job.previousIndex
    )

    if success then
        Registry.state.rebuildPending = false
        Registry.state.deferredRebuild = false
        Registry.state.rebuildReason = nil
        Registry.state.stale = false
        Shared.log("Info", "Completed deferred MS_Items rebuild with "
            .. tostring(catalog and catalog.total or 0) .. " items.")
        removeRebuildHandler()
    else
        -- Keep the old snapshot visible and retry after another stable probe.
        Registry.state.rebuildPending = true
        Registry.state.deferredRebuild = true
        Registry.state.readyProbeCount = 0
        Registry.state.lastReadyItemCount = nil
    end
end

function Runtime.scheduleRebuild(reason)
    Registry.state.rebuildPending = true
    Registry.state.deferredRebuild = true
    Registry.state.rebuildReason = tostring(reason or "deferred")
    if Registry.state.rebuildScheduled then return true end
    if not Events or not Events.OnTick or type(Events.OnTick.Add) ~= "function" then
        return false
    end

    local handler
    handler = function()
        runScheduledRebuild()
    end
    Registry.state.rebuildHandler = handler
    Registry.state.rebuildScheduled = true
    Events.OnTick.Add(handler)
    return true
end

function Runtime.ensureLoaded(forceRebuild)
    local activeState = Shared.buildActiveModState()
    if forceRebuild then
        Shared.log("Info", "Forced MS_Items runtime rebuild requested.")
        return Runtime.rebuildCache("forced")
    end

    if Registry.state.loaded
        and Registry.state.activeModsHash == activeState.activeModsHash
        and Registry.state.intrinsicConfigHash == Shared.buildIntrinsicConfigHash()
        and type(Registry.state.catalog) == "table" then
        Runtime.refreshCatalogPrices()
        if Registry.state.rebuildPending then
            Runtime.scheduleRebuild(Registry.state.rebuildReason or "deferred")
        end
        return Registry.state.catalog
    end

    local indexData = IO.loadIndex()
    local valid, reason = IO.validateIndex(indexData, activeState)
    if valid then
        Shared.debugLog("MS_Items cache already valid; loading from " .. Registry.OUTPUT_HINT)
        local rebuilding = Registry.state.rebuildPending == true
        if not rebuilding then
            Registry.state.deferredRebuild = false
            Registry.state.stale = false
        end
        local catalog = populateMasterList(indexData, activeState, {
            cacheOnly = true,
            stale = rebuilding,
        })
        if rebuilding then Runtime.scheduleRebuild(Registry.state.rebuildReason or "deferred") end
        return catalog
    end

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
        Shared.log("Warn", "MS_Items cache invalidated by active mod change; scheduling runtime rebuild." .. extra)
    else
        Shared.log("Warn", "MS_Items cache invalidated (" .. tostring(reason) .. "); scheduling a nonblocking rebuild.")
    end

    if type(indexData) == "table" and type(indexData.files) == "table" and #indexData.files > 0 then
        -- Keep the previous catalog usable while the live PZ tables settle.
        -- It is explicitly marked stale and is never used as final live price
        -- data by the pricing API.
        populateMasterList(indexData, activeState, {
            cacheOnly = true,
            stale = true,
        })
    else
        Registry.state.catalog = Shared.buildEmptyCatalog(activeState, "runtime-cache-pending")
        Registry.state.loaded = true
        Registry.state.activeModsHash = activeState.activeModsHash
        Registry.state.pricingConfigHash = Shared.buildPricingConfigHash()
        Registry.state.intrinsicConfigHash = Shared.buildIntrinsicConfigHash()
        Registry.state.pricingPolicyHash = Shared.buildPricingConfigHash()
        Registry.state.stale = true
    end

    Runtime.scheduleRebuild(reason or "invalid-cache")
    return Registry.state.catalog
end

return Runtime
