local T = require "tests/support/test"
T.addPackagePaths()

local Runtime = require "MarketSense/MS_Config"
local Config = MarketSense.Config
local Pricing = require "MarketSense/MS_Pricing"
local Core = require "MarketSense/MS_Core"
local Cache = require "MarketSense/MS_RuntimeCache"
local Evidence = require "MarketSense/MS_FoodVariantEvidence"
local Shared = require "MarketSense/ItemsRegistry/MS_ItemsRegistry_Shared"

local function evaluate(category, primary, context)
    local details = {
        category = category,
        primary = primary,
        tags = { primary },
        expandedTags = { category, primary },
        classificationDetails = { source = "pricing_tuning_smoke" },
    }
    local score = Pricing.calculateRawScore(context or {}, details)
    return score, details
end

local function readyContext(extra)
    local context = {
        fullType = "Base.PricingTuningItem",
        weight = 0.5,
        conditionMax = 100,
        condition = 100,
        conditionRatio = 1,
        hasRuntimeState = true,
        isRotten = false,
        isPoison = false,
        isBurnt = false,
        isDung = false,
    }
    for key, value in pairs(extra or {}) do context[key] = value end
    return context
end

Runtime.sandboxVars = nil
Config.applySandboxOptions()
Runtime.pricing.variationEnabled = false
Runtime.pricing.contrastStrength = 0
Runtime.pricing.baseMultiplier = 1

local intrinsicHashBeforePolicyChange = Shared.buildIntrinsicConfigHash()
_G.SandboxVars = { MarketSense = {
    PriceMultiplierPercent = 35,
    PriceVariationPercent = 10,
    PriceFoodOpenedMultiplierPercent = 65,
    PriceFoodSealedPreservationPercent = 150,
    PriceVesselCapacityValue = 7,
    PriceCategoryFoodMin = 80,
}}
Config.applySandboxOptions()
T.equal(Shared.buildIntrinsicConfigHash(), intrinsicHashBeforePolicyChange,
    "sandbox policy changes do not invalidate intrinsic cache inputs")
_G.SandboxVars = nil
Config.applySandboxOptions()
Runtime.pricing.variationEnabled = false
Runtime.pricing.contrastStrength = 0
Runtime.pricing.baseMultiplier = 1

T.equal(Runtime.pricing.maxPrice, nil,
    "Lua pricing defaults do not impose a global price cap")
T.equal(Runtime.pricing.categoryBands.Container.response, 80,
    "container currency band is calibrated for ordinary vessels")
T.falsy(Config.reloadExported(),
    "generated pricing exports are not runtime inputs")

local categoryCases = {
    { "Food", "FoodStaple", { hungerChange = -0.3, calories = 600 } },
    { "Weapon", "WeaponMelee", { minDamage = 1, maxDamage = 2, maxRange = 1,
        maxHit = 2, hitChance = 10, weight = 1 } },
    { "Tool", "ToolMechanics", { conditionMax = 100, conditionRatio = 1,
        mechanicType = 2, weight = 1 } },
    { "Container", "ContainerBagBackpack", { capacity = 27,
        weightReduction = 65, canBeEquipped = "Back", weight = 1 } },
    { "Clothing", "ClothingOuterwear", { biteDefense = 10,
        scratchDefense = 20, insulation = 0.5, weight = 1 } },
    { "Electronics", "ElectronicsRadio", { deviceData = {
        isTwoWay = true, isPortable = true, transmitRange = 250,
    }, capabilities = { "radio_communication" }, weight = 1 } },
    { "Medical", "FirstAid", { canBandage = true, bandagePower = 1,
        reduceInfectionPower = 1, useDelta = 1, maxUses = 1 } },
    { "Literature", "SkillBook", { skillTrained = "Carpentry",
        lvlSkillTrained = 3, maxLevelTrained = 5, learnedRecipes = { "MakePlank" } } },
    { "Liquid", "LiquidWater", { fluidAmount = 12, thirstChange = -0.3,
        fluidTypeString = "Water" } },
    { "Resource", "MaterialMetalworking", { typeName = "IronIngot",
        idLower = "ironingot", displayNameLower = "iron ingot", weight = 1 } },
    { "Building", "BuildingFurnitureStorage", { isMoveable = true,
        worldObjectEvidence = { available = true, containerCapacity = 24 },
        capabilities = { capabilities = { "storage_surface" } }, capacity = 24 } },
    { "Misc", "MiscFishing", { isFishingLure = true, weight = 0.1 } },
}

for _, entry in ipairs(categoryCases) do
    local category, primary, values = entry[1], entry[2], entry[3]
    local score, details = evaluate(category, primary, readyContext(values))
    T.truthy(score >= 1, category .. " has a non-zero price score")
    T.equal(details.priceHeuristic.status, "ready",
        category .. " pricing heuristic is ready")
end

local nutritious = evaluate("Food", "FoodStaple", readyContext({
    hungerChange = -0.3, calories = 600,
}))
local harmful = evaluate("Food", "FoodStaple", readyContext({
    hungerChange = 0.3, calories = 0, isPoison = true,
}))
T.truthy(nutritious > harmful, "food utility outranks harmful nutrition")

local strongWeapon = evaluate("Weapon", "WeaponMelee", readyContext({
    minDamage = 2, maxDamage = 4, maxRange = 2, maxHit = 3, hitChance = 10,
}))
local weakWeapon = evaluate("Weapon", "WeaponMelee", readyContext({
    minDamage = 0.1, maxDamage = 0.2, maxRange = 0.5, maxHit = 1,
    hitChance = 1,
}))
T.truthy(strongWeapon > weakWeapon, "weapon performance orders within the family")

local stored = evaluate("Container", "ContainerBagBackpack", readyContext({
    capacity = 27, weightReduction = 65, canBeEquipped = "Back",
}))
local emptyContainer = evaluate("Container", "ContainerBox", readyContext({
    capacity = 0, weightReduction = 0, canBeEquipped = "",
}))
T.truthy(stored > emptyContainer, "container storage evidence raises value")

local worldStorage = evaluate("Building", "BuildingFurnitureStorage", readyContext({
    capacity = 24,
    worldObjectEvidence = { available = true, containerCapacity = 24 },
    capabilities = { capabilities = { "storage_surface" } },
}))
local abstractStorage = evaluate("Building", "BuildingFurnitureStorage", readyContext({
    capacity = 24,
    worldObjectEvidence = { available = false },
    capabilities = { capabilities = {} },
}))
T.truthy(worldStorage > abstractStorage,
    "building capacity is counted only with world-object evidence")

local fresh = evaluate("Food", "FoodStaple", readyContext({
    hungerChange = -0.3, calories = 600, hasRuntimeFoodAge = true,
    foodAge = 0, foodDaysFresh = 2, foodDaysRotten = 4,
})); fresh = fresh
local rotten = evaluate("Food", "FoodStaple", readyContext({
    hungerChange = -0.3, calories = 600, hasRuntimeFoodAge = true,
    foodAge = 4, foodDaysFresh = 2, foodDaysRotten = 4, isRotten = true,
})); rotten = rotten
T.truthy(fresh > rotten, "runtime freshness and rotten penalties are applied")

local hugeFood = evaluate("Food", "FoodStaple", readyContext({
    hungerChange = -20, calories = 100000, weight = 0,
}))
T.truthy(hugeFood > 250, "high-value food is not flattened by a category ceiling")

local uncappedDetails = {
    category = "Food",
    primary = "FoodStaple",
    tags = { "FoodStaple" },
    expandedTags = { "Food", "FoodStaple" },
    rawScore = 999,
    priceHeuristic = { aggregateCeiling = 180, stateFactor = 1 },
}
local uncapped = Pricing.applyBalances(readyContext(), uncappedDetails)
T.truthy(uncapped > Runtime.pricing.categoryBands.Food.max,
    "aggregate price can overflow the normal category band")

local cachedSnapshot = {
    fullType = "Base.CachedPolicyItem",
    moduleName = "Base",
    typeName = "CachedPolicyItem",
    category = "Food",
    primary = "FoodStaple",
    tags = { "FoodStaple" },
    expandedTags = { "Food", "FoodStaple" },
    intrinsicScore = 100,
    stockRange = { min = 1, max = 4 },
}
Runtime.pricing.variationEnabled = false
Runtime.pricing.baseMultiplier = 1
local originalContextBuilder = MarketSense.PropertyReader.buildContext
MarketSense.PropertyReader.buildContext = function()
    error("cached finalization must not rebuild PropertyReader context")
end
local cachedPrice = Pricing.finalizeIntrinsicSnapshot(cachedSnapshot, false).price
Runtime.pricing.baseMultiplier = 2
local policyPrice = Pricing.finalizeIntrinsicSnapshot(cachedSnapshot, false).price
MarketSense.PropertyReader.buildContext = originalContextBuilder
T.equal(policyPrice, cachedPrice * 2,
    "cached intrinsic score is finalized with the current policy")
Runtime.pricing.baseMultiplier = 1

Runtime.sandboxVars = {
    PriceSubcategoryFoodNonPerishableValue = 40,
}
local subcategoryValue, subcategorySummary = require("MarketSense/Pricing/MS_MarketModifiers").apply(
    readyContext({ fullType = "Base.SubcategoryValue" }),
    {
        category = "Food",
        subcategory = "NonPerishable",
        primary = "FoodStaple",
        tags = {},
        expandedTags = {},
    },
    20
)
T.equal(subcategoryValue, 60,
    "subcategory pricing is an additive semantic adjustment")
T.equal(subcategorySummary.subcategoryAdd, 40,
    "subcategory addition is exposed in the modifier summary")
Runtime.sandboxVars = nil

local baseDetails = {
    category = "Literature", primary = "Literature", tags = {}, expandedTags = {},
    rawScore = 100, priceHeuristic = { anchor = 100, stateFactor = 1 },
}
local basePrice = Pricing.applyBalances(readyContext(), baseDetails)
_G.SandboxVars = { MarketSense = {
    PriceMultiplierPercent = 25,
    PriceContrastPercent = 20,
    PriceVariationPercent = 12,
    PriceFoodOpenedMultiplierPercent = 70,
    PriceFoodSealedPreservationPercent = 125,
    PriceVesselEnabled = false,
    PriceVesselBaseValue = 12,
    PriceVesselCapacityValue = 8,
    PriceVesselOpenedPenalty = 4,
    PriceCategoryFoodMin = 100,
    PriceCategoryFoodMax = 600,
}}
Config.applySandboxOptions()
T.equal(Runtime.pricing.baseMultiplier, 1.25,
    "integer global percentage becomes a neutral-centered multiplier")
T.equal(Runtime.pricing.contrastStrength, 0.20,
    "integer contrast percentage becomes the internal fraction")
T.equal(Runtime.pricing.variationStrength, 0.12,
    "integer variation percentage becomes the internal fraction")
T.equal(Runtime.foodPricing.openedPenalty, 0.70,
    "integer opened-food percentage becomes the internal penalty")
T.equal(Runtime.foodPricing.sealedPreservationMultiplier, 1.25,
    "integer sealed-preservation percentage becomes the internal premium")
T.equal(Runtime.vesselPricing.enabled, false,
    "vessel pricing enable option is applied")
T.equal(Runtime.vesselPricing.baseValue, 12,
    "integer vessel base value remains an integer dollar addition")
T.equal(Runtime.vesselPricing.capacityValue, 8,
    "integer vessel capacity value is applied")
T.equal(Runtime.vesselPricing.openedPenalty, 4,
    "integer opened-vessel penalty is applied")
T.equal(Runtime.pricing.categoryBands.Food.min, 100,
    "category band minimum is sandbox configurable")
T.equal(Runtime.pricing.categoryBands.Food.max, 600,
    "category band maximum is sandbox configurable")
_G.SandboxVars = nil
Config.applySandboxOptions()
_G.SandboxVars = { MarketSense = {
    PriceMultiplier = 2,
    PriceContrastStrength = 0.25,
    PriceVariationEnabled = false,
}}
Config.applySandboxOptions()
T.equal(Runtime.pricing.baseMultiplier, 2,
    "existing sandbox multiplier remains compatible")
T.equal(Runtime.pricing.contrastStrength, 0.25,
    "existing sandbox contrast option remains compatible")
local doubledPrice = Pricing.applyBalances(readyContext(), baseDetails)
T.equal(doubledPrice, basePrice * 2, "sandbox multiplier is applied exactly once")
_G.SandboxVars = nil
Config.applySandboxOptions()

local nonFoodJar = {
    fullType = "Base.CannedStorageJar",
    itemTypeToken = "normal",
    displayCategory = "Container",
    displayName = "Canned Storage Jar",
    isCannedFood = false,
    isPackaged = false,
    tags = {},
    normalizedTagList = {},
}
local candidateCalled = false
Evidence.apply(nonFoodJar, function()
    candidateCalled = true
end, { status = "not_detected" })
T.falsy(candidateCalled,
    "container named like a jar is not treated as food variant evidence")

local sealed = {
    fullType = "Base.CannedNameOnly",
    itemTypeToken = "food",
    displayCategory = "Food",
    isCannedFood = true,
    isPackaged = true,
    foodType = "Vegetable",
    hungerChange = -0.2,
    hunger = 0.2,
    thirstChange = 0,
    thirst = 0,
    unhappyChange = 0,
    unhappy = 0,
    boredomChange = 0,
    boredom = 0,
    stressChange = 0,
    stress = 0,
    calories = 100,
    carbohydrates = 10,
    lipids = 2,
    proteins = 3,
}
local opened = {
    fullType = "Base.CannedNameOnlyOpen",
    itemTypeToken = "food",
    displayCategory = "Food",
    foodType = "Fruit",
    hungerChange = -0.4,
    calories = 999,
    carbohydrates = 90,
    lipids = 20,
    proteins = 30,
    isObsolete = false,
}
Evidence.apply(sealed, function(fullType)
    return fullType == opened.fullType and opened or nil
end, { status = "not_detected" })
T.equal(sealed.calories, 100,
    "name-only opened variant cannot overwrite canonical nutrition")
T.equal(sealed.foodVariantEvidence.authority, "name_hint",
    "name-only opened variant records weaker authority")
T.equal(sealed.foodVariantEvidence.status, "corroborated",
    "name-only variant remains diagnostic when it adds no fields")

local originalRevision = Runtime.pricingRevision
Cache.clear()
Cache.setDetails("Base.PricingCache", { price = 12 })
T.truthy(Cache.getDetails("Base.PricingCache"), "pricing detail cache stores a result")
Runtime.pricingRevision = originalRevision + 1
T.falsy(Cache.getDetails("Base.PricingCache"),
    "pricing revision invalidates cached details")
Runtime.pricingRevision = originalRevision
Cache.clear()

local Registry = assert(MarketSense.ItemsRegistry)
T.equal(Registry.REBUILD_BUDGET_MS, 3,
    "deferred registry keeps its cooperative time budget")
T.truthy(type(require("MarketSense/ItemsRegistry/MS_ItemsRegistry_Runtime").scheduleRebuild)
    == "function", "deferred registry scheduler remains available")

T.finish("marketsense_pricing_tuning_smoke")
