local Shared = require "MarketSense/ItemsRegistry/MS_ItemsRegistry_Shared"
local IO = require "MarketSense/ItemsRegistry/MS_ItemsRegistry_IO"
local Availability = require "MarketSense/MS_ItemAvailability"

local Build = {}
local Registry = Shared.Registry
local Core = Shared.Core
local TagUtils = Shared.TagUtils
local Config = Shared.Config

local GENERIC_FOOD_TAGS = {
    Food = true,
    FoodPerishable = true,
    FoodNonPerishable = true,
}

local function jsonBool(value)
    return value and "true" or "false"
end

local function jsonNumber(value)
    return tostring(tonumber(value) or 0)
end

local function jsonArray(values)
    local parts = {}
    for _, value in ipairs(values or {}) do
        parts[#parts + 1] = Shared.jsonString(value)
    end
    return "[" .. table.concat(parts, ", ") .. "]"
end

local function jsonField(lines, name, value, suffix)
    lines[#lines + 1] = "      " .. Shared.jsonString(name) .. ": " .. value .. (suffix or ",")
end

local function collectFoodAuditEntry(ctx, tagInfo, primary, fileEntry)
    if not GENERIC_FOOD_TAGS[tostring(primary or "")] then
        return nil
    end

    local details = tagInfo and tagInfo.details or {}
    return {
        fullType = ctx.fullType,
        primary = primary,
        path = fileEntry and fileEntry.path or "",
        stage = details.stage or "",
        source = details.source or "",
        reason = details.reason or "",
        displayCategory = ctx.displayCategory,
        itemType = ctx.itemType,
        description = ctx.description,
        foodType = ctx.foodType,
        lootType = ctx.lootType,
        eatType = ctx.eatType,
        isDung = ctx.isDung == true,
        doubleClickRecipe = ctx.doubleClickRecipe,
        replaceOnUse = ctx.replaceOnUse,
        replaceOnCooked = ctx.replaceOnCooked,
        onCooked = ctx.onCooked,
        evolvedRecipe = ctx.evolvedRecipe,
        evolvedRecipeName = ctx.evolvedRecipeName,
        customEatSound = ctx.customEatSound,
        hunger = ctx.hunger,
        thirst = ctx.thirst,
        calories = ctx.calories,
        carbohydrates = ctx.carbohydrates,
        lipids = ctx.lipids,
        proteins = ctx.proteins,
        foodVariantEvidence = ctx.foodVariantEvidence,
        daysFresh = ctx.daysFresh,
        daysRotten = ctx.daysRotten,
        foodDaysFresh = ctx.foodDaysFresh,
        foodDaysRotten = ctx.foodDaysRotten,
        hasFoodNutritionEvidence = ctx.hasFoodNutritionEvidence == true,
        hasFoodSpoilageEvidence = ctx.hasFoodSpoilageEvidence == true,
        hasFoodRecipeEvidence = ctx.hasFoodRecipeEvidence == true,
        isCannedFood = ctx.isCannedFood == true,
        isPackaged = ctx.isPackaged == true,
        isCantEat = ctx.isCantEat == true,
        isCookable = ctx.isCookable == true,
        canAge = ctx.canAge == true,
        instanceCreated = ctx.instanceCreated == true,
        isFoodInstance = ctx.isFoodInstance == true,
        admissionAccepted = details.admissionAccepted == true,
        admissionReason = details.admissionReason or "",
        admissionVetoHits = Shared.copyArray(details.admissionVetoHits or {}),
        admissionSignalHits = Shared.copyArray(details.admissionSignalHits or {}),
        labelCorrectionAction = details.labelCorrectionAction or "",
        labelCorrectionFrom = details.labelCorrectionFrom or "",
        labelCorrectionTo = details.labelCorrectionTo or "",
        labelCorrectionReason = details.labelCorrectionReason or "",
        labelCorrectionHits = Shared.copyArray(details.labelCorrectionHits or {}),
        tags = Shared.copyArray(ctx.normalizedTagList or {}),
    }
end

local function serializeFoodAudit(entries)
    local lines = {
        "{",
        "  \"generatedAt\": " .. Shared.jsonString(Shared.getTimestamp()) .. ",",
        "  \"signatureVersion\": " .. Shared.jsonString(Registry.SIGNATURE_VERSION) .. ",",
        "  \"genericFoodCount\": " .. tostring(#(entries or {})) .. ",",
        "  \"entries\": [",
    }

    for index, entry in ipairs(entries or {}) do
        lines[#lines + 1] = "    {"
        jsonField(lines, "fullType", Shared.jsonString(entry.fullType))
        jsonField(lines, "primary", Shared.jsonString(entry.primary))
        jsonField(lines, "path", Shared.jsonString(entry.path))
        jsonField(lines, "stage", Shared.jsonString(entry.stage))
        jsonField(lines, "source", Shared.jsonString(entry.source))
        jsonField(lines, "reason", Shared.jsonString(entry.reason))
        jsonField(lines, "displayCategory", Shared.jsonString(entry.displayCategory))
        jsonField(lines, "itemType", Shared.jsonString(entry.itemType))
        jsonField(lines, "description", Shared.jsonString(entry.description))
        jsonField(lines, "foodType", Shared.jsonString(entry.foodType))
        jsonField(lines, "lootType", Shared.jsonString(entry.lootType))
        jsonField(lines, "eatType", Shared.jsonString(entry.eatType))
        jsonField(lines, "isDung", jsonBool(entry.isDung))
        jsonField(lines, "doubleClickRecipe", Shared.jsonString(entry.doubleClickRecipe))
        jsonField(lines, "replaceOnUse", Shared.jsonString(entry.replaceOnUse))
        jsonField(lines, "replaceOnCooked", Shared.jsonString(entry.replaceOnCooked))
        jsonField(lines, "onCooked", Shared.jsonString(entry.onCooked))
        jsonField(lines, "evolvedRecipe", Shared.jsonString(entry.evolvedRecipe))
        jsonField(lines, "evolvedRecipeName", Shared.jsonString(entry.evolvedRecipeName))
        jsonField(lines, "customEatSound", Shared.jsonString(entry.customEatSound))
        jsonField(lines, "hunger", jsonNumber(entry.hunger))
        jsonField(lines, "thirst", jsonNumber(entry.thirst))
        jsonField(lines, "calories", jsonNumber(entry.calories))
        jsonField(lines, "carbohydrates", jsonNumber(entry.carbohydrates))
        jsonField(lines, "lipids", jsonNumber(entry.lipids))
        jsonField(lines, "proteins", jsonNumber(entry.proteins))
        local variantEvidence = entry.foodVariantEvidence or {}
        jsonField(lines, "foodVariantStatus", Shared.jsonString(variantEvidence.status))
        jsonField(lines, "foodVariantSource", Shared.jsonString(variantEvidence.sourceFullType))
        jsonField(lines, "foodVariantRelation", Shared.jsonString(variantEvidence.relation))
        jsonField(lines, "foodVariantConfidence", jsonNumber(variantEvidence.confidence))
        jsonField(lines, "foodVariantFields", jsonArray(variantEvidence.fields))
        jsonField(lines, "foodVariantCandidateCount", jsonNumber(#(variantEvidence.candidates or {})))
        jsonField(lines, "foodVariantConflictCount", jsonNumber(#(variantEvidence.conflicts or {})))
        jsonField(lines, "daysFresh", jsonNumber(entry.daysFresh))
        jsonField(lines, "daysRotten", jsonNumber(entry.daysRotten))
        jsonField(lines, "foodDaysFresh", jsonNumber(entry.foodDaysFresh))
        jsonField(lines, "foodDaysRotten", jsonNumber(entry.foodDaysRotten))
        jsonField(lines, "hasFoodNutritionEvidence", jsonBool(entry.hasFoodNutritionEvidence))
        jsonField(lines, "hasFoodSpoilageEvidence", jsonBool(entry.hasFoodSpoilageEvidence))
        jsonField(lines, "hasFoodRecipeEvidence", jsonBool(entry.hasFoodRecipeEvidence))
        jsonField(lines, "isCannedFood", jsonBool(entry.isCannedFood))
        jsonField(lines, "isPackaged", jsonBool(entry.isPackaged))
        jsonField(lines, "isCantEat", jsonBool(entry.isCantEat))
        jsonField(lines, "isCookable", jsonBool(entry.isCookable))
        jsonField(lines, "canAge", jsonBool(entry.canAge))
        jsonField(lines, "instanceCreated", jsonBool(entry.instanceCreated))
        jsonField(lines, "isFoodInstance", jsonBool(entry.isFoodInstance))
        jsonField(lines, "admissionAccepted", jsonBool(entry.admissionAccepted))
        jsonField(lines, "admissionReason", Shared.jsonString(entry.admissionReason))
        jsonField(lines, "admissionVetoHits", jsonArray(entry.admissionVetoHits))
        jsonField(lines, "admissionSignalHits", jsonArray(entry.admissionSignalHits))
        jsonField(lines, "labelCorrectionAction", Shared.jsonString(entry.labelCorrectionAction))
        jsonField(lines, "labelCorrectionFrom", Shared.jsonString(entry.labelCorrectionFrom))
        jsonField(lines, "labelCorrectionTo", Shared.jsonString(entry.labelCorrectionTo))
        jsonField(lines, "labelCorrectionReason", Shared.jsonString(entry.labelCorrectionReason))
        jsonField(lines, "labelCorrectionHits", jsonArray(entry.labelCorrectionHits))
        jsonField(lines, "tags", jsonArray(entry.tags), "")
        lines[#lines + 1] = "    }" .. (index < #entries and "," or "")
    end

    lines[#lines + 1] = "  ]"
    lines[#lines + 1] = "}"
    return table.concat(lines, "\n")
end

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
    else
        local merged = Shared.copyArray(liveData.tags)
        if type(override.addTags) == "table" and #override.addTags > 0 then
            for _, tag in ipairs(override.addTags) do
                merged[#merged + 1] = tostring(tag)
            end
        end

        if type(override.removeTags) == "table" and #override.removeTags > 0 then
            local removeSet = {}
            for _, tag in ipairs(override.removeTags) do
                local text = tostring(tag or "")
                if text ~= "" then
                    removeSet[text] = true
                end
            end

            local filtered = {}
            for _, tag in ipairs(merged) do
                if not removeSet[tostring(tag or "")] then
                    filtered[#filtered + 1] = tag
                end
            end
            merged = filtered
        end

        liveData.tags = TagUtils.unique(merged)
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
        availability = itemData.availability or Availability.get(fullType),
        source = "lean-cache",
    }
end

local function liveItems()
    if type(getAllItems) ~= "function" then return nil end
    return getAllItems()
end

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

local function initializeRuntimeRules()
    local runtimeRules = Shared.ensureRuntimeRules()
    if runtimeRules and runtimeRules.loadFromFile then
        runtimeRules.loadFromFile(false)
    end
    return runtimeRules
end

function Build.getLiveItems()
    return liveItems()
end

function Build.getLiveItemCount()
    return collectionSize(liveItems())
end

function Build.beginGeneration(allItems)
    allItems = allItems or liveItems()
    if allItems == nil then
        return {
            allItems = nil,
            total = 0,
            index = 0,
            generated = {},
            phase = "done",
            done = true,
            invalid = true,
        }
    end

    local job = {
        allItems = allItems,
        total = collectionSize(allItems),
        index = 0,
        generated = {},
        foodAudit = Registry.WRITE_PREBUILD_AUDIT and {} or nil,
        phase = "availability",
        done = false,
        runtimeRules = initializeRuntimeRules(),
    }
    job.availabilityJob = Availability.beginRebuild(allItems)
    return job
end

local function collectOneItem(job, scriptItem)
    local ctx = MarketSense.PropertyReader.buildContext(scriptItem)
    if not ctx or not ctx.fullType or ctx.fullType == "" then return end

    local syntheticSkip, syntheticReason = Shared.shouldSkipSyntheticContext(ctx)
    local availability = Availability.get(ctx.fullType)
    local availabilitySkip = availability.status ~= "obtainable"
    local runtimeRules = job.runtimeRules
    local skip = syntheticSkip
        or availabilitySkip
        or (runtimeRules and runtimeRules.shouldSkip and runtimeRules.shouldSkip(ctx.fullType) or false)
    if skip then
        local reason = syntheticSkip and (syntheticReason or "synthetic")
            or availabilitySkip and (availability.reason or availability.status)
            or "runtime rule"
        Shared.debugLog("Skipped item during MarketSense catalog generation: " .. tostring(ctx.fullType) .. " (" .. tostring(reason) .. ")")
        return
    end

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
    if job.foodAudit then
        local auditEntry = collectFoodAuditEntry(ctx, tagInfo, primary, fileEntry)
        if auditEntry then job.foodAudit[#job.foodAudit + 1] = auditEntry end
    end

    job.generated[ctx.fullType] = {
        item = ctx.fullType,
        basePrice = tonumber(liveData.basePrice) or Shared.getBasePrice(ctx, tagInfo),
        tags = TagUtils.unique(liveData.tags or { primary }),
        stockRange = {
            min = math.max(0, tonumber(liveData.stockRange and liveData.stockRange.min) or 0),
            max = math.max(0, tonumber(liveData.stockRange and liveData.stockRange.max) or 0),
        },
        availability = availability,
        origin = origin,
        root = fileEntry.root,
        category = fileEntry.category,
        subcategory = fileEntry.subcategory,
        leaf = fileEntry.leaf,
        primary = primary,
        primaryPrefix = fileEntry.primaryPrefix,
        path = fileEntry.path,
    }
end

function Build.stepGeneration(job, maxItems, maxMs)
    if type(job) ~= "table" or job.done then return true end
    maxItems = math.max(1, math.floor(tonumber(maxItems) or 1))
    maxMs = tonumber(maxMs)
    local startedAt = maxMs and timestampMs() or nil

    if job.phase == "availability" then
        if not Availability.stepRebuild(job.availabilityJob, maxItems, maxMs) then
            return false
        end
        job.phase = "items"
        return false
    end

    if job.phase == "items" then
        local processed = 0
        while job.index < job.total and not budgetReached(startedAt, maxMs, processed, maxItems) do
            local scriptItem = collectionValue(job.allItems, job.index)
            job.index = job.index + 1
            processed = processed + 1
            if scriptItem ~= nil then
                collectOneItem(job, scriptItem)
            end
        end
        if job.index < job.total then return false end
        if job.foodAudit then
            IO.writeFile(Registry.AUDIT_PATH, serializeFoodAudit(job.foodAudit))
        end
        job.phase = "done"
        job.done = true
        return true
    end

    job.done = true
    return true
end

function Build.collectGeneratedItems()
    local job = Build.beginGeneration()
    while not Build.stepGeneration(job, math.max(1, job.total)) do end
    return job.generated
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
        pricingConfigHash = Shared.buildPricingConfigHash(),
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
