local T = require "tests/support/test"
T.addPackagePaths()

_G.unpack = _G.unpack or table.unpack
local runtimeRules = assert(T.load("MarketSense/MS_RuntimeRules.lua"))
local shared = assert(T.load("MarketSense/ItemsRegistry/MS_ItemsRegistry_Shared.lua"))
local ioLayer = assert(T.load("MarketSense/ItemsRegistry/MS_ItemsRegistry_IO.lua"))
local availability = assert(T.load("MarketSense/MS_ItemAvailability.lua"))
local build = assert(T.load("MarketSense/ItemsRegistry/MS_ItemsRegistry_Build.lua"))

T.equal(shared.Registry.FILE_SCHEMA, "MS_ITEMS_V2", "standalone cache schema")
T.equal(shared.Registry.ROOT_FOLDER, "MS_Items", "standalone cache folder")
T.falsy(shared.Registry.WRITE_PREBUILD_AUDIT,
    "prebuild JSON audit is opt-in; TXT remains the runtime catalog")

T.truthy(runtimeRules.apply({
    overridesById = {
        ["Base.HarnessRule"] = { price = 42, stock = { min = 2, max = 5 } },
    },
}), "runtime rule application")
local override = assert(runtimeRules.getOverride("Base.HarnessRule"))
T.equal(override.price, 42, "runtime price override")
T.equal(override.stock.min, 2, "runtime stock override")
T.equal(override.stock.max, 5, "runtime stock override max")

T.truthy(runtimeRules.apply({
    overridesById = {
        ["Base.HarnessMinPrice"] = { minPrice = 42 },
    },
}), "runtime minimum-price override application")
T.equal(runtimeRules.getOverride("Base.HarnessMinPrice").minPrice, 42,
    "minimum-price override survives normalization")

local generated = build.applyRuntimeOverride("Base.HarnessGenerated", {
    basePrice = 12,
    tags = { "Misc" },
    stockRange = { min = 0, max = 10 },
}, {
    getOverride = function()
        return {
            price = 88,
            tags = { "ToolCraft" },
            stock = { min = 2, max = 3 },
        }
    end,
})
T.equal(generated.basePrice, 12, "generated cache keeps intrinsic score under exact override")
T.equal(generated.exactPrice, 88, "generated cache keeps exact price as final policy")
T.equal(generated.tags[1], "ToolCraft", "generated cache tag override")
T.equal(generated.stockRange.min, 2, "generated cache stock minimum")
T.equal(generated.stockRange.max, 3, "generated cache stock maximum")
local generatedEntry = build.buildLiveEntry("Base.HarnessGenerated", generated, "Vanilla")
T.equal(generatedEntry.price, 88, "live catalog entry honors exact runtime price")

local empty = shared.buildEmptyCatalog({ activeModsHash = "test" }, "harness")
T.equal(type(empty.items), "table", "empty catalog has item map")
T.equal(empty.source, "harness", "empty catalog source")
T.equal(shared.stableHash({ "a", "b" }), shared.stableHash({ "a", "b" }), "stable hash")

local serializedIndex = ioLayer.serializeIndex({
    schemaVersion = 5,
    generatedAt = "PZ-test",
    activeModsHash = "hash",
    generatorVersion = 2,
    signatureVersion = "signature",
    pricingHeuristicVersion = 7,
    intrinsicConfigHash = shared.buildIntrinsicConfigHash(),
    pricingPolicyHash = shared.buildPricingConfigHash(),
    activeMods = { "MarketSense", "Example Mod" },
    files = {
        {
            root = "Food", category = "Food", subcategory = "Staple",
            leaf = "Canned", primaryPrefix = "Food.Canned",
            path = "Food/Staple/Canned.txt",
        },
    },
})
local indexLines = {}
for line in string.gmatch(string.gsub(serializedIndex, "\r\n", "\n"), "[^\n]+") do
    indexLines[#indexLines + 1] = line
end
_G.getFileReader = function()
    local position = 0
    return {
        readLine = function()
            position = position + 1
            return indexLines[position]
        end,
        close = function() end,
    }
end
local parsedIndex = assert(ioLayer.parseLuaTableFile("MS_Items/MS_ItemsIndex.txt"))
T.equal(parsedIndex.schemaVersion, 5, "safe index schema")
T.equal(parsedIndex.activeMods[2], "Example Mod", "safe index active mod")
T.equal(parsedIndex.files[1].path, "Food/Staple/Canned.txt", "safe index file path")
T.equal(parsedIndex.pricingConfigHash, shared.buildPricingConfigHash(),
    "pricing configuration is persisted in the runtime index")
T.equal(parsedIndex.intrinsicConfigHash, shared.buildIntrinsicConfigHash(),
    "intrinsic configuration is persisted in the runtime index")
_G.getFileReader = nil

local leanLines = {
    "# schema=MS_ITEMS_V2",
    "# root=Food",
    "# category=Food",
    "# subcategory=Dish",
    "# leaf=Prepared",
    "# primaryPrefix=Food.Dish.Prepared",
    "@origin=Vanilla",
    "@tags=FoodDishPerishable|Quality.Standard",
    "Base.CachedDish|42|1|4|Pot%7CLarge|retained|1.5|1|Base.Pot|pot|replace_on_use|vessel_v1|0|sealed",
    "",
}
_G.getFileReader = function()
    local position = 0
    return {
        readLine = function()
            position = position + 1
            return leanLines[position]
        end,
        close = function() end,
    }
end
local parsedLean = assert(ioLayer.parseLeanFile("Food/Dish/Prepared.txt"))
local cachedRow = parsedLean.groups[1].items[1]
T.equal(cachedRow[2], 42, "lean cache stores intrinsic score")
T.equal(cachedRow[5].vesselName, "Pot|Large", "lean cache decodes vessel identity")
T.equal(cachedRow[5].vesselState, "retained", "lean cache stores vessel state")
T.equal(cachedRow[5].capacity, 1.5, "lean cache stores vessel capacity")
T.equal(cachedRow[7], "sealed", "lean cache stores food state policy input")
_G.getFileReader = nil

_G.getGameTime = function()
    return {
        getYear = function() return 1993 end,
        getMonth = function() return 6 end,
        getDay = function() return 15 end,
        getTimeOfDay = function() return 13.5 end,
        getMinutes = function() return 30 end,
    }
end
T.equal(shared.getTimestamp(), "PZ-1993-07-15T13:30:00", "PZ timestamp")
_G.getGameTime = nil

local function fakeItem(fullType, hidden, loot)
    local moduleName, typeName = string.match(fullType, "^([^%.]+)%.(.+)$")
    local item = {
        fullType = fullType,
        moduleName = moduleName,
        typeName = typeName,
        hidden = hidden == true,
        loot = loot == true,
    }
    function item:getFullName() return self.fullType end
    function item:getModuleName() return self.moduleName end
    function item:getName() return self.typeName end
    function item:getDisplayCategory() return self.hidden and "Hidden" or "Tool" end
    function item:getDisplayName() return self.hidden and "DUMMY ITEM" or self.typeName end
    function item:getTooltip() return "" end
    function item:isHidden() return self.hidden end
    function item:getObsolete() return false end
    function item:canSpawnAsLoot() return self.loot end
    function item:isCraftRecipeProduct() return false end
    function item:canBeForaged() return false end
    return item
end

local lootItem = fakeItem("Base.HarnessLoot", false, true)
local hiddenItem = fakeItem("Base.HarnessDebugDummy", true, true)
local fishItem = fakeItem("Base.HarnessFish", false, false)
local craftItem = fakeItem("Base.HarnessCraft", false, false)
local fakeItems = { lootItem, hiddenItem, fishItem, craftItem }
local collection = {}
function collection:size() return #fakeItems end
function collection:get(index) return fakeItems[index + 1] end
local fakeByType = {
    [lootItem.fullType] = lootItem,
    [hiddenItem.fullType] = hiddenItem,
    [fishItem.fullType] = fishItem,
    [craftItem.fullType] = craftItem,
}
_G.getAllItems = function() return collection end
_G.getScriptManager = function()
    return {
        FindItem = function(_, fullType) return fakeByType[fullType] end,
        getAllRecipes = function()
            return {
                {
                    getResult = function()
                        return { getFullType = function() return craftItem.fullType end }
                    end,
                },
            }
        end,
        getAllCraftRecipes = function() return nil end,
        getAllEvolvedRecipesList = function() return nil end,
    }
end
_G.Fishing = { fishDefinitions = { { itemType = fishItem.fullType } } }
_G.ProceduralDistributions = {
    list = {
        Harness = {
            rolls = 1,
            items = { "HarnessLoot", 1, "HarnessFish", 10 },
        },
    },
}
local availabilityState = availability.rebuild(collection)
T.truthy(availabilityState.built, "availability index built")
T.equal(availability.get(lootItem.fullType).status, "obtainable", "loot engine signal")
T.equal(availability.get(hiddenItem.fullType).status, "excluded", "hidden engine signal")
T.equal(availability.get(hiddenItem.fullType).obtainable, false, "excluded item is not obtainable")
T.equal(availability.get(fishItem.fullType).status, "obtainable", "fishing runtime table")
T.equal(availability.get(craftItem.fullType).status, "obtainable", "recipe output registry")
local lootEvidence = availability.get(lootItem.fullType)
T.equal(lootEvidence.rarity, "Rare", "single low-weight loot entry is rare")
T.equal(lootEvidence.rarityEvidence.status, "observed", "loot rarity evidence status")
T.equal(lootEvidence.rarityEvidence.weightedEntryCount, 1, "loot weight evidence")
_G.Fishing = nil
_G.ProceduralDistributions = nil

T.finish("marketsense_runtime_smoke")
