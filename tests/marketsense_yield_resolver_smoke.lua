local T = require "tests/support/test"
T.addPackagePaths()

local Resolver = assert(require "MarketSense/Pricing/MS_YieldResolver")
local ToolRecipeDemand = assert(require "MarketSense/Pricing/MS_ToolRecipeDemand")

-- PZ exposes several Java List/Set values through collection-shaped bridge
-- objects rather than plain Lua arrays.  This fixture keeps the payload out
-- of numeric keys so the resolver must use the same collection adapter as
-- the live runtime.
local function javaList(values)
    local value = { values = values }
    function value:toArray() return self.values end
    return value
end

local function item(fullType)
    local moduleName, typeName = string.match(fullType, "^([^%.]+)%.(.+)$")
    local value = { fullType = fullType, moduleName = moduleName, typeName = typeName }
    function value:getFullName() return self.fullType end
    function value:getModuleName() return self.moduleName end
    function value:getName() return self.typeName end
    return value
end

local function input(possible, amount, originalLine, mode, tool)
    local value = {
        possible = javaList(possible), amount = amount or 1,
        line = originalLine or "",
        mode = mode or "use", tool = tool == true,
    }
    function value:getPossibleInputItems() return self.possible end
    function value:getAmount() return self.amount end
    function value:getMaxAmount() return self.amount end
    function value:getOriginalLine() return self.line end
    function value:isKeep() return self.mode == "keep" end
    function value:isDestroy() return self.mode == "destroy" end
    function value:isTool() return self.tool end
    function value:isToolLeft() return false end
    function value:isToolRight() return false end
    return value
end

local function output(possible, amount, originalLine, mapper)
    local value = {
        possible = javaList(possible), amount = amount or 1,
        line = originalLine or "",
        mapper = mapper,
    }
    function value:getPossibleResultItems() return self.possible end
    function value:getAmount() return self.amount end
    function value:getChance() return 1 end
    function value:getOutputMapper() return self.mapper end
    function value:getOriginalLine() return self.line end
    return value
end

local function recipe(name, inputs, outputs)
    local value = {
        name = name, inputs = javaList(inputs), outputs = javaList(outputs),
    }
    function value:getName() return self.name end
    function value:getInputs() return self.inputs end
    function value:getOutputs() return self.outputs end
    return value
end

local function mapper(patterns)
    local value = { patterns = patterns }
    function value:getPatternForResult(result)
        return self.patterns[result]
    end
    return value
end

local egg = item("Base.Egg")
local carton = item("Base.EggCarton")
local beerBottle = item("Base.BeerBottle")
local beerCan = item("Base.BeerCan")
local beerPack = item("Base.BeerPack")
local beerCanPack = item("Base.BeerCanPack")
local ambiguousBox = item("Base.AmbiguousBox")
local unknownBox = item("Base.UnknownBox")
local hammer = item("Base.Hammer")

local beerMapper = mapper({
    [beerBottle] = javaList({ beerPack }),
    [beerCan] = javaList({ beerCanPack }),
})

local recipes = {
    recipe(
        "OpenEggCarton",
        { input({ carton }, 1, "item 1 Base.EggCarton flags[InheritFoodAge]") },
        { output({ egg }, 12) }
    ),
    recipe(
        "OpenPackOfBeer",
        { input({ beerPack, beerCanPack }) },
        { output({ beerBottle, beerCan }, 6, "item 6 mapper:Beer flags[InheritFoodAge]", beerMapper) }
    ),
    recipe("OpenBoxOne", { input({ ambiguousBox }) }, { output({ egg }, 1) }),
    recipe("OpenBoxTwo", { input({ ambiguousBox }) }, { output({ beerCan }, 1) }),
    recipe("OpenUnknownBox", { input({ unknownBox }) }, { output({}) }),
    recipe(
        "UseHammer",
        { input({ hammer }, 2, "item 2 tags[base:hammer] mode:keep flags[MayDegradeLight]", "keep") },
        { output({ egg }, 1) }
    ),
}

_G.getScriptManager = function()
    return {
        getAllCraftRecipes = function() return javaList(recipes) end,
    }
end

Resolver.clear()
local cartonResolution = Resolver.resolve({ fullType = carton:getFullName() })
T.equal(cartonResolution.status, "resolved", "name heuristic resolves egg carton")
T.equal(cartonResolution.candidateMethod, "recipe_name", "egg carton candidate method")
T.equal(cartonResolution.outputs[1].fullType, egg:getFullName(), "egg output type")
T.equal(cartonResolution.outputs[1].quantity, 12, "egg output quantity")
T.truthy(cartonResolution.outputs[1].inheritFoodAge, "egg age inheritance")

local canPackResolution = Resolver.resolve({
    fullType = beerCanPack:getFullName(), openingRecipe = "OpenPackOfBeer",
})
T.equal(canPackResolution.status, "resolved", "mapped beer pack resolves")
T.equal(canPackResolution.outputs[1].fullType, beerCan:getFullName(), "mapped beer output")
T.equal(canPackResolution.outputs[1].quantity, 6, "mapped beer quantity")

local ambiguousResolution = Resolver.resolve({ fullType = ambiguousBox:getFullName() })
T.equal(ambiguousResolution.status, "ambiguous", "ambiguous box is visible")
T.equal(ambiguousResolution.candidateCount, 2, "ambiguous box candidate count")

local unresolvedResolution = Resolver.resolve({ fullType = unknownBox:getFullName() })
T.equal(unresolvedResolution.status, "unresolved", "unresolved output is visible")

-- Explicit item-side openers must still resolve when the global recipe index
-- was first requested before the recipe list was populated.
local explicitManager = {
    getAllCraftRecipes = function() return javaList({}) end,
    getCraftRecipe = function(_, name)
        return name == "OpenPackOfBeer" and recipes[2] or nil
    end,
}
_G.getScriptManager = function() return explicitManager end
Resolver.clear()
local explicitResolution = Resolver.resolve({
    fullType = beerCanPack:getFullName(),
    doubleClickRecipe = "OpenPackOfBeer",
})
T.equal(explicitResolution.status, "resolved",
    "explicit opener resolves outside the global recipe index")
T.equal(explicitResolution.outputs[1].quantity, 6,
    "explicit opener retains mapped yield quantity")

_G.getScriptManager = function()
    return { getAllCraftRecipes = function() return javaList(recipes) end }
end
ToolRecipeDemand.clear()
local toolDemand = ToolRecipeDemand.resolve({ fullType = hammer:getFullName() })
T.equal(toolDemand.status, "resolved", "runtime tool recipe demand resolves")
T.equal(toolDemand.reusableRecipeCount, 1,
    "runtime tool demand counts reusable recipes")
T.equal(toolDemand.reusableInputAmount, 2,
    "runtime tool demand uses the recipe input amount")
T.equal(toolDemand.recipes[1].selectorKind, "tags",
    "runtime tool demand preserves tag selector evidence")

T.finish("marketsense_yield_resolver_smoke")
