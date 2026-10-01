local T = require "tests/support/test"
T.addPackagePaths()

local Availability = assert(T.load("MarketSense/MS_ItemAvailability.lua"))

local function collection(values)
    return {
        size = function() return #values end,
        get = function(_, index) return values[index + 1] end,
    }
end

local function item(fullType)
    local moduleName, typeName = string.match(fullType, "^([^%.]+)%.(.+)$")
    return {
        getFullName = function() return fullType end,
        getModuleName = function() return moduleName end,
        getName = function() return typeName end,
    }
end

local items = {}
local recipes = {}
for index = 1, 5 do
    local fullType = "Base.BudgetRecipeItem" .. tostring(index)
    items[index] = item(fullType)
    recipes[index] = {
        getResult = function()
            return {
                getFullType = function() return fullType end,
                getType = function() return "BudgetRecipeItem" .. tostring(index) end,
            }
        end,
    }
end

_G.getScriptManager = function()
    return {
        getAllRecipes = function() return collection(recipes) end,
        getAllCraftRecipes = function() return nil end,
        getAllEvolvedRecipesList = function() return nil end,
    }
end
_G.Distributions = {
    items = {
        "Base.BudgetRecipeItem1", 1,
        "Base.BudgetRecipeItem2", 1,
        "Base.BudgetRecipeItem3", 1,
    },
}

local job = Availability.beginRebuild(collection(items))
Availability.stepRebuild(job, 2, nil)
T.equal(job.index, 2, "item phase respects the work budget")
Availability.stepRebuild(job, 2, nil)
Availability.stepRebuild(job, 2, nil)
T.equal(job.phase, "regularRecipes", "recipe phases start after item discovery")

Availability.stepRebuild(job, 2, nil)
T.equal(job.regularRecipeState.index, 2,
    "regular recipe phase advances by the same bounded batch")
T.truthy(Availability.state.records["Base.BudgetRecipeItem1"],
    "bounded recipe work still records discovered outputs")
T.falsy(Availability.state.records["Base.BudgetRecipeItem4"],
    "bounded recipe work does not scan the whole collection")

while job.phase ~= "runtimeSources" do
    Availability.stepRebuild(job, 2, nil)
end
Availability.stepRebuild(job, 1, nil)
T.equal(Availability.state.records["Base.BudgetRecipeItem1"].lootEntryCount, 0,
    "runtime source traversal yields before processing loot entries")
Availability.stepRebuild(job, 1, nil)
T.equal(Availability.state.records["Base.BudgetRecipeItem1"].lootEntryCount, 1,
    "runtime source traversal processes one loot entry per bounded step")
T.equal(Availability.state.records["Base.BudgetRecipeItem2"].lootEntryCount, 0,
    "runtime source traversal does not scan the whole loot list")

T.finish("marketsense_availability_budget_smoke")
