local T = require "tests/support/test"
T.addPackagePaths()

_G.unpack = _G.unpack or table.unpack

local scriptItem = {
    fullName = "Base.DescriptionFood",
}

function scriptItem:getFullName() return self.fullName end
function scriptItem:getModuleName() return "Base" end
function scriptItem:getName() return "DescriptionFood" end
function scriptItem:getDisplayCategory() return "Food" end
function scriptItem:getItemType() return "Food" end
function scriptItem:getDisplayName() return "Generic Item" end
function scriptItem:getTooltip() return "Canned preserved bean meal" end
function scriptItem:getFoodType() return "" end
function scriptItem:getHungerChange() return -0.2 end
function scriptItem:getCalories() return 250 end
function scriptItem:getDaysFresh() return 20 end
function scriptItem:getDaysTotallyRotten() return 40 end
function scriptItem:getActualWeight() return 3 end
function scriptItem:getConditionMax() return 10 end
function scriptItem:getLevelSkillTrained() return 3 end

local inventoryItem = {}
function inventoryItem:getDescription() return "Canned preserved bean meal" end
function inventoryItem:getActualWeight() return 0.5 end
function inventoryItem:getCalories() return 180 end
function inventoryItem:getConditionMax() return 99 end
function inventoryItem:getAge() return 30 end
function inventoryItem:isRotten() return false end
function inventoryItem:isFrozen() return false end
function inventoryItem:isCooked() return false end
function inventoryItem:isBurnt() return false end
function inventoryItem:getHeat() return 0 end
function inventoryItem:isCannedFood() return true end
function inventoryItem:Remove() end

local beverageCategory = "Beverage"
local liquidCategory = "Liquid"
local fluidCategoryList = {}
function fluidCategoryList:size() return 2 end
function fluidCategoryList:get(index)
    return index == 0 and beverageCategory or liquidCategory
end
_G.FluidCategory = {
    getList = function() return fluidCategoryList end,
}

local beerFluid = {}
function beerFluid:getFluidType() return "Beer" end
function beerFluid:getFluidTypeString() return "Beer" end
function beerFluid:isCategory(category)
    return category == beverageCategory or category == liquidCategory
end

local beerContainer = {}
function beerContainer:getContainerName() return "BeerCan" end
function beerContainer:getAmount() return 12 end
function beerContainer:getCapacity() return 12 end
function beerContainer:getPrimaryFluidAmount() return 12 end
function beerContainer:getFilledRatio() return 1 end
function beerContainer:getPrimaryFluid() return beerFluid end
function beerContainer:isEmpty() return false end
function beerContainer:isMixture() return false end
function inventoryItem:getFluidContainer() return beerContainer end

_G.instanceof = function(_, className)
    return className == "Food" or className == "InventoryItem"
end
_G.instanceItem = function(_) return inventoryItem end

local weaponScriptItem = {
    fullName = "Base.HarnessSpear",
}
function weaponScriptItem:getFullName() return self.fullName end
function weaponScriptItem:getModuleName() return "Base" end
function weaponScriptItem:getName() return "HarnessSpear" end
function weaponScriptItem:getDisplayCategory() return "Weapon" end
function weaponScriptItem:getItemType() return "base:weapon" end
function weaponScriptItem:getDisplayName() return "Harness Spear" end
function weaponScriptItem:getWeaponCategories() return { "base:spear", "base:improvised" } end
function weaponScriptItem:getMinDamage() return 1 end
function weaponScriptItem:getMaxDamage() return 2 end
function weaponScriptItem:getMaxRange() return 1.5 end
function weaponScriptItem:getMaxHitCount() return 2 end
function weaponScriptItem:getConditionMax() return 100 end
function weaponScriptItem:getActualWeight() return 1.2 end
function weaponScriptItem:getTooltip() return "a crafted spear" end

local scriptManager = {}
function scriptManager:FindItem(fullType)
    if fullType == scriptItem.fullName then
        return scriptItem
    end
    if fullType == "Base.HarnessSpear" then
        return weaponScriptItem
    end
end
_G.getScriptManager = function() return scriptManager end

local function weaponInstance(condition)
    local item = {}
    function item:getCondition() return condition end
    function item:getConditionMax() return 100 end
    function item:getActualWeight() return 1.2 end
    function item:Remove() end
    return item
end

local api = assert(require "MarketSense/MS_PublicAPI")
T.equal(api, MarketSense, "canonical public API is MarketSense")
local collectionLike = {}
function collectionLike:toArray() return { "Beverage", "Liquid" } end
local collectionValues = MarketSense.Core.listFromJavaCollection(collectionLike)
T.equal(#collectionValues, 2, "Java collection adapter reads toArray values")
T.equal(collectionValues[1], "Beverage", "Java collection adapter preserves values")
local printedSet = setmetatable({}, {
    __tostring = function() return "[Beverage]" end,
})
local printedSetValues = MarketSense.Core.listFromJavaCollection(printedSet)
T.equal(#printedSetValues, 1, "Java Set adapter reads stable printed values")
T.equal(printedSetValues[1], "Beverage", "Java Set adapter preserves printed value")
MarketSense.Config.MasterList = {
    ["Base.HarnessRegistryItem"] = {
        fullType = "Base.HarnessRegistryItem",
    },
}
T.truthy(MarketSense.Config.MasterList["Base.HarnessRegistryItem"],
    "MarketSense owns the canonical master list")
T.truthy(api.GetPriceDetails(scriptItem.fullName),
    "MarketSense evaluator works as a standalone mod")
local propertyReader = assert(MarketSense.PropertyReader)
local registry = assert(MarketSense.ItemsRegistry)

T.truthy(api.ApplyRuntimeRule({
    overridesById = {
        [scriptItem.fullName] = {
            price = 77,
            tags = { "FoodNonPerishableCanned" },
            stock = { min = 2, max = 4 },
        },
    },
}), "fresh public runtime-rule API")
T.equal(api.GetRuntimeRules().overridesById[scriptItem.fullName].price, 77,
    "public runtime-rule API applies exact price override")
T.truthy(api.ApplyRuntimeRule({
    blacklist = { "Base.HarnessBlocked" },
    whitelist = { "Base.HarnessWhitelistWins" },
}), "public blacklist and whitelist API")
T.truthy(MarketSense.RuntimeRules.isBlacklisted("Base.HarnessBlocked"),
    "blacklist blocks an exact item")
T.falsy(MarketSense.RuntimeRules.isBlacklisted("Base.HarnessWhitelistWins"),
    "whitelist takes precedence over blacklist decisions")

local context = propertyReader.buildContext(scriptItem, inventoryItem)
T.equal(context.itemType, "Food", "PZ Item.getItemType is read")
T.equal(context.lvlSkillTrained, 3, "PZ Item.getLevelSkillTrained is read")
T.equal(context.description, "Canned preserved bean meal", "inventory description is read")
T.equal(context.weight, 0.5, "live weight overrides script weight")
T.equal(context.conditionMax, 99, "live condition overrides script condition")
T.equal(context.hungerChange, -0.2, "signed hunger change is preserved")
T.equal(context.foodAge, 30, "live food age is read")
T.equal(context.hasRuntimeFoodAge, true, "runtime food age evidence is marked")
T.equal(context.fluidCategories[1], "Beverage", "fluid categories use the supported PZ category list")
T.equal(context.fluidCategories[2], "Liquid", "fluid category membership is preserved")

local function foodDetails()
    return { category = "Food", primary = "Food", tags = { "Food" }, expandedTags = { "Food" } }
end

local function foodContext(age, rotten, extra)
    local context = {
        hungerChange = -0.3,
        thirstChange = 0,
        calories = 600,
        weight = 0.5,
        hasRuntimeFoodAge = true,
        hasRuntimeFoodState = true,
        foodAge = age,
        foodDaysFresh = 2,
        foodDaysRotten = 4,
        isRotten = rotten == true,
        isCantEat = false,
    }
    for key, value in pairs(extra or {}) do context[key] = value end
    return context
end

local freshFood = MarketSense.FoodPricing.calculate(foodContext(0, false), foodDetails())
local staleFood = MarketSense.FoodPricing.calculate(foodContext(3, false), foodDetails())
local rottenFood = MarketSense.FoodPricing.calculate(foodContext(4, true), foodDetails())
T.truthy(freshFood > staleFood, "stale food is cheaper than fresh food")
T.truthy(staleFood > rottenFood, "rotten food is cheaper than stale food")

local longShelfFood = MarketSense.FoodPricing.calculate(
    foodContext(0, false, { foodDaysFresh = 20, foodDaysRotten = 40 }), foodDetails()
)
T.truthy(longShelfFood > freshFood, "longer shelf life raises food value modestly")

local cookedFood = MarketSense.FoodPricing.calculate(
    foodContext(0, false, { isCooked = true }), foodDetails()
)
local burntFood = MarketSense.FoodPricing.calculate(
    foodContext(0, false, { isBurnt = true }), foodDetails()
)
T.truthy(cookedFood > freshFood, "cooked food receives one preparation benefit")
T.truthy(freshFood > burntFood, "burnt food receives one preparation penalty")

local beneficialFood = MarketSense.FoodPricing.calculate(
    foodContext(0, false, { unhappyChange = -10 }), foodDetails()
)
local harmfulFood = MarketSense.FoodPricing.calculate(
    foodContext(0, false, { hungerChange = 0.3, unhappyChange = 10 }), foodDetails()
)
T.truthy(freshFood > harmfulFood, "harmful signed changes lower food value")
T.truthy(beneficialFood > freshFood, "beneficial mood change raises food value")

local literatureContext = {
    fullType = "Base.HarnessSkillBook",
    skillTrained = "Carpentry",
    lvlSkillTrained = 3,
    maxLevelTrained = 5,
    learnedRecipes = { "MakePlank" },
    readType = "normal",
    canBeWrite = false,
    isLiteratureInstance = false,
    boredomChange = -10,
    unhappyChange = -2,
    stressChange = 0,
    weight = 0.2,
}
local literatureDetails = {
    category = "Literature",
    primary = "SkillBook",
    tags = { "SkillBook" },
    expandedTags = { "Literature", "SkillBook" },
    classificationDetails = { source = "lit_skillbook" },
}
local literatureScore = MarketSense.Pricing.calculateRawScore(literatureContext, literatureDetails)
T.equal(literatureDetails.priceHeuristic.model, "literature_v2_pending",
    "literature pricing reset is exposed")
T.equal(literatureDetails.priceHeuristic.status, "pending",
    "literature pricing reset is marked pending")
T.equal(literatureScore, 5, "pending literature pricing uses neutral anchor")
literatureDetails.rawScore = literatureScore
T.equal(MarketSense.Pricing.applyBalances(literatureContext, literatureDetails), 5,
    "pending literature pricing ignores legacy flat additions")

local staleLiterature = MarketSense.Pricing.applyOverridesOnly(literatureContext, {
    fullType = literatureContext.fullType,
    category = "Literature",
    primary = "SkillBook",
    tags = { "SkillBook" },
    rawScore = 999,
    price = 999,
}, true)
T.equal(staleLiterature.priceHeuristic.model, "literature_v2_pending",
    "cached legacy literature score is rebuilt")
T.truthy(staleLiterature.price < 999, "cached legacy literature dollars are discarded")

local clothingContext = {
    fullType = "Base.HarnessJacket",
    bodyLocation = "Jacket",
    bodyLocationToken = "jacket",
    biteDefense = 10,
    scratchDefense = 20,
    bulletDefense = 0,
    insulation = 0.5,
    windResistance = 0.6,
    conditionMax = 10,
    condition = 10,
    conditionRatio = 1,
    weight = 1.0,
    runSpeedModifier = 0.95,
    combatSpeedModifier = 0.9,
}
local clothingDetails = {
    category = "Clothing",
    primary = "ClothingOuterwear",
    tags = { "ClothingOuterwear" },
    expandedTags = { "Clothing", "ClothingOuterwear" },
    classificationDetails = { source = "apparel_bodyloc" },
}
local clothingScore = MarketSense.Pricing.calculateRawScore(clothingContext, clothingDetails)
T.equal(clothingDetails.priceHeuristic.model, "clothing_v2_pending",
    "clothing pricing reset is exposed")
T.equal(clothingDetails.priceHeuristic.status, "pending",
    "clothing pricing reset is marked pending")
T.equal(clothingScore, 4, "pending clothing pricing uses neutral anchor")
clothingDetails.rawScore = clothingScore
T.equal(MarketSense.Pricing.applyBalances(clothingContext, clothingDetails), 4,
    "pending clothing pricing ignores legacy flat additions")

local staleClothing = MarketSense.Pricing.applyOverridesOnly(clothingContext, {
    fullType = clothingContext.fullType,
    category = "Clothing",
    primary = "ClothingOuterwear",
    tags = { "ClothingOuterwear" },
    rawScore = 999,
    price = 999,
}, true)
T.equal(staleClothing.priceHeuristic.model, "clothing_v2_pending",
    "cached legacy clothing score is rebuilt")
T.truthy(staleClothing.price < 999, "cached legacy clothing dollars are discarded")

local containerContext = {
    fullType = "Base.HarnessBackpack",
    capacity = 27,
    weightReduction = 65,
    weight = 1.0,
    conditionMax = 10,
    condition = 10,
    conditionRatio = 1,
    canBeEquipped = "Back",
    bodyLocation = "Back",
    bodyLocationToken = "back",
    isFluidContainer = false,
    isActualLiquid = false,
}
local containerDetails = {
    category = "Container",
    primary = "ContainerBagBackpack",
    tags = { "ContainerBagBackpack" },
    expandedTags = { "Container", "ContainerBag", "ContainerBagBackpack" },
    yieldResolution = {
        status = "resolved",
        recipe = "OpenHarnessBackpack",
        outputs = { { fullType = "Base.Ration", quantity = 2 } },
    },
    classificationDetails = { source = "container_wearable" },
}
local containerScore = MarketSense.Pricing.calculateRawScore(containerContext, containerDetails)
T.equal(containerDetails.priceHeuristic.model, "container_v2_pending",
    "container pricing reset is exposed")
T.equal(containerDetails.priceHeuristic.status, "pending",
    "container pricing reset is marked pending")
T.equal(containerScore, 14, "pending container pricing uses neutral anchor")
T.equal(containerDetails.priceHeuristic.contentYieldOutputCount, 1,
    "container heuristic exposes deterministic content yield evidence")
containerDetails.rawScore = containerScore
T.equal(MarketSense.Pricing.applyBalances(containerContext, containerDetails), 14,
    "pending container pricing ignores legacy flat additions")

local staleContainer = MarketSense.Pricing.applyOverridesOnly(containerContext, {
    fullType = containerContext.fullType,
    category = "Container",
    primary = "ContainerBagBackpack",
    tags = { "ContainerBagBackpack" },
    rawScore = 999,
    price = 999,
}, true)
T.equal(staleContainer.priceHeuristic.model, "container_v2_pending",
    "cached legacy container score is rebuilt")
T.truthy(staleContainer.price < 999, "cached legacy container dollars are discarded")

local toolContext = {
    fullType = "Base.HarnessBlowtorch",
    conditionMax = 100,
    condition = 47,
    conditionRatio = 0.47,
    conditionLowerChance = 10,
    useDelta = 0.0625,
    maxUses = 16,
    currentUsesFloat = 0.75,
    remainingUsesRatio = 0.75,
    weightEmpty = 0.5,
    weight = 1.5,
    mechanicType = 0,
    capacity = 0,
    weightReduction = 0,
    isDrainable = true,
    isDrainableInstance = true,
    canBeEquipped = "",
    isTwoHandWeapon = false,
    acceptItemFunction = "",
}
local toolDetails = {
    category = "Tool",
    primary = "ToolWelding",
    tags = { "ToolWelding" },
    expandedTags = { "Tool", "ToolWelding" },
    classificationDetails = { source = "tool_tag", tag = "blowtorch" },
}
MarketSense.ToolRecipeDemand.setRecipeIndex({
    [toolContext.fullType] = {
        {
            recipe = "WeldHarnessFrame", inputAmount = 1, inputCount = 3,
            inputIndex = 1, reusable = true, toolFlag = false, mode = "keep",
        },
        {
            recipe = "RepairHarness", inputAmount = 1, inputCount = 2,
            inputIndex = 2, reusable = true, toolFlag = true, mode = "keep",
        },
    },
})
local toolScore = MarketSense.Pricing.calculateRawScore(toolContext, toolDetails)
T.equal(toolDetails.priceHeuristic.model, "tool_v2",
    "tool pricing model is exposed")
T.equal(toolDetails.priceHeuristic.status, "ready",
    "tool pricing model is ready")
T.equal(toolDetails.priceHeuristic.recipeDemand.reusableRecipeCount, 2,
    "tool recipe demand counts reusable recipes")
T.equal(toolDetails.priceHeuristic.recipeCriticality, "low",
    "small recipe demand remains low criticality")
T.truthy(toolScore > 14, "recipe demand raises tool score")
T.equal(toolDetails.priceHeuristic.maxUses, 16,
    "tool heuristic exposes total drainable uses")
T.equal(toolDetails.priceHeuristic.remainingUsesRatio, 0.75,
    "tool heuristic exposes remaining drainable uses")
T.equal(toolDetails.priceHeuristic.conditionLowerChance, 10,
    "tool heuristic exposes condition-loss evidence")
toolDetails.rawScore = toolScore
T.equal(MarketSense.Pricing.applyBalances(toolContext, toolDetails),
    MarketSense.Core.round(MarketSense.Core.priceClamp(toolScore)),
    "tool pricing keeps recipe-driven score without legacy flat additions")

local hybridDetails = {
    category = "Weapon",
    primary = "WeaponSmallBlunt",
    tags = { "WeaponSmallBlunt" },
    expandedTags = { "Weapon", "WeaponSmallBlunt" },
    weaponEvidence = { mechanicalClass = "WeaponSmallBlunt" },
}
local hybridScore = MarketSense.Pricing.calculateRawScore(toolContext, hybridDetails)
T.equal(hybridDetails.priceHeuristic.recipeDemand.reusableRecipeCount, 2,
    "weapon/tool hybrids expose reusable recipe demand")
T.truthy(hybridScore > 14,
    "weapon/tool hybrids receive verified recipe utility")

local staleTool = MarketSense.Pricing.applyOverridesOnly(toolContext, {
    fullType = toolContext.fullType,
    category = "Tool",
    primary = "ToolWelding",
    tags = { "ToolWelding" },
    rawScore = 999,
    price = 999,
}, true)
T.equal(staleTool.priceHeuristic.model, "tool_v2",
    "cached legacy tool score is rebuilt")
T.truthy(staleTool.price < 999, "cached legacy tool dollars are discarded")

local details = assert(api.GetPriceDetails(scriptItem.fullName, true))
T.equal(details.category, "Food", "food root")
T.equal(details.primary, "FoodNonPerishableCanned", "description drives canned subtype")
T.equal(details.price, 77, "exact item price override is authoritative")
T.equal(details.stock.min, 2, "item stock override minimum")
T.equal(details.stock.max, 4, "item stock override maximum")
T.equal(type(details.balanceAudit), "table", "audit is present")

local debugDetails = assert(api.DebugItem(scriptItem.fullName, false))
T.equal(debugDetails.availability.status, "uncertain", "debug exposes Lua availability")
T.equal(debugDetails.marketEligible, false, "uncertain item is not market eligible")
T.equal(type(debugDetails.yieldResolution), "table", "debug exposes yield resolution")

local tags = api.GetTags(scriptItem.fullName)
T.equal(tags.primary, details.primary, "public tag primary")
T.equal(tags.category, details.category, "public tag category")
local yieldResolution = api.GetYieldResolution(scriptItem.fullName)
T.equal(type(yieldResolution), "table", "public yield resolver")
T.equal(yieldResolution.status, "not_detected", "public yield resolver status")

api.ClearRuntimeCache()
local withoutAudit = assert(api.GetPriceDetails(scriptItem.fullName, false))
T.falsy(withoutAudit.balanceAudit, "non-audit result does not include audit")
local withAudit = assert(api.GetPriceDetails(scriptItem.fullName, true))
T.equal(type(withAudit.balanceAudit), "table", "audit cache miss is repaired")

T.falsy(api.GetPriceDetails(nil), "invalid full type is rejected")
T.equal(type(api.IsItemRuntimeDebugEnabled()), "boolean", "debug API is boolean")

local fullCondition = assert(api.GetPriceDetailsForInstance(
    weaponScriptItem.fullName, weaponInstance(100), true
))
local halfCondition = assert(api.GetPriceDetailsForInstance(
    weaponScriptItem.fullName, weaponInstance(50), true
))
local brokenCondition = assert(api.GetPriceDetailsForInstance(
    weaponScriptItem.fullName, weaponInstance(0), true
))
T.equal(fullCondition.primary, "WeaponSpear", "instance pricing keeps spear leaf")
T.equal(fullCondition.weaponEvidence.mechanicalClass, "WeaponSpear", "instance exposes melee evidence")
T.equal(fullCondition.priceHeuristic.model, "weapon_v2_pending", "weapon pricing reset is exposed")
T.equal(fullCondition.priceHeuristic.status, "pending", "weapon pricing reset is marked pending")
T.equal(fullCondition.price, halfCondition.price, "pending weapon pricing ignores legacy condition score")
T.equal(halfCondition.price, brokenCondition.price, "pending weapon pricing remains neutral")
T.equal(fullCondition.priceHeuristic.conditionRatio, 1, "full condition ratio is visible")
T.equal(halfCondition.priceHeuristic.conditionRatio, 0.5, "half condition ratio is visible")

local staleWeapon = MarketSense.Pricing.applyOverridesOnly(weaponScriptItem.fullName, {
    fullType = weaponScriptItem.fullName,
    category = "Weapon",
    primary = "WeaponSpear",
    tags = { "WeaponSpear" },
    rawScore = 999,
    price = 999,
}, true)
T.equal(staleWeapon.priceHeuristic.model, "weapon_v2_pending",
    "cached legacy weapon score is rebuilt")
T.truthy(staleWeapon.price < 999, "cached legacy weapon dollars are discarded")

registry.state.catalog = {
    items = {
        [scriptItem.fullName] = {
            fullType = scriptItem.fullName,
            category = details.category,
            primary = details.primary,
            price = details.price,
        },
    },
}
local registryDetail = assert(api.GetRegistryDetails(scriptItem.fullName))
T.equal(registryDetail.primary, details.primary, "registry detail lookup")
local allKnown = api.GetAllKnownItems()
T.truthy(allKnown[scriptItem.fullName], "registry known-item lookup")
allKnown[scriptItem.fullName].price = -1
T.truthy(registry.state.catalog.items[scriptItem.fullName].price > 0, "registry returns a copy")

local previousEnsureLoaded = registry.ensureLoaded
local receivedForce
registry.ensureLoaded = function(force)
    receivedForce = force
    return "mock-catalog"
end
T.equal(api.EnsureRuntimeRegistryLoaded(true), "mock-catalog", "registry load wrapper result")
T.equal(receivedForce, true, "registry force flag is forwarded")
registry.ensureLoaded = previousEnsureLoaded

T.finish("marketsense_api_smoke")
