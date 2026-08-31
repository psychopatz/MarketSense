local T = require "tests/support/test"
T.addPackagePaths()

local classifier = assert(T.load("MarketSense/signatures/tags/MS_Classifier.lua"))
local mapper = assert(MarketSense.TagMapper)
local postLabelResolver = assert(T.load("MarketSense/signatures/tags/MS_PostLabelResolver.lua"))

local function context(id, props)
    props = props or {}
    local tags = props.tags or {}
    local normalizedTags = {}
    for _, tag in ipairs(tags) do
        local suffix = string.lower(tostring(tag)):match("([^:.]+)$") or tostring(tag)
        suffix = string.gsub(suffix, "[^%w]", "")
        normalizedTags[suffix] = true
        normalizedTags["base" .. suffix] = true
    end
    local displayCategory = string.lower(props.displayCategory or "")
    local itemType = string.lower(props.itemType or "")
    local foodType = string.lower(props.foodType or "")
    return {
        fullType = "Base." .. id,
        fullLower = string.lower("Base." .. id), idLower = string.lower(id),
        displayNameLower = string.lower(props.displayName or id),
        descriptionLower = string.lower(props.description or ""),
        iconLower = string.lower(props.icon or ""), tooltipLower = "",
        displayCategoryLower = displayCategory,
        displayCategoryToken = displayCategory,
        itemTypeLower = itemType,
        itemTypeToken = itemType:match("([^:.]+)$") or "",
        foodTypeLower = foodType,
        foodTypeToken = foodType:match("([^:.]+)$") or "",
        lootTypeLower = string.lower(props.lootType or ""),
        tags = tags, normalizedTags = normalizedTags,
        weaponCategories = props.weaponCategories or {}, learnedRecipes = {},
        capabilitySet = props.capabilitySet or {}, capabilityRequirements = {},
        worldObjectEvidence = props.worldObjectEvidence,
        worldObjectSpriteLower = string.lower(props.worldObjectSprite or ""),
        isMoveable = props.isMoveable == true, isCraftRecipeProduct = props.isCraftRecipeProduct == true,
        isFluidContainer = false, isActualLiquid = false, isFoodInstance = props.isFoodInstance == true,
        isCannedFood = false, isPackaged = false, canAge = false,
        isCantEat = props.isCantEat == true, isDrainable = props.isDrainable == true,
        hasFoodNutritionEvidence = props.hasFoodNutritionEvidence == true,
        hasFoodRecipeEvidence = props.hasFoodRecipeEvidence == true,
        hasFoodSpoilageEvidence = props.hasFoodSpoilageEvidence == true,
        foodDaysFresh = props.foodDaysFresh or 0, foodDaysRotten = props.foodDaysRotten or 0,
        evolvedRecipeLower = string.lower(props.evolvedRecipe or ""),
        isSpice = props.isSpice == true, moduleName = props.moduleName or "Base",
        minDamage = props.minDamage or 0, maxDamage = props.maxDamage or 0,
        capacity = props.capacity or 0,
    }
end

local function expect(id, props, primary, path, source)
    local result = assert(classifier.classify(context(id, props)))
    T.equal(result.primary, primary, id .. " primary")
    local definition = mapper.getDefinition(result.primary)
    local categoryPath = definition.root .. "/" .. definition.subcategory
        .. "/" .. definition.leaf .. ".txt"
    T.equal(categoryPath, path, id .. " hierarchy")
    if source then
        T.equal((result.details or {}).source, source, id .. " evidence source")
    end
end

local function expectFinal(id, props, primary, path)
    local ctx = context(id, props)
    local result = assert(classifier.classify(ctx))
    local final = assert(postLabelResolver.correct(ctx, result))
    T.equal(final.primary, primary, id .. " final primary")
    local definition = mapper.getDefinition(final.primary)
    local categoryPath = definition.root .. "/" .. definition.subcategory
        .. "/" .. definition.leaf .. ".txt"
    T.equal(categoryPath, path, id .. " final hierarchy")
end

expect("IronBar", {
    itemType = "base:weapon", displayCategory = "MaterialWeapon",
    tags = { "Base:hasmetal", "Base:ironmaterial", "Base:barstock" }, maxDamage = 0.4,
}, "MaterialMetalworking", "Resource/Material/Metalworking.txt", "material_tag_ironmaterial")

expect("BowlingPin", {
    itemType = "base:weapon", displayCategory = "SportsWeapon",
    tags = { "Base:nomaintenancexp" }, weaponCategories = { "Base:improvised", "Base:smallblunt" },
    maxDamage = 0.9,
}, "WeaponSmallBlunt", "Weapon/Melee/SmallBlunt.txt", "weapon_melee")

expect("Cooler", {
    itemType = "base:container", displayCategory = "Container", capacity = 12,
}, "ContainerCooler", "Container/Cooler/Cooler.txt", "container_cooler_name")

expect("Remote", {
    itemType = "base:normal", displayCategory = "Electronics",
}, "ElectronicsControl", "Electronics/Control/Control.txt", "electronics_control_name")

expect("CarBattery1", {
    itemType = "base:weapon", displayCategory = "VehicleMaintenance",
    displayName = "Car Battery", maxDamage = 1.5,
}, "ElectronicsBattery", "Electronics/Battery/Battery.txt", "electronics_battery")

expect("Lighter_Battery", {
    itemType = "base:weapon", displayCategory = "FireSource",
    displayName = "Lighter - Improvised Battery", maxDamage = 1.5,
}, "ElectronicsBattery", "Electronics/Battery/Battery.txt", "electronics_battery")

expect("CarBatteryCharger", {
    itemType = "base:normal", displayCategory = "VehicleMaintenance",
    displayName = "Car Battery Charger",
}, "ToolMechanics", "Tool/Mechanics/Mechanics.txt", "tool_vehiclemaint")

expect("MeasuringTape", {
    itemType = "base:normal", displayCategory = "Tool",
}, "ToolMeasurement", "Tool/Measurement/Measurement.txt", "tool_measurement_name")

expect("GardeningSprayAphids", {
    itemType = "base:drainable", displayCategory = "Gardening",
}, "GardeningPestControl", "Building/Gardening/PestControl.txt", "gardening_spray_name")

expect("HandShovel", {
    itemType = "base:weapon", displayCategory = "Gardening",
    tags = { "Base:sharpenable", "Base:digplow" }, weaponCategories = { "Base:smallblade" },
    maxDamage = 0.4,
}, "ToolGardening", "Tool/Gardening/Gardening.txt", "tool_tag")

expect("HollowBook_Handgun", {
    itemType = "base:container", displayCategory = "Literature",
    tags = { "Base:hollowbook" }, capacity = 2,
}, "LiteratureHollowBookHandgun", "Literature/HollowBook/Handgun.txt", "lit_hollow_book_variant")

expect("FishingHook", {
    itemType = "base:normal", displayCategory = "Fishing",
    tags = { "Base:fishinghook" },
}, "MiscFishing", "Misc/Fishing/Fishing.txt", "misc_display_or_fishing_tag")

local material = classifier.classify(context("IronBar", {
    itemType = "base:weapon", displayCategory = "MaterialWeapon",
    tags = { "Base:ironmaterial" }, maxDamage = 0.4,
}))
T.equal(material.category, "Resource", "material weapon never becomes Weapon")

expectFinal("CookiesSugar", {
    itemType = "base:food", displayCategory = "Food", isFoodInstance = true,
    hasFoodNutritionEvidence = true,
}, "FoodNonPerishableBaking", "Food/NonPerishable/Baking.txt")

expectFinal("Popcorn", {
    itemType = "base:food", displayCategory = "Food", isFoodInstance = true,
    hasFoodNutritionEvidence = true,
}, "FoodNonPerishableSnack", "Food/NonPerishable/Snack.txt")

expectFinal("Acorn", {
    itemType = "base:food", displayCategory = "Food", foodType = "Nut",
    isFoodInstance = true, hasFoodNutritionEvidence = true,
    evolvedRecipe = "Soup:10;Bread:10",
}, "FoodNut", "Food/NonPerishable/Nut.txt")

expectFinal("Poppies", {
    itemType = "base:food", displayCategory = "Gardening", isCantEat = true,
    foodDaysFresh = 6,
}, "GardeningHarvest", "Building/Gardening/Harvest.txt")

expectFinal("GrassTuft", {
    itemType = "base:food", displayCategory = "Food", isCantEat = true,
    tags = { "Base:farmingloot" },
}, "BuildingAgricultureHay", "Building/Agriculture/Hay.txt")

expectFinal("Tobacco", {
    itemType = "base:food", displayCategory = "Tool", isCantEat = true,
    foodDaysFresh = 7,
}, "Smoking", "Tool/Smoking/Smoking.txt")

expectFinal("CorpseAnimal", {
    itemType = "base:food", displayCategory = "Corpse",
    tags = { "Base:animalcorpse" }, foodDaysFresh = 5,
}, "MaterialButchering", "Resource/Material/Butchering.txt")

expectFinal("HotDrink", {
    itemType = "base:food", displayCategory = "Food",
    tags = { "Base:herbaltea" }, isFoodInstance = true,
    hasFoodNutritionEvidence = true,
}, "FoodTea", "Food/NonPerishable/Tea.txt")

expectFinal("RatPoison", {
    itemType = "base:drainable", displayCategory = "Household", isDrainable = true,
}, "MiscSafety", "Misc/Safety/Safety.txt")

expect("RagFilter", {
    itemType = "base:drainable", displayCategory = "Accessory", isDrainable = true,
    tags = { "Base:ragfilter" },
}, "MiscSafety", "Misc/Safety/Safety.txt", "misc_safety_tag_or_name")

expectFinal("AKFlower", {
    moduleName = "NnC", itemType = "base:food", displayCategory = "Drugs",
    isCantEat = true, isFoodInstance = true,
}, "Smoking", "Tool/Smoking/Smoking.txt")

expectFinal("WeedBaggieAK", {
    moduleName = "NnC", itemType = "base:drainable", displayCategory = "Drugs",
    isDrainable = true, tags = { "NnC:WeedJar" },
}, "Smoking", "Tool/Smoking/Smoking.txt")

expectFinal("Xanax", {
    moduleName = "NnC", itemType = "base:drainable", displayCategory = "Drugs",
    isDrainable = true, tags = { "Base:Consumable", "NnC:Benzos" },
}, "MaterialChemical", "Resource/Material/Chemical.txt")

expectFinal("CrackBaggie", {
    moduleName = "NnC", itemType = "base:drainable", displayCategory = "Drugs",
    isDrainable = true, isCantEat = true, tags = { "NnC:Cocaine" },
}, "MaterialChemical", "Resource/Material/Chemical.txt")

expectFinal("HeroinNo2Pot", {
    moduleName = "NnC", itemType = "base:food", displayCategory = "Drugs",
    isCantEat = true,
}, "MaterialChemical", "Resource/Material/Chemical.txt")

expectFinal("MethPyrexDishUncooked", {
    moduleName = "NnC", itemType = "base:food", displayCategory = "Drugs",
    isCantEat = true,
}, "MaterialChemical", "Resource/Material/Chemical.txt")

expect("MethBeaker", {
    moduleName = "NnC", itemType = "base:normal", displayCategory = "Drugs",
    icon = "NnC_MethBeaker",
}, "ToolUtility", "Tool/Utility/Utility.txt", "tool_utility_name")

expectFinal("MushroomSpores", {
    moduleName = "NnC", itemType = "base:normal", displayCategory = "Drugs",
}, "GardeningSeed", "Building/Gardening/Seed.txt")

expect("Grinder", {
    moduleName = "NnC", itemType = "base:normal", displayCategory = "Drugs",
    tags = { "NnC:Grinder" }, icon = "NnC_Grinder",
}, "ToolUtility", "Tool/Utility/Utility.txt", "tool_utility_name")

expectFinal("MakeupCase_Professional", {
    itemType = "base:container", displayCategory = "Container", capacity = 2,
}, "ContainerBox", "Container/Box/Box.txt")

T.finish("marketsense_subcategory_smoke")
