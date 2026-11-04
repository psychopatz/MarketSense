local Shared = require "MarketSense/ItemsRegistry/MS_ItemsRegistry_Shared"

local Query = {}
local Registry = Shared.Registry
local Core = Shared.Core

Query.MAX_RESULTS = 256

local function registryRevision()
    local config = MarketSense and MarketSense.Config or nil
    return math.max(0, math.floor(tonumber(
        config and config.ItemRegistryRevision
    ) or 0))
end

local function availabilityStatus(value)
    if type(value) ~= "table" then return nil end
    return tostring(value.status or "")
end

local function obtainable(value)
    if type(value) ~= "table" then return false end
    if value.obtainable ~= nil then return value.obtainable == true end
    local status = availabilityStatus(value)
    return status == "obtainable" or status == "cached"
end

local function resetIndex()
    Registry.state.queryIndex = {
        revision = registryRevision(),
        all = {},
        byCategory = {},
        obtainable = {},
        obtainableByCategory = {},
        modded = {},
        obtainableModded = {},
        moddedByCategory = {},
        obtainableModdedByCategory = {},
    }
    return Registry.state.queryIndex
end

local function add(list, value)
    list[#list + 1] = value
end

local function buildIndex()
    local revision = registryRevision()
    local state = Registry.state
    local existing = state.queryIndex
    if type(existing) == "table"
        and existing.revision == revision
    then
        return existing
    end

    local index = resetIndex()
    local catalog = state.catalog
    if type(catalog) ~= "table"
        or type(catalog.items) ~= "table"
    then
        return index
    end

    for fullType, entry in pairs(catalog.items) do
        if type(fullType) == "string" and fullType ~= ""
            and type(entry) == "table"
        then
            add(index.all, fullType)
            local category = tostring(entry.category or "")
            if category ~= "" then
                index.byCategory[category] =
                    index.byCategory[category] or {}
                add(index.byCategory[category], fullType)
            end
            local isModded = tostring(entry.sourceModId or "")
                ~= "Vanilla"
                and tostring(entry.sourceModId or "") ~= ""
            if isModded then
                add(index.modded, fullType)
                if category ~= "" then
                    index.moddedByCategory[category] =
                        index.moddedByCategory[category] or {}
                    add(index.moddedByCategory[category], fullType)
                end
            end
            if obtainable(entry.availability) then
                add(index.obtainable, fullType)
                if isModded then
                    add(index.obtainableModded, fullType)
                    if category ~= "" then
                        index.obtainableModdedByCategory[category] =
                            index.obtainableModdedByCategory[category] or {}
                        add(index.obtainableModdedByCategory[category], fullType)
                    end
                end
                if category ~= "" then
                    index.obtainableByCategory[category] =
                        index.obtainableByCategory[category] or {}
                    add(index.obtainableByCategory[category], fullType)
                end
            end
        end
    end

    table.sort(index.all)
    table.sort(index.obtainable)
    table.sort(index.modded)
    table.sort(index.obtainableModded)
    for _, rows in pairs(index.byCategory) do table.sort(rows) end
    for _, rows in pairs(index.obtainableByCategory) do
        table.sort(rows)
    end
    for _, rows in pairs(index.moddedByCategory) do
        table.sort(rows)
    end
    for _, rows in pairs(index.obtainableModdedByCategory) do
        table.sort(rows)
    end
    return index
end

local function descriptor(entry, includeTags)
    local result = {
        fullType = entry.fullType,
        moduleName = entry.moduleName,
        typeName = entry.typeName,
        sourceModId = entry.sourceModId,
        category = entry.category,
        primary = entry.primary,
        availability = type(entry.availability) == "table"
            and {
                status = entry.availability.status,
                obtainable = obtainable(entry.availability),
            }
            or nil,
    }
    if includeTags == true then
        result.tags = Core.deepCopy(entry.tags or {})
        result.expandedTags = Core.deepCopy(entry.expandedTags or {})
    end
    return result
end

function Query.isReady()
    if type(Registry.ensureLoaded) == "function" then
        Registry.ensureLoaded(false)
    end
    local state = Registry.state or {}
    return state.loaded == true
        and state.stale ~= true
        and type(state.catalog) == "table"
        and type(state.catalog.items) == "table"
end

function Query.getRevision()
    return registryRevision()
end

function Query.get(fullType, options)
    if type(fullType) ~= "string" or fullType == "" then
        return nil, "item_required"
    end
    if not Query.isReady() then
        return nil, "catalog_not_ready"
    end
    local catalog = Registry.state.catalog
    local entry = catalog.items[fullType]
    if type(entry) ~= "table" then return nil, "item_not_found" end
    options = type(options) == "table" and options or {}
    return descriptor(entry, options.includeTags == true)
end

function Query.query(options)
    options = type(options) == "table" and options or {}
    if not Query.isReady() then
        return {}, "catalog_not_ready"
    end

    local limit = math.max(1, math.min(
        Query.MAX_RESULTS,
        math.floor(tonumber(options.limit) or 32)
    ))
    local offset = math.max(
        0,
        math.floor(tonumber(options.offset) or 0)
    )
    local category = options.category
        and tostring(options.category) or nil
    if category == "" then category = nil end
    local obtainableOnly = options.obtainableOnly == true
    local moddedOnly = options.moddedOnly == true

    local index = buildIndex()
    local rows
    if category and moddedOnly then
        local source = obtainableOnly
            and (index.obtainableByCategory[category] or {})
            or (index.byCategory[category] or {})
        rows = {}
        local catalog = Registry.state.catalog
        for _, fullType in ipairs(source) do
            local entry = catalog.items[fullType]
            if entry and tostring(entry.sourceModId or "") ~= "Vanilla"
                and tostring(entry.sourceModId or "") ~= ""
            then
                rows[#rows + 1] = fullType
            end
        end
    elseif moddedOnly and obtainableOnly then
        rows = index.obtainableModded
    elseif moddedOnly then
        rows = index.modded
    elseif category and obtainableOnly then
        rows = index.obtainableByCategory[category] or {}
    elseif category then
        rows = index.byCategory[category] or {}
    elseif obtainableOnly then
        rows = index.obtainable
    else
        rows = index.all
    end

    local catalog = Registry.state.catalog
    local output = {}
    local startIndex = offset + 1
    local endIndex = math.min(#rows, offset + limit)
    for indexValue = startIndex, endIndex do
        local fullType = rows[indexValue]
        local entry = catalog.items[fullType]
        if type(entry) == "table" then
            output[#output + 1] =
                descriptor(entry, options.includeTags == true)
        end
    end

    return output, nil, {
        revision = index.revision,
        total = #rows,
        offset = offset,
        limit = limit,
        nextOffset = endIndex < #rows and endIndex or nil,
    }
end

function Query.invalidate()
    Registry.state.queryIndex = nil
end

return Query
