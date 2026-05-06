local Shared = require "MarketSense/ItemsRegistry/MS_ItemsRegistry_Shared"
local IO = require "MarketSense/ItemsRegistry/MS_ItemsRegistry_IO"

local Build = {}
local Registry = Shared.Registry
local Core = Shared.Core
local TagUtils = Shared.TagUtils
local Config = Shared.Config

function Build.applyRuntimeOverride(fullType, data, runtimeRules)
    local liveData = {
        item = fullType,
        basePrice = tonumber(data.basePrice) or (Config.pricing.minPrice or 1),
        tags = Shared.copyArray(data.tags or {}),
        stockRange = {
            min = math.max(0, tonumber(data.stockRange and data.stockRange.min) or 0),
            max = math.max(0, tonumber(data.stockRange and data.stockRange.max) or 0),
        },
    }

    if not runtimeRules or type(runtimeRules.getOverride) ~= "function" then
        return liveData
    end

    local override = runtimeRules.getOverride(fullType)
    if type(override) ~= "table" then
        return liveData
    end

    if type(override.tags) == "table" and #override.tags > 0 then
        liveData.tags = TagUtils.unique(override.tags)
    end

    if type(override.price) == "number" then
        liveData.basePrice = math.max(Config.pricing.minPrice or 1, Core.round(override.price))
    end

    if type(override.stock) == "table" then
        if override.stock.min ~= nil then
            liveData.stockRange.min = math.max(0, math.floor(tonumber(override.stock.min) or 0))
        end
        if override.stock.max ~= nil then
            liveData.stockRange.max = math.max(0, math.floor(tonumber(override.stock.max) or 0))
        end
        if liveData.stockRange.min > liveData.stockRange.max then
            liveData.stockRange.min = liveData.stockRange.max
        end
    end

    return liveData
end

function Build.buildLiveEntry(fullType, itemData, sourceOrigin, category, primary)
    local moduleName, typeName = Core.splitFullType(fullType)
    local effectiveBasePrice = tonumber(itemData.basePrice) or (Config.pricing.minPrice or 1)
    if DynamicTrading.PriceConfig and DynamicTrading.PriceConfig.GetEffectiveBasePrice then
        effectiveBasePrice = DynamicTrading.PriceConfig.GetEffectiveBasePrice(fullType, itemData)
    end

    local expandedTags = TagUtils.expandHierarchy(itemData.tags or {})
    return {
        fullType = fullType,
        moduleName = moduleName,
        typeName = typeName,
        sourceModId = sourceOrigin or moduleName,
        sourceModName = sourceOrigin == "Vanilla" and "Project Zomboid (Vanilla)" or tostring(sourceOrigin or moduleName),
        category = category or TagUtils.categoryFromPrimary(primary or Shared.getPrimaryTag(itemData.tags)),
        primary = primary or Shared.getPrimaryTag(itemData.tags),
        tags = Shared.copyArray(itemData.tags or {}),
        expandedTags = expandedTags,
        basePrice = tonumber(itemData.basePrice) or 0,
        price = tonumber(effectiveBasePrice) or 0,
        rawScore = tonumber(itemData.basePrice) or 0,
        confidence = 1,
        stock = {
            min = math.max(0, tonumber(itemData.stockRange and itemData.stockRange.min) or 0),
            max = math.max(0, tonumber(itemData.stockRange and itemData.stockRange.max) or 0),
        },
        source = "lean-cache",
    }
end

function Build.collectGeneratedItems()
    local runtimeRules = Shared.ensureRuntimeRules()
    if runtimeRules and runtimeRules.loadFromFile then
        runtimeRules.loadFromFile(false)
    end

    local ok, allItems = pcall(function()
        return getAllItems and getAllItems() or nil
    end)

    if not ok or allItems == nil then
        return {}
    end

    local generated = {}
    for index = 0, allItems:size() - 1 do
        local scriptItem = allItems:get(index)
        local ctx = MarketSense.PropertyReader.buildContext(scriptItem)
        if ctx and ctx.fullType and ctx.fullType ~= "" then
            local syntheticSkip, syntheticReason = Shared.shouldSkipSyntheticContext(ctx)
            local skip = syntheticSkip or (runtimeRules and runtimeRules.shouldSkip and runtimeRules.shouldSkip(ctx.fullType) or false)
            if not skip then
                local tagInfo = MarketSense.AutoTag.generate(ctx)
                local baseData = {
                    item = ctx.fullType,
                    basePrice = Shared.getBasePrice(ctx, tagInfo),
                    tags = TagUtils.unique(tagInfo.tags or { tagInfo.primary }),
                    stockRange = Shared.getBaseStock(ctx),
                }
                local liveData = Build.applyRuntimeOverride(ctx.fullType, baseData, runtimeRules)
                local primary = Shared.getPrimaryTag(liveData.tags)
                local fileEntry = Shared.toFileEntry(primary, liveData.tags)
                local origin = Shared.getOriginFromContext(ctx)

                generated[ctx.fullType] = {
                    item = ctx.fullType,
                    basePrice = tonumber(liveData.basePrice) or Shared.getBasePrice(ctx, tagInfo),
                    tags = TagUtils.unique(liveData.tags or { primary }),
                    stockRange = {
                        min = math.max(0, tonumber(liveData.stockRange and liveData.stockRange.min) or 0),
                        max = math.max(0, tonumber(liveData.stockRange and liveData.stockRange.max) or 0),
                    },
                    origin = origin,
                    root = fileEntry.root,
                    category = fileEntry.category,
                    subcategory = fileEntry.subcategory,
                    leaf = fileEntry.leaf,
                    primary = primary,
                    primaryPrefix = fileEntry.primaryPrefix,
                    path = fileEntry.path,
                }
            elseif syntheticSkip then
                Shared.debugLog("Skipped synthetic/invalid item during DT_Items generation: " .. tostring(ctx.fullType) .. " (" .. tostring(syntheticReason or "synthetic") .. ")")
            end
        end
    end

    return generated
end

function Build.mergeStoredAndGenerated(storedItems, generatedItems, activeState)
    local merged = {}

    for fullType, entry in pairs(storedItems or {}) do
        if not Shared.isOriginActive(entry.origin, activeState.activeModSet) then
            merged[fullType] = entry
        end
    end

    for fullType, entry in pairs(generatedItems or {}) do
        merged[fullType] = entry
    end

    return merged
end

function Build.groupForWrite(itemsByFullType)
    local grouped = {}

    for fullType, entry in pairs(itemsByFullType or {}) do
        local fileEntry = Shared.toFileEntry(entry.primary, entry.tags)
        local path = entry.path or fileEntry.path
        local root = entry.root or fileEntry.root or fileEntry.category
        local category = entry.category or fileEntry.category
        local subcategory = entry.subcategory or fileEntry.subcategory
        local leaf = entry.leaf or fileEntry.leaf or "General"
        local primaryPrefix = entry.primaryPrefix or fileEntry.primaryPrefix or entry.primary

        grouped[path] = grouped[path] or {
            root = root,
            category = category,
            subcategory = subcategory,
            leaf = leaf,
            primaryPrefix = primaryPrefix,
            groups = {},
        }

        local groupKey = tostring(entry.origin or "Vanilla") .. "\31" .. Shared.join(entry.tags or {}, "|")
        local bucket = grouped[path].groups[groupKey]
        if not bucket then
            bucket = {
                origin = entry.origin or "Vanilla",
                tags = TagUtils.unique(entry.tags or {}),
                items = {},
            }
            grouped[path].groups[groupKey] = bucket
        end

        bucket.items[#bucket.items + 1] = {
            item = fullType,
            basePrice = tonumber(entry.basePrice) or (Config.pricing.minPrice or 1),
            stockMin = tonumber(entry.stockRange and entry.stockRange.min) or 0,
            stockMax = tonumber(entry.stockRange and entry.stockRange.max) or 0,
        }
    end

    return grouped
end

function Build.writeGroupedFiles(grouped, activeState, sourceManifestHash)
    local timestamp = Shared.getTimestamp()
    local files = {}

    for path, payload in pairs(grouped or {}) do
        local content = {
            "# schema=" .. Registry.FILE_SCHEMA,
            "# root=" .. tostring(payload.root or payload.category or "Misc"),
            "# category=" .. tostring(payload.category or "Misc"),
            "# subcategory=" .. tostring(payload.subcategory or "General"),
            "# leaf=" .. tostring(payload.leaf or "General"),
            "# primaryPrefix=" .. tostring(payload.primaryPrefix or ((payload.category or "Misc") .. "." .. (payload.subcategory or "General") .. "." .. (payload.leaf or "General"))),
            "# generatedAt=" .. timestamp,
            "",
        }

        local keys = {}
        for groupKey in pairs(payload.groups or {}) do
            keys[#keys + 1] = groupKey
        end
        table.sort(keys)

        for _, groupKey in ipairs(keys) do
            local group = payload.groups[groupKey]
            table.sort(group.items, function(left, right)
                return tostring(left.item) < tostring(right.item)
            end)

            content[#content + 1] = "@origin=" .. tostring(group.origin or "Vanilla")
            content[#content + 1] = "@tags=" .. Shared.join(group.tags or {}, "|")
            for _, row in ipairs(group.items) do
                content[#content + 1] = tostring(row.item) ..
                    "|" .. tostring(Core.round(row.basePrice or 0)) ..
                    "|" .. tostring(math.max(0, math.floor(row.stockMin or 0))) ..
                    "|" .. tostring(math.max(0, math.floor(row.stockMax or 0)))
            end
            content[#content + 1] = ""
        end

        local ok = IO.writeFile(Registry.ROOT_FOLDER .. "/" .. path, table.concat(content, "\r\n"))
        if ok then
            files[#files + 1] = {
                root = payload.root or payload.category,
                category = payload.category,
                subcategory = payload.subcategory,
                leaf = payload.leaf,
                primaryPrefix = payload.primaryPrefix,
                path = path,
            }
        end
    end

    IO.sortFileEntries(files)

    local indexData = {
        schemaVersion = Registry.SCHEMA_VERSION,
        generatedAt = timestamp,
        activeModsHash = activeState.activeModsHash,
        generatorVersion = Registry.GENERATOR_VERSION,
        signatureVersion = Registry.SIGNATURE_VERSION,
        pricingHeuristicVersion = Registry.PRICING_HEURISTIC_VERSION,
        gameVersion = activeState.gameVersion,
        sourceManifestHash = tostring(sourceManifestHash or Shared.stableHash({
            tostring(activeState and activeState.activeModsHash or ""),
            tostring(timestamp),
        })),
        activeMods = Shared.copyArray(activeState.activeMods),
        files = files,
    }

    IO.writeFile(Registry.INDEX_PATH, IO.serializeIndex(indexData))
    return indexData
end

return Build
