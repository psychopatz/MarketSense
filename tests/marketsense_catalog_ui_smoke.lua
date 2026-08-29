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
DynamicTrading = {
    GetAllKnownItems = function() return {} end,
    ClearRuntimeCache = function() DynamicTrading.cacheCleared = true end,
    RegenerateItemRegistry = function()
        return { total = 2, files = { {}, {} } }
    end,
}

local WindowBase = {}
function WindowBase:derive()
    local child = {}
    child.__index = child
    setmetatable(child, { __index = self })
    return child
end
PsychopatzWindow = WindowBase

package.preload["ISUI/ISTextEntryBox"] = function() return true end
package.preload["MarketSense/MS_PublicAPI"] = function() return DynamicTrading end
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
T.equal(DynamicTrading.cacheCleared, true,
    "runtime generation clears stale price details")

T.finish("marketsense_catalog_ui_smoke")
