local T = require "tests/support/test"
T.addPackagePaths()

_G.unpack = _G.unpack or table.unpack
_G.getFileReader = function() return nil end
_G.getFileWriter = function()
    return {
        write = function() end,
        close = function() end,
    }
end

local api = assert(require "MarketSense/MS_PublicAPI")
local registry = assert(MarketSense.ItemsRegistry)

local items = {}
for index = 1, 4412 do
    local fullType = string.format("Mod.Item%04d", index)
    local category = index % 2 == 0 and "Food" or "Tool"
    items[fullType] = {
        fullType = fullType,
        moduleName = "Mod",
        typeName = string.format("Item%04d", index),
        sourceModId = index == 4300 and "WorkshopMod" or "Vanilla",
        category = category,
        primary = category,
        tags = { category },
        expandedTags = { category },
        availability = {
            status = "obtainable",
            obtainable = true,
        },
    }
end

MarketSense.Config.ItemRegistryRevision = 100
MarketSense.ItemRuntimeConfig.pricingRevision = 7
registry.state.loaded = true
registry.state.stale = false
registry.state.catalog = {
    items = items,
    total = 4412,
}
registry.ensureLoaded = function()
    return registry.state.catalog
end
registry.invalidateQuery()

T.truthy(api.IsCatalogReady(), "catalog query reports ready")
T.equal(api.GetCatalogRevision(), 100, "catalog revision exposed")
T.equal(api.GetPricingRevision(), 7, "pricing revision exposed")

local first, reason, page = api.QueryItems({
    category = "Food",
    obtainableOnly = true,
    limit = 64,
})
T.equal(reason, nil, "bounded query reason")
T.equal(#first, 64, "bounded category query limit")
T.equal(page.total, 2206, "query sees entries beyond 4096")
T.equal(page.revision, 100, "query page revision")
T.truthy(page.nextOffset ~= nil, "bounded query exposes continuation")
for _, row in ipairs(first) do
    T.equal(row.category, "Food", "category filter")
    T.truthy(row.availability and row.availability.obtainable,
        "obtainable filter")
    T.equal(row.tags, nil, "tags omitted unless requested")
end

local second = api.QueryItems({
    category = "Food",
    obtainableOnly = true,
    limit = 64,
    offset = page.nextOffset,
})
T.equal(#second, 64, "continuation query")
T.truthy(second[1].fullType > first[#first].fullType,
    "query order is deterministic")

local tagged = api.QueryItems({
    category = "Tool",
    limit = 1,
    includeTags = true,
})
T.equal(tagged[1].tags[1], "Tool",
    "tags included only on request")

local exact = assert(api.GetCatalogItem("Mod.Item4412"))
T.equal(exact.fullType, "Mod.Item4412",
    "exact lookup reaches item beyond former DT cap")

local modded = api.QueryItems({
    obtainableOnly = true,
    moddedOnly = true,
    limit = 8,
})
T.equal(#modded, 1,
    "canonical modded query is independent of catalog position")
T.equal(modded[1].fullType, "Mod.Item4300",
    "modded query reaches item beyond former 4096 boundary")

items["Zed.NewItem"] = {
    fullType = "Zed.NewItem",
    moduleName = "Zed",
    typeName = "NewItem",
    sourceModId = "TestMod",
    category = "Food",
    primary = "Food",
    availability = {
        status = "obtainable",
        obtainable = true,
    },
}
registry.state.catalog.total = 4413
MarketSense.Config.ItemRegistryRevision = 101

local revised, revisedReason, revisedPage = api.QueryItems({
    category = "Food",
    obtainableOnly = true,
    limit = 256,
    offset = 2048,
})
T.equal(revisedReason, nil, "revised query reason")
T.equal(revisedPage.revision, 101,
    "query index follows canonical registry revision")
T.equal(revisedPage.total, 2207,
    "revised query sees newly added canonical item")

registry.state.stale = true
local unavailable, unavailableReason = api.QueryItems({ limit = 8 })
T.equal(#unavailable, 0, "stale catalog returns no query rows")
T.equal(unavailableReason, "catalog_not_ready",
    "stale catalog fails boundedly")
registry.state.stale = false

T.finish("marketsense_catalog_query_smoke")
