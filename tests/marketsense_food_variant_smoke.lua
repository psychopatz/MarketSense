local T = require "tests/support/test"
T.addPackagePaths()
_G.unpack = _G.unpack or table.unpack

local function foodScript(fullName, displayName, values)
    local item = {
        fullName = fullName,
        displayName = displayName,
        values = values or {},
    }

    function item:getFullName() return self.fullName end
    function item:getModuleName() return "Base" end
    function item:getName() return string.match(self.fullName, "^[^%.]+%.(.+)$") end
    function item:getDisplayCategory() return "Food" end
    function item:getItemType() return "FoodNonPerishableCanned" end
    function item:getDisplayName() return self.displayName end
    function item:getTooltip() return self.displayName end
    function item:getFoodType() return self.values.foodType or "" end
    function item:getHungerChange() return self.values.hungerChange or 0 end
    function item:getThirstChange() return self.values.thirstChange or 0 end
    function item:getCalories() return self.values.calories or 0 end
    function item:getCarbohydrates() return self.values.carbohydrates or 0 end
    function item:getLipids() return self.values.lipids or 0 end
    function item:getProteins() return self.values.proteins or 0 end
    function item:getDaysFresh() return 20 end
    function item:getDaysTotallyRotten() return 40 end
    function item:getActualWeight() return 0.5 end
    function item:getCannedFood() return true end
    function item:getPackaged() return true end
    function item:isCantEat() return self.values.isCantEat == true end
    function item:getReplaceOnUse() return self.values.replaceOnUse or "" end
    function item:Remove() end
    return item
end

local sealed = foodScript("Base.CannedTomato", "Canned Tomato", {
    -- Deliberately incomplete/wrong sealed metadata; the opened item is the
    -- authoritative edible form for this regression fixture.
    calories = 1,
    lipids = 0,
    isCantEat = true,
    replaceOnUse = "Base.CannedTomatoOpen",
})
local opened = foodScript("Base.CannedTomatoOpen", "Canned Tomato (Open)", {
    foodType = "Vegetable",
    hungerChange = -0.3,
    calories = 120,
    carbohydrates = 20,
    lipids = 1,
    proteins = 5,
})

local scriptManager = {}
function scriptManager:FindItem(fullType)
    if fullType == sealed.fullName then return sealed end
    if fullType == opened.fullName then return opened end
end

_G.getScriptManager = function() return scriptManager end
_G.instanceof = function(_, className)
    return className == "Food" or className == "InventoryItem"
end
_G.instanceItem = function(scriptItem) return scriptItem end

local propertyReader = require "MarketSense/MS_PropertyReader"
MarketSense.RuntimeCache.clear()
local context = propertyReader.buildContext(sealed.fullName)

T.equal(context.hungerChange, -0.3,
    "opened food signed hunger metadata replaces sealed default")
T.equal(context.calories, 120,
    "opened food calories replace sealed metadata")
T.equal(context.carbohydrates, 20,
    "opened food carbohydrates are read")
T.equal(context.lipids, 1,
    "opened food lipids replace sealed metadata")
T.equal(context.proteins, 5,
    "opened food proteins replace sealed metadata")
T.equal(context.foodType, "Vegetable",
    "opened food type refines the sealed item")
T.equal(context.foodVariantEvidence.sourceFullType, opened.fullName,
    "food evidence records the opened source item")
T.equal(context.foodVariantEvidence.relation, "definition_reference",
    "explicit replacement metadata outranks a name heuristic")
T.equal(context.foodVariantEvidence.status, "verified",
    "opened nutrition is marked verified")
T.truthy(#context.foodVariantEvidence.conflicts > 0,
    "disagreement with sealed metadata remains auditable")

local evidence = require "MarketSense/MS_FoodVariantEvidence"
evidence.apply(context, function(fullType)
    return propertyReader.buildContext(fullType, nil, true)
end, {
    status = "resolved",
    outputs = {{ fullType = opened.fullName, quantity = 1, chance = 1, resolution = "exact" }},
})
T.equal(context.foodVariantEvidence.relation, "recipe_output",
    "exact opened recipe output outranks a name/reference fallback")

local openedContext = propertyReader.buildContext(opened.fullName)
T.equal(openedContext.foodVariantEvidence.status, "not_applicable",
    "opened variants are not recursively audited as their own packages")

local Pricing = require "MarketSense/MS_Pricing"
local sealedDetails = {
    category = "Food",
    primary = "FoodNonPerishableCanned",
    tags = { "FoodNonPerishableCanned" },
    expandedTags = { "FoodNonPerishableCanned", "FoodNonPerishable", "Food" },
}
local openedDetails = {
    category = "Food",
    primary = "FoodNonPerishableCanned",
    tags = { "FoodNonPerishableCanned" },
    expandedTags = { "FoodNonPerishableCanned", "FoodNonPerishable", "Food" },
}
local sealedScore = Pricing.calculateRawScore(context, sealedDetails)
local openedScore = Pricing.calculateRawScore(openedContext, openedDetails)
T.truthy(sealedScore > openedScore,
    "sealed canned food outranks its opened counterpart")
T.equal(sealedDetails.priceHeuristic.foodCondition, "sealed",
    "sealed canned food reports a sealed condition")
T.equal(openedDetails.priceHeuristic.foodCondition, "opened",
    "opened canned food reports a negative opened condition")

T.finish("marketsense_food_variant_smoke")
