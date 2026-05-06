-- MS_TagMapper.lua
-- Flat token taxonomy for MarketSense.
-- Each item is classified into a flat display token (e.g. "WeaponAxe", "FoodPerishableMeat").
-- TOKEN_TO_ROOT maps each token to its root category (the top-level grouping).
-- TOKEN_PARENTS maps each token to its immediate parents for pricing hierarchy expansion.

MarketSense = MarketSense or {}
MarketSense.TagMapper = MarketSense.TagMapper or {}

local TagMapper = MarketSense.TagMapper

-- ============================================================
-- Root category lookup: flat token → top-level category name
-- ============================================================
local TOKEN_TO_ROOT = {
    -- Weapon
    Ammo = "Weapon", AmmoBox = "Weapon", AmmoCarton = "Weapon", AmmoMag = "Weapon",
    WeaponAxe = "Weapon", WeaponBlunt = "Weapon", WeaponSmallBlunt = "Weapon",
    WeaponLongBlade = "Weapon", WeaponSmallBlade = "Weapon",
    WeaponSpear = "Weapon", WeaponCrafted = "Weapon", BrokenWeapon = "Weapon",
    WeaponMelee = "Weapon", WeaponRanged = "Weapon",
    Firearm = "Weapon", FirearmHandgun = "Weapon", FirearmRifle = "Weapon", FirearmShotgun = "Weapon",
    Explosive = "Weapon", WeaponExplosive = "Weapon", WeaponPart = "Weapon",
    -- Beverage
    Beverage = "Beverage",
    BeverageWater = "Beverage", BeverageMilk = "Beverage", BeverageCoffee = "Beverage",
    BeverageTea = "Beverage", BeverageSoftDrink = "Beverage", BeverageJuice = "Beverage",
    BeverageBeer = "Beverage", BeverageWine = "Beverage", BeverageAlcohol = "Beverage",
    BeverageCocktail = "Beverage", BeverageEnergyDrink = "Beverage", BeverageBox = "Beverage",
    -- Clothing
    ClothingFullBody = "Clothing", ClothingOuterwear = "Clothing", ClothingVest = "Clothing",
    ClothingTop = "Clothing", ClothingBottom = "Clothing", ClothingFootwear = "Clothing",
    ClothingSocks = "Clothing", ClothingHead = "Clothing", ClothingHands = "Clothing",
    ClothingUnderwear = "Clothing",
    Accessory = "Clothing", AccessoryNeck = "Clothing", AccessoryLegs = "Clothing",
    AccessoryTop = "Clothing", AccessoryArms = "Clothing", AccessoryHands = "Clothing",
    AccessoryHead = "Clothing", AccessoryFace = "Clothing", AccessoryJewelry = "Clothing",
    ProtectiveGear = "Clothing", ProtectiveGearLegs = "Clothing", ProtectiveGearTop = "Clothing",
    ProtectiveGearArms = "Clothing", ProtectiveGearHands = "Clothing",
    ProtectiveGearHead = "Clothing", ProtectiveGearFace = "Clothing",
    -- Container
    Container = "Container", ContainerWearable = "Container", ContainerWearableAmmo = "Container",
    ContainerAmmo = "Container", ContainerLiquid = "Container", ContainerBox = "Container",
    KeyRing = "Container", MementoOrContainer = "Container",
    -- Food root tokens
    Food = "Food", FoodNonPerishable = "Food", FoodPerishable = "Food",
    -- Food non-perishable
    FoodBaking = "Food", FoodCandy = "Food", FoodCheese = "Food", FoodCoffee = "Food",
    FoodEgg = "Food", FoodFruits = "Food", FoodHerb = "Food", FoodLivestock = "Food",
    FoodMeat = "Food", FoodMushroom = "Food", FoodNoExplicit = "Food", FoodNut = "Food",
    FoodPetFood = "Food", FoodPreserved = "Food", FoodSnack = "Food", FoodSpice = "Food",
    FoodStaple = "Food", FoodStock = "Food", FoodTea = "Food", FoodVegetables = "Food",
    FoodNonPerishableCanned = "Food", FoodNonPerishableSnack = "Food",
    -- Food perishable
    FoodDish = "Food", FoodPortion = "Food", FoodSeafood = "Food",
    FoodPerishableBaking = "Food", FoodPerishableCandy = "Food", FoodPerishableCheese = "Food",
    FoodPerishableDairy = "Food", FoodPerishableBread = "Food", FoodPerishableDish = "Food",
    FoodPerishableFruits = "Food", FoodPerishableMeat = "Food", FoodPerishableSeafood = "Food",
    FoodPerishableSnack = "Food", FoodPerishableMeal = "Food",
    FoodOrFirstAid = "Medical",
    -- Cooking (under Tool)
    Cooking = "Tool", CookingCup = "Tool", CookingPan = "Tool",
    CookingCutlery = "Tool", CookingUtensil = "Tool", CookingOrTool = "Tool",
    -- Tool
    Tool = "Tool", ToolCraft = "Tool", ToolOrJunk = "Tool",
    ToolBlacksmith = "Tool", ToolButchering = "Tool", ToolCarpentry = "Tool",
    ToolFlintKnapping = "Tool", ToolGardening = "Tool", ToolMaintenance = "Tool",
    ToolMasonry = "Tool", ToolMechanics = "Tool", ToolPottery = "Tool",
    ToolTailoring = "Tool", ToolWelding = "Tool", ToolFarming = "Tool",
    Smoking = "Tool",
    -- Material / Resource
    Material = "Resource", ResourceFuel = "Resource",
    MaterialMetalworking = "Resource", MaterialTailoring = "Resource",
    MaterialPottery = "Resource", MaterialCarpentry = "Resource",
    MaterialMaintenance = "Resource", MaterialButchering = "Resource",
    MaterialFireSource = "Resource", MaterialOrJunk = "Resource", MaterialBundled = "Resource",
    MaterialHardware = "Resource", MaterialWood = "Resource", MaterialChemical = "Resource",
    ResourceMetal = "Resource", ResourceFabric = "Resource", ResourceMaterial = "Resource",
    ResourceHardware = "Resource",
    -- Medical
    Medical = "Medical", FirstAid = "Medical", Bandage = "Medical",
    -- Literature
    Literature = "Literature", SkillBook = "Literature",
    LiteratureHardcover = "Literature", LiteratureFancyBook = "Literature",
    LiteratureSoftcover = "Literature", LiteratureMagazine = "Literature",
    LiteratureNewspaper = "Literature", LiteratureOrJunk = "Literature",
    LiteratureConsumable = "Literature", LiteraturePhoto = "Literature",
    LiteraturePictureBook = "Literature", LiteratureRecipe = "Literature",
    LiteratureComic = "Literature", LiteratureAdult = "Literature",
    LiteratureBrochure = "Literature", LiteratureFlier = "Literature",
    LiteratureRpgManual = "Literature",
    -- Gardening / Building seeds
    Gardening = "Building", GardeningSeed = "Building",
    GardeningSeedPacket = "Building", GardeningCompostable = "Building",
    -- Electronics (MarketSense-specific)
    Electronics = "Electronics",
    ElectronicsBattery = "Electronics", ElectronicsGenerator = "Electronics",
    ElectronicsRadio = "Electronics", ElectronicsTelevision = "Electronics",
    ElectronicsCommunicator = "Electronics", ElectronicsTransmitter = "Electronics",
    ElectronicsLight = "Electronics",
    -- Building (MarketSense-specific)
    Building = "Building",
    BuildingFixture = "Building", BuildingFixtureAppliance = "Building",
    BuildingFixturePlumbing = "Building", BuildingFurniture = "Building",
    BuildingFurnitureBed = "Building", BuildingFurnitureChair = "Building",
    BuildingFurnitureStorage = "Building", BuildingGarden = "Building",
    BuildingMoveable = "Building", BuildingSurvival = "Building",
    BuildingSurvivalTrap = "Building", BuildingVehicle = "Building",
    -- Memento / Misc
    Memento = "Misc", MementoPlushie = "Misc",
    Junk = "Misc", Misc = "Misc",
}

-- ============================================================
-- Parent hierarchy: flat token → ordered list of parent tokens
-- Parents listed closest-to-leaf first; root category is appended by expandPrimary.
-- ============================================================
local TOKEN_PARENTS = {
    -- Ammo
    AmmoBox = { "Ammo" }, AmmoCarton = { "Ammo" }, AmmoMag = { "Ammo" },
    -- Weapon subtypes
    WeaponAxe = { "WeaponMelee" }, WeaponBlunt = { "WeaponMelee" },
    WeaponSmallBlunt = { "WeaponMelee" }, WeaponLongBlade = { "WeaponMelee" },
    WeaponSmallBlade = { "WeaponMelee" }, WeaponSpear = { "WeaponMelee" },
    WeaponCrafted = { "WeaponMelee" },
    Firearm = { "WeaponRanged" },
    FirearmHandgun = { "Firearm", "WeaponRanged" },
    FirearmRifle = { "Firearm", "WeaponRanged" },
    FirearmShotgun = { "Firearm", "WeaponRanged" },
    WeaponExplosive = { "Explosive" },
    -- Beverage
    BeverageWater = { "Beverage" }, BeverageMilk = { "Beverage" },
    BeverageCoffee = { "Beverage" }, BeverageTea = { "Beverage" },
    BeverageSoftDrink = { "Beverage" }, BeverageJuice = { "Beverage" },
    BeverageBeer = { "Beverage" }, BeverageWine = { "Beverage" },
    BeverageAlcohol = { "Beverage" }, BeverageCocktail = { "Beverage" },
    BeverageEnergyDrink = { "Beverage" }, BeverageBox = { "Beverage" },
    -- Clothing
    ClothingVest = { "ClothingOuterwear" },
    ClothingSocks = { "ClothingFootwear" },
    ClothingUnderwear = { "ClothingBottom" },
    AccessoryNeck = { "Accessory" }, AccessoryLegs = { "Accessory" },
    AccessoryTop = { "Accessory" }, AccessoryArms = { "Accessory" },
    AccessoryHands = { "Accessory" }, AccessoryHead = { "Accessory" },
    AccessoryFace = { "Accessory" }, AccessoryJewelry = { "Accessory" },
    ProtectiveGearLegs = { "ProtectiveGear" }, ProtectiveGearTop = { "ProtectiveGear" },
    ProtectiveGearArms = { "ProtectiveGear" }, ProtectiveGearHands = { "ProtectiveGear" },
    ProtectiveGearHead = { "ProtectiveGear" }, ProtectiveGearFace = { "ProtectiveGear" },
    -- Container
    ContainerWearable = { "Container" },
    ContainerWearableAmmo = { "ContainerWearable", "Container" },
    ContainerAmmo = { "Container" }, ContainerLiquid = { "Container" },
    ContainerBox = { "Container" }, KeyRing = { "Container" },
    MementoOrContainer = { "Container" },
    -- Food base
    FoodNonPerishable = { "Food" }, FoodPerishable = { "Food" },
    -- Food non-perishable
    FoodBaking = { "FoodNonPerishable" }, FoodCandy = { "FoodNonPerishable" },
    FoodCheese = { "FoodNonPerishable" }, FoodCoffee = { "FoodNonPerishable" },
    FoodEgg = { "FoodNonPerishable" }, FoodFruits = { "FoodNonPerishable" },
    FoodHerb = { "FoodNonPerishable" }, FoodLivestock = { "FoodNonPerishable" },
    FoodMeat = { "FoodNonPerishable" }, FoodMushroom = { "FoodNonPerishable" },
    FoodNoExplicit = { "FoodNonPerishable" }, FoodNut = { "FoodNonPerishable" },
    FoodPetFood = { "FoodNonPerishable" }, FoodPreserved = { "FoodNonPerishable" },
    FoodSnack = { "FoodNonPerishable" }, FoodSpice = { "FoodNonPerishable" },
    FoodStaple = { "FoodNonPerishable" }, FoodStock = { "FoodNonPerishable" },
    FoodTea = { "FoodNonPerishable" }, FoodVegetables = { "FoodNonPerishable" },
    FoodNonPerishableCanned = { "FoodNonPerishable" },
    FoodNonPerishableSnack = { "FoodNonPerishable", "FoodSnack" },
    -- Food perishable
    FoodDish = { "FoodPerishable" }, FoodPortion = { "FoodPerishable" },
    FoodSeafood = { "FoodPerishable" },
    FoodPerishableBaking = { "FoodPerishable", "FoodBaking" },
    FoodPerishableCandy = { "FoodPerishable", "FoodCandy" },
    FoodPerishableCheese = { "FoodPerishable", "FoodCheese" },
    FoodPerishableDairy = { "FoodPerishable" },
    FoodPerishableBread = { "FoodPerishable" },
    FoodPerishableDish = { "FoodPerishable", "FoodDish" },
    FoodPerishableFruits = { "FoodPerishable", "FoodFruits" },
    FoodPerishableMeat = { "FoodPerishable", "FoodMeat" },
    FoodPerishableSeafood = { "FoodPerishable", "FoodSeafood" },
    FoodPerishableSnack = { "FoodPerishable", "FoodSnack" },
    FoodPerishableMeal = { "FoodPerishable" },
    -- Cooking
    CookingCup = { "Cooking" }, CookingPan = { "Cooking" },
    CookingCutlery = { "Cooking" }, CookingUtensil = { "Cooking" },
    CookingOrTool = { "Cooking" },
    -- Tool
    ToolCraft = { "Tool" }, ToolOrJunk = { "Tool" },
    ToolBlacksmith = { "ToolCraft" }, ToolButchering = { "ToolCraft" },
    ToolCarpentry = { "ToolCraft" }, ToolFlintKnapping = { "ToolCraft" },
    ToolGardening = { "Tool" }, ToolMaintenance = { "Tool" },
    ToolMasonry = { "ToolCraft" }, ToolMechanics = { "Tool" },
    ToolPottery = { "ToolCraft" }, ToolTailoring = { "ToolCraft" },
    ToolWelding = { "ToolCraft" }, ToolFarming = { "Tool" },
    -- Material
    MaterialMetalworking = { "Material" }, MaterialTailoring = { "Material" },
    MaterialPottery = { "Material" }, MaterialCarpentry = { "Material" },
    MaterialMaintenance = { "Material" }, MaterialButchering = { "Material" },
    MaterialFireSource = { "Material" }, MaterialOrJunk = { "Material" },
    MaterialBundled = { "Material" }, MaterialHardware = { "Material" },
    MaterialWood = { "Material" }, MaterialChemical = { "Material" },
    ResourceMetal = { "Material" }, ResourceFabric = { "Material" },
    ResourceMaterial = { "Material" }, ResourceHardware = { "Material" },
    -- Medical
    FirstAid = { "Medical" }, Bandage = { "FirstAid", "Medical" },
    -- Literature
    LiteratureFancyBook = { "LiteratureHardcover" },
    LiteratureHardcover = { "Literature" }, LiteratureSoftcover = { "Literature" },
    LiteratureMagazine = { "Literature" }, LiteratureNewspaper = { "Literature" },
    LiteratureOrJunk = { "Literature" }, LiteratureConsumable = { "Literature" },
    LiteraturePhoto = { "Literature" }, LiteraturePictureBook = { "Literature" },
    LiteratureRecipe = { "Literature" }, SkillBook = { "Literature" },
    LiteratureComic = { "Literature" }, LiteratureAdult = { "Literature" },
    LiteratureBrochure = { "Literature" }, LiteratureFlier = { "Literature" },
    LiteratureRpgManual = { "Literature" },
    -- Gardening
    GardeningSeed = { "Gardening" },
    GardeningSeedPacket = { "GardeningSeed", "Gardening" },
    GardeningCompostable = { "Gardening" },
    -- Electronics
    ElectronicsBattery = { "Electronics" }, ElectronicsGenerator = { "Electronics" },
    ElectronicsRadio = { "Electronics" }, ElectronicsTelevision = { "Electronics" },
    ElectronicsCommunicator = { "Electronics" }, ElectronicsTransmitter = { "Electronics" },
    ElectronicsLight = { "Electronics" },
    -- Building
    BuildingFixture = { "Building" },
    BuildingFixtureAppliance = { "BuildingFixture" },
    BuildingFixturePlumbing = { "BuildingFixture" },
    BuildingFurniture = { "Building" },
    BuildingFurnitureBed = { "BuildingFurniture" },
    BuildingFurnitureChair = { "BuildingFurniture" },
    BuildingFurnitureStorage = { "BuildingFurniture" },
    BuildingGarden = { "Building" }, BuildingMoveable = { "Building" },
    BuildingSurvival = { "Building" },
    BuildingSurvivalTrap = { "BuildingSurvival" },
    BuildingVehicle = { "Building" },
    -- Memento
    MementoPlushie = { "Memento" },
}

-- ============================================================
-- Public API
-- ============================================================

function TagMapper.categoryFromPrimary(token)
    local text = tostring(token or "")
    if text == "" then return "Misc" end
    return TOKEN_TO_ROOT[text] or "Misc"
end

function TagMapper.getParents(token)
    local text = tostring(token or "")
    if text == "" then return {} end
    local parents = TOKEN_PARENTS[text] or {}
    local root = TOKEN_TO_ROOT[text]
    if root and root ~= text then
        local rootAlreadyIn = false
        for _, p in ipairs(parents) do
            if p == root then rootAlreadyIn = true; break end
        end
        if not rootAlreadyIn then
            local result = {}
            for _, p in ipairs(parents) do result[#result + 1] = p end
            result[#result + 1] = root
            return result
        end
    end
    return parents
end

function TagMapper.expandPrimary(token)
    local text = tostring(token or "")
    if text == "" then return {} end
    local result = { text }
    local seen = { [text] = true }
    for _, parent in ipairs(TagMapper.getParents(text)) do
        if not seen[parent] then
            result[#result + 1] = parent
            seen[parent] = true
        end
    end
    return result
end

function TagMapper.makeResult(displayCat, confidence, details)
    if not displayCat or displayCat == "" then return nil end
    local root = TOKEN_TO_ROOT[displayCat] or "Misc"
    return {
        matched    = true,
        confidence = confidence or 0.85,
        displayCat = displayCat,
        primary    = displayCat,
        category   = root,
        tags       = { displayCat },
        details    = details or {},
    }
end

function TagMapper.isKnown(token)
    return TOKEN_TO_ROOT[tostring(token or "")] ~= nil
end

function TagMapper.toTag(token)
    return token
end

function TagMapper.getDefinition(token)
    local text = tostring(token or "")
    local root = TOKEN_TO_ROOT[text] or "Misc"

    -- Determine subcategory: strip root prefix from the first mid-level parent
    local subcategory = "General"
    local directParents = TOKEN_PARENTS[text]
    if directParents and directParents[1] then
        local firstParent = directParents[1]
        if firstParent ~= root and TOKEN_TO_ROOT[firstParent] == root then
            -- Only strip root prefix when the parent name actually starts with root
            if string.sub(firstParent, 1, #root) == root then
                local stripped = string.sub(firstParent, #root + 1)
                subcategory = (stripped ~= "" and stripped) or "General"
            end
        end
    end

    -- Determine leaf: strip "root+subcategory" prefix from token
    local leaf = text
    local fullPrefix = root .. (subcategory ~= "General" and subcategory or "")
    if subcategory ~= "General" and #fullPrefix < #text and string.sub(text, 1, #fullPrefix) == fullPrefix then
        local stripped = string.sub(text, #fullPrefix + 1)
        leaf = (stripped ~= "" and stripped) or text
    elseif #root < #text and string.sub(text, 1, #root) == root then
        local stripped = string.sub(text, #root + 1)
        leaf = (stripped ~= "" and stripped) or text
    end

    local primaryPrefix = root .. "." .. subcategory .. "." .. leaf
    local path = root .. "/" .. subcategory .. "/" .. leaf .. ".txt"

    return {
        root          = root,
        token         = text,
        subcategory   = subcategory,
        leaf          = leaf,
        primaryPrefix = primaryPrefix,
        path          = path,
        parents       = TagMapper.getParents(text),
    }
end

return TagMapper
