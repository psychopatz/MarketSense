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
local yieldText = Window.BuildYieldSummary({
    yieldResolution = {
        status = "resolved",
        recipe = "OpenEggCarton",
        outputs = {{ fullType = "Base.Egg", quantity = 12 }},
    },
})
T.equal(yieldText, "Yield: OpenEggCarton -> 12 x Base.Egg",
    "catalog displays resolved bundle output")
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
local weaponToolHeuristicText = Window.BuildPriceHeuristicSummary({
    priceHeuristic = {
        model = "weapon_v2_pending",
        status = "pending",
        mechanicalClass = "WeaponSmallBlunt",
        role = "tool",
        recipeDemandScore = 0.91,
        recipeDemand = { recipeCount = 53, reusableRecipeCount = 52 },
    },
})
T.equal(weaponToolHeuristicText,
    "Pricing: pending | class=WeaponSmallBlunt | recipes=53 | reusable=52 | demand=0.91 | role=tool",
    "catalog displays tool recipe demand for weapon hybrids")
local literatureHeuristicText = Window.BuildPriceHeuristicSummary({
    priceHeuristic = {
        model = "literature_v2_pending",
        status = "pending",
        subtype = "Literature.SkillBook",
        skill = "Carpentry",
        skillLevel = 3,
        learnedRecipeCount = 2,
        readType = "normal",
    },
})
T.equal(literatureHeuristicText,
    "Pricing: pending | subtype=Literature.SkillBook | skill=Carpentry | level=3 | recipes=2 | read=normal",
    "catalog displays pending literature heuristic metadata")
local clothingHeuristicText = Window.BuildPriceHeuristicSummary({
    priceHeuristic = {
        model = "clothing_v2_pending",
        status = "pending",
        subtype = "ClothingOuterwear",
        bodyLocationToken = "jacket",
        biteDefense = 10,
        scratchDefense = 20,
        bulletDefense = 0,
    },
})
T.equal(clothingHeuristicText,
    "Pricing: pending | subtype=ClothingOuterwear | slot=jacket | bite=10 | scratch=20 | bullet=0",
    "catalog displays pending clothing heuristic evidence")
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
local containerHeuristicText = Window.BuildPriceHeuristicSummary({
    priceHeuristic = {
        model = "container_v2_pending",
        status = "pending",
        subtype = "ContainerBagBackpack",
        capacity = 27,
        weightReduction = 65,
        weight = 1.0,
        contentYieldStatus = "not_detected",
    },
})
T.equal(containerHeuristicText,
    "Pricing: pending | subtype=ContainerBagBackpack | capacity=27 | reduction=65 | weight=1.0 | yield=not_detected",
    "catalog displays pending container heuristic evidence")
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
