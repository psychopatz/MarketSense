local T = require "tests/support/test"
T.addPackagePaths()
package.path = T.modRoot .. "/common/media/lua/client/?.lua;" .. package.path

MarketSense = {}
getText = function(key) return key end
require "MarketSense/signatures/tags/MS_TagMapper"

local UI = {
    Theme = {},
    Layout = {},
    ImageResolver = { DrawItemIcon = function() end },
    CreateCategorizedList = function() end,
}
PsychopatzCore = {
    UI = UI,
    DebugHub = {},
}
PsychopatzCore.DebugHub.RegisterTool = function(definition)
    PsychopatzCore.DebugHub.testTool = definition
    return true
end
MarketSense.GetAllKnownItems = function() return {} end
MarketSense.GetRegistryDetails = function(fullType)
    if fullType == "Base.CannedCarrots2" then return { basePrice = 1 } end
    return nil
end
getItemDisplayName = function(fullType)
    if fullType == "Base.CannedCarrots2" then return "Canned Carrots" end
    return fullType
end
MarketSense.ClearRuntimeCache = function() MarketSense.cacheCleared = true end
MarketSense.RegenerateItemRegistry = function()
    return { total = 2, files = { {}, {} } }
end

-- The GUI must consume the canonical MarketSense API directly.
local WindowBase = {}
function WindowBase:derive()
    local child = {}
    child.__index = child
    setmetatable(child, { __index = self })
    return child
end
PsychopatzWindow = WindowBase

package.preload["ISUI/ISTextEntryBox"] = function() return true end
package.preload["ISUI/ISComboBox"] = function()
    ISComboBox = ISComboBox or {}
    return ISComboBox
end
package.preload["MarketSense/MS_PublicAPI"] = function() return MarketSense end
package.preload["PsychopatzCore/UI/PsychopatzUI"] = function() return UI end
package.preload["PsychopatzCore/UI/PsychopatzDebugHubWindow"] = function()
    return PsychopatzCore.DebugHub
end

local Window = dofile(T.modRoot
    .. "/common/media/lua/client/MarketSense/MS_ItemCatalogDebugWindow.lua")

local function path(row)
    return table.concat(Window.BuildCategoryPath(row), "/")
end

T.equal(path({
    category = "Weapon", primary = "Ammo",
    expandedTags = { "Ammo", "Weapon" },
}), "Weapon/Ranged/Ammo", "ammo category path")
T.equal(path({
    category = "Weapon", primary = "FirearmRifle",
    expandedTags = { "FirearmRifle", "Firearm", "WeaponRanged", "Weapon" },
}), "Weapon/Ranged/Firearm", "firearm category path")
T.equal(path({
    category = "Food", primary = "FoodNonPerishableCanned",
    expandedTags = { "FoodNonPerishableCanned", "FoodNonPerishable", "Food" },
}), "Food/NonPerishable", "food category path")
T.equal(path({
    category = "Container", primary = "ContainerBag",
    expandedTags = { "ContainerBag", "Container" },
}), "Container/Bag", "container category path")

local gardeningDescription = Window.BuildDisplayTags({
    category = "Building",
    subcategory = "Gardening",
    leaf = "PestControl",
    primary = "GardeningPestControl",
    tags = {
        "GardeningPestControl", "Quality.Standard", "Origin.Vanilla",
        "Rarity.Common", "Theme.GrowingSeason",
    },
    expandedTags = {
        "GardeningPestControl", "Gardening", "Building",
        "Quality.Standard", "Origin.Vanilla", "Rarity.Common",
        "Theme.GrowingSeason",
    },
    sourceModId = "Vanilla",
})
T.equal(gardeningDescription,
    "Category: Building > Gardening > Pest Control | Quality: Standard | Rarity: Common | Theme: Growing Season | Origin: Vanilla",
    "catalog description groups canonical taxonomy and descriptors without duplicate origin")
T.truthy(not string.find(gardeningDescription, "Vanilla.*Vanilla"),
    "catalog description does not repeat vanilla origin")

local cachedRows = {
    {
        fullType = "Base.TinnedFish",
        category = "Food",
        subcategory = "Seafood",
        primary = "FoodSeafoodPerishable",
        expandedTags = { "FoodSeafoodPerishable", "FoodSeafood", "Food",
            "Theme.Survival" },
        sourceModId = "Vanilla",
    },
    {
        fullType = "Brita.Rifle",
        category = "Weapon",
        subcategory = "Ranged",
        primary = "FirearmRifle",
        expandedTags = { "FirearmRifle", "Firearm", "WeaponRanged", "Weapon",
            "Theme.Combat" },
        sourceModId = "Brita",
    },
}
local filterOptions = Window.BuildFilterOptions(cachedRows)
local filterOptionsByKey = {}
for _, option in ipairs(filterOptions) do
    filterOptionsByKey[option.key] = option
end
T.truthy(filterOptionsByKey["all"] ~= nil,
    "catalog filter includes all-items option")
T.truthy(filterOptionsByKey["category\31food"] ~= nil,
    "catalog filter includes category options")
T.truthy(filterOptionsByKey["subcategory\31food.seafood"] ~= nil,
    "catalog filter includes subcategory options")
T.truthy(filterOptionsByKey["theme\31survival"] ~= nil,
    "catalog filter includes theme options")
T.truthy(filterOptionsByKey["origin\31vanilla"] ~= nil,
    "catalog filter includes origin options")
T.truthy(Window.MatchesFilter(cachedRows[1],
    { kind = "subcategory", value = "Food.Seafood" }),
    "subcategory filter matches cached row")
T.truthy(Window.MatchesFilter(cachedRows[1],
    { kind = "theme", value = "Survival" }),
    "theme filter matches cached row")
T.truthy(not Window.MatchesFilter(cachedRows[1],
    { kind = "origin", value = "Brita" }),
    "origin filter excludes other cached rows")
local filteredView = {
    allItems = cachedRows,
    visibleItems = {},
    filterSelection = { kind = "category", value = "Food" },
    search = { getText = function() return "" end },
    itemList = {
        setItems = function(self, items) self.items = items end,
    },
}
Window.refreshVisibleItems(filteredView)
T.equal(#filteredView.itemList.items, 1,
    "catalog filter updates visible rows from the cached snapshot")
T.equal(filteredView.itemList.items[1].fullType, "Base.TinnedFish",
    "catalog filter keeps the matching cached row")
local yieldText = Window.BuildYieldSummary({
    yieldResolution = {
        status = "resolved",
        recipe = "OpenEggCarton",
        outputs = {{ fullType = "Base.Egg", quantity = 12 }},
    },
})
T.equal(yieldText, "Yield: OpenEggCarton -> 12 x Base.Egg",
    "catalog displays resolved bundle output")
local baseItemText = Window.BuildBaseItemSummary({
    yieldResolution = {
        status = "resolved",
        outputs = {{ fullType = "Base.CannedCarrots2", quantity = 6 }},
    },
})
T.equal(baseItemText,
    "Base item: 6 x Canned Carrots [Base.CannedCarrots2] (base price=$1)",
    "catalog displays bundle base item and persisted base price")
local ambiguousYieldText = Window.BuildYieldSummary({
    yieldResolution = {
        status = "ambiguous", candidateCount = 2,
        candidates = {{ recipe = "OpenBoxOne" }, { recipe = "OpenBoxTwo" }},
    },
})
T.equal(ambiguousYieldText, "Yield: AMBIGUOUS (2 candidates): OpenBoxOne, OpenBoxTwo",
    "catalog displays ambiguous bundle candidates")
local missingYieldText = Window.BuildYieldSummary({
    yieldResolution = { status = "not_detected", recipeCount = 4326, sourceCount = 1875 },
})
T.equal(missingYieldText, "Yield: NOT_DETECTED (4326 recipes, 1875 sources indexed)",
    "catalog displays missing-yield index diagnostics")
local foodHeuristicText = Window.BuildPriceHeuristicSummary({
    priceHeuristic = {
        model = "food_v2_bundle",
        status = "ready",
        subtype = "FoodNonPerishableBoxed",
        role = "edible",
        rationUnits = 1.25,
        hungerChange = -0.3,
        thirstChange = 0,
        freshnessState = "definition_freshness",
        yieldStatus = "resolved",
    },
})
T.equal(foodHeuristicText,
    "Pricing: ready | subtype=FoodNonPerishableBoxed | role=edible | ration=1.25 | hunger=-0.30 | thirst=0.00 | freshness=definition_freshness | yield=resolved",
    "catalog displays food utility and valued bundle evidence")
T.equal(Window.BuildPriceHeuristicSummary({
    priceHeuristic = {
        model = "food_v2", status = "ready", subtype = "Food",
        role = "edible", rationUnits = 1.25, hungerChange = -0.3,
        thirstChange = 0, freshnessState = "fresh", yieldStatus = "not_detected",
        calories = 120, carbohydrates = 20, lipids = 1, proteins = 5,
        foodVariantEvidence = {
            status = "verified", sourceFullType = "Base.CannedTomatoOpen",
            relation = "definition_reference",
        },
    },
}),
    "Pricing: ready | subtype=Food | role=edible | ration=1.25 | hunger=-0.30 | thirst=0.00 | freshness=fresh | yield=not_detected | variant=Base.CannedTomatoOpen[definition_reference] | nutrition=cal:120 carb:20 fat:1 protein:5",
    "catalog displays opened-food nutrition evidence")
T.equal(Window.BuildMarketModifierSummary({
    marketPricing = {
        anchor = 10,
        anchorSpreadMultiplier = 1.04,
        tagAdd = 17,
        itemAdd = 0,
        variationMultiplier = 0.98,
        variationSource = "WorldGenParams.seedString",
    },
}),
    "Market: anchor=$10 | contrast=1.040x | tagAdd=17 | itemAdd=0 | variation=0.980x (WorldGenParams.seedString)",
    "catalog displays typed modifier and seeded variation diagnostics")
T.equal(Window.BuildMarketModifierSummary({
    marketPricing = {
        absoluteOverride = true,
        overridePrice = 77,
        variationSource = "disabled",
    },
}), "Market: exact override=$77 | variation=disabled",
    "catalog distinguishes exact overrides from disabled variation")
local weaponToolHeuristicText = Window.BuildPriceHeuristicSummary({
    priceHeuristic = {
        model = "weapon_v2",
        status = "ready",
        mechanicalClass = "WeaponSmallBlunt",
        role = "tool",
        recipeDemandScore = 0.91,
        recipeDemand = { recipeCount = 53, reusableRecipeCount = 52 },
    },
})
T.equal(weaponToolHeuristicText,
    "Pricing: ready | class=WeaponSmallBlunt | recipes=53 | reusable=52 | demand=0.91 | role=tool",
    "catalog displays tool recipe demand for weapon hybrids")
local literatureHeuristicText = Window.BuildPriceHeuristicSummary({
    priceHeuristic = {
        model = "literature_v2",
        status = "ready",
        subtype = "Literature.SkillBook",
        skill = "Carpentry",
        skillLevel = 3,
        learnedRecipeCount = 2,
        readType = "normal",
    },
})
T.equal(literatureHeuristicText,
    "Pricing: ready | subtype=Literature.SkillBook | skill=Carpentry | level=3 | recipes=2 | read=normal",
    "catalog displays literature heuristic metadata")
local liquidHeuristicText = Window.BuildPriceHeuristicSummary({
    priceHeuristic = {
        model = "liquid_v2",
        status = "ready",
        subtype = "LiquidWater",
        fluidTypeString = "Water",
        fluidAmount = 2,
        fluidPrimaryAmount = 2,
        fluidFilledRatio = 1,
        fluidIsMixture = false,
        yieldStatus = "not_detected",
    },
})
T.equal(liquidHeuristicText,
    "Pricing: ready | subtype=LiquidWater | fluid=Water | amount=2 | primary=2 | ratio=1.00 | mixture=no | yield=not_detected",
    "catalog displays liquid heuristic evidence")
local resourceHeuristicText = Window.BuildPriceHeuristicSummary({
    priceHeuristic = {
        model = "resource_v2",
        status = "ready",
        subtype = "MaterialMetalworking",
        materialFamily = "Metalworking",
        materialForm = "ore",
        canStack = "true",
        yieldStatus = "resolved",
        yieldOutputCount = 1,
        yieldOutputQuantity = 4,
    },
})
T.equal(resourceHeuristicText,
    "Pricing: ready | subtype=MaterialMetalworking | family=Metalworking | form=ore | stack=true | yield=resolved (1 outputs, qty=4)",
    "catalog displays resource yield evidence")
local miscHeuristicText = Window.BuildPriceHeuristicSummary({
    priceHeuristic = {
        model = "misc_v2",
        status = "ready",
        subtype = "MiscFishing",
        signals = { "fishing_lure", "recipe_transform" },
        maxUses = 6,
        weight = 1.5,
        yieldStatus = "resolved",
        yieldOutputCount = 1,
        yieldOutputQuantity = 6,
    },
})
T.equal(miscHeuristicText,
    "Pricing: ready | subtype=MiscFishing | signals=fishing_lure,recipe_transform | uses=6 | weight=1.5 | yield=resolved (1 outputs, qty=6)",
    "catalog displays Misc utility and yield evidence")
local miscBundleHeuristicText = Window.BuildPriceHeuristicSummary({
    priceHeuristic = {
        model = "misc_v2_bundle",
        status = "ready",
        subtype = "Misc",
        signals = { "recipe_transform" },
        weight = 0.5,
        yieldStatus = "resolved",
        yieldOutputCount = 1,
        yieldOutputQuantity = 6,
        mode = "multi_output_bundle",
        yieldValue = 12,
    },
})
T.equal(miscBundleHeuristicText,
    "Pricing: ready | subtype=Misc | signals=recipe_transform | uses=- | weight=0.5 | yield=resolved (1 outputs, qty=6) | mode=multi_output_bundle | value=12",
    "catalog displays valued Misc bundle evidence")
local clothingHeuristicText = Window.BuildPriceHeuristicSummary({
    priceHeuristic = {
        model = "clothing_v2",
        status = "ready",
        subtype = "ClothingOuterwear",
        bodyLocationToken = "jacket",
        biteDefense = 10,
        scratchDefense = 20,
        bulletDefense = 0,
    },
})
T.equal(clothingHeuristicText,
    "Pricing: ready | subtype=ClothingOuterwear | slot=jacket | bite=10 | scratch=20 | bullet=0",
    "catalog displays clothing heuristic evidence")
local toolHeuristicText = Window.BuildPriceHeuristicSummary({
    priceHeuristic = {
        model = "tool_v2",
        status = "ready",
        subtype = "ToolBlacksmith",
        recipeCriticality = "high",
        recipeDemandScore = 0.91,
        recipeDemand = { recipeCount = 53, reusableRecipeCount = 52 },
    },
})
T.equal(toolHeuristicText,
    "Pricing: ready | subtype=ToolBlacksmith | recipes=53 | reusable=52 | criticality=high | demand=0.91",
    "catalog displays tool recipe-demand evidence")
T.equal(Window.BuildDetailSubtext({
    yieldResolution = { status = "not_detected", recipeCount = 1, sourceCount = 2 },
    priceHeuristic = {
        model = "tool_v2", status = "ready", subtype = "ToolBlacksmith",
        recipeCriticality = "high", recipeDemandScore = 0.91,
        recipeDemand = { recipeCount = 53, reusableRecipeCount = 52 },
    },
}),
    "Pricing: ready | subtype=ToolBlacksmith | recipes=53 | reusable=52 | criticality=high | demand=0.91 | Yield: NOT_DETECTED (1 recipes, 2 sources indexed)",
    "catalog keeps pricing diagnostics visible beside yield diagnostics")
local detailLines = Window.BuildDetailLines({
    category = "Food",
    categoryPath = { "Food", "Perishable", "Vegetables" },
    rarity = "Common",
    themes = { "HighCalorie", "HighFat" },
}, {
    priceHeuristic = {
        model = "food_v2", role = "spice", foodCondition = "fresh",
        score = 12.5, rationUnits = 0.55, hungerChange = -0.1,
        thirstChange = 0,
        categoryBand = { category = "Food", min = 50, max = 500 },
    },
    marketPricing = {
        subcategoryAdd = -10, tagAdd = 11,
        variationMultiplier = 0.98,
    },
    yieldResolution = { status = "not_detected", recipeCount = 2, sourceCount = 1 },
})
T.equal(detailLines[1].label, "Classification",
    "catalog detail lines expose organized classification")
T.truthy(string.find(detailLines[3].value, "raw=12.5", 1, true) ~= nil,
    "catalog labels raw heuristic values as non-price data")
T.truthy(string.find(detailLines[4].value, "band=Food $50-$500", 1, true) ~= nil,
    "catalog detail lines separate the reference band from the catalog price")
local containerHeuristicText = Window.BuildPriceHeuristicSummary({
    priceHeuristic = {
        model = "container_v2",
        status = "ready",
        subtype = "ContainerBagBackpack",
        capacity = 27,
        weightReduction = 65,
        weight = 1.0,
        yieldStatus = "not_detected",
    },
})
T.equal(containerHeuristicText,
    "Pricing: ready | subtype=ContainerBagBackpack | capacity=27 | reduction=65 | weight=1.0 | yield=not_detected",
    "catalog displays container heuristic evidence")
local electronicsHeuristicText = Window.BuildPriceHeuristicSummary({
    priceHeuristic = {
        model = "electronics_v2",
        status = "ready",
        subtype = "ElectronicsRadio",
        capabilities = { "radio_communication" },
        lightStrength = 1.5,
        deviceDataAvailable = true,
    },
})
T.equal(electronicsHeuristicText,
    "Pricing: ready | subtype=ElectronicsRadio | capability=radio_communication | light=1.5 | device",
    "catalog displays electronics heuristic evidence")
local medicalHeuristicText = Window.BuildPriceHeuristicSummary({
    priceHeuristic = {
        model = "medical_v2",
        status = "ready",
        subtype = "FirstAid",
        bandagePower = 1,
        reduceInfectionPower = 0,
        yieldStatus = "resolved",
    },
})
T.equal(medicalHeuristicText,
    "Pricing: ready | subtype=FirstAid | bandage=1 | infection=0 | effect=1 | yield=resolved",
    "catalog displays medical heuristic evidence")
local buildingHeuristicText = Window.BuildPriceHeuristicSummary({
    priceHeuristic = {
        model = "building_v2",
        status = "ready",
        subtype = "BuildingFurnitureStorage",
        capabilities = { "storage_surface" },
        capabilityEvidence = { "world.furniture.storage" },
        requirements = { "electricity" },
        capacity = 24,
        worldContainerCapacity = 24,
        worldEvidenceAvailable = true,
        yieldStatus = "resolved",
    },
})
T.equal(buildingHeuristicText,
    "Pricing: ready | subtype=BuildingFurnitureStorage | capability=storage_surface | evidence=world.furniture.storage | requirement=electricity | capacity=24 | world=available | yield=resolved",
    "catalog displays building heuristic evidence")
T.equal(PsychopatzCore.DebugHub.testTool.id, "marketsense.itemCatalog",
    "catalog debug tool registration")
local generatedWindow = {
    allItems = {},
    refreshCatalog = function(self) self.refreshed = true end,
}
Window.onGenerateRuntimeItems(generatedWindow)
T.equal(generatedWindow.refreshed, true, "runtime generation refreshes catalog")
T.equal(generatedWindow.runtimeGenerationBusy, false,
    "runtime generation clears busy state")
T.equal(type(generatedWindow.runtimeGenerationStatus), "string",
    "runtime generation reports status")
T.equal(MarketSense.cacheCleared, true,
    "runtime generation clears stale price details")

T.finish("marketsense_catalog_ui_smoke")
