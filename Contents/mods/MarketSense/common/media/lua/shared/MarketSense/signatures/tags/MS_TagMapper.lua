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
    Weapon = "Weapon",
    Ammo = "Weapon", AmmoBox = "Weapon", AmmoCarton = "Weapon", AmmoMag = "Weapon",
    WeaponAxe = "Weapon", WeaponBlunt = "Weapon", WeaponSmallBlunt = "Weapon",
    WeaponLongBlade = "Weapon", WeaponSmallBlade = "Weapon",
    WeaponSpear = "Weapon", WeaponCrafted = "Weapon", WeaponImprovised = "Weapon",
    WeaponUnarmed = "Weapon", BrokenWeapon = "Weapon",
    WeaponMelee = "Weapon", WeaponRanged = "Weapon",
    Firearm = "Weapon", FirearmHandgun = "Weapon", FirearmRifle = "Weapon", FirearmShotgun = "Weapon",
    Explosive = "Weapon", WeaponExplosive = "Weapon", WeaponPart = "Weapon",
    -- Beverage (filed under Food for registry output)
    Beverage = "Food",
    BeverageWater = "Food", BeverageMilk = "Food", BeverageDairy = "Food", BeverageCoffee = "Food",
    BeverageTea = "Food", BeverageSoftDrink = "Food", BeverageJuice = "Food",
    BeverageBeer = "Food", BeverageWine = "Food", BeverageAlcohol = "Food", BeverageSoda = "Food",
    BeverageCocktail = "Food", BeverageEnergyDrink = "Food", BeverageBox = "Food",
    -- Liquid contents (the vessel remains Container/ContainerLiquid only
    -- when no primary fluid is present at runtime)
    Liquid = "Liquid", LiquidBeverage = "Liquid", LiquidWater = "Liquid",
    LiquidTaintedWater = "Liquid", LiquidCarbonatedWater = "Liquid",
    LiquidSoda = "Liquid", LiquidJuice = "Liquid", LiquidSyrup = "Liquid", LiquidMilk = "Liquid",
    LiquidCoffee = "Liquid", LiquidTea = "Liquid", LiquidBeer = "Liquid",
    LiquidWine = "Liquid", LiquidAlcohol = "Liquid", LiquidBlood = "Liquid",
    LiquidAnimalBlood = "Liquid", LiquidAnimalGrease = "Liquid",
    LiquidFuel = "Liquid", LiquidDye = "Liquid", LiquidHairDye = "Liquid",
    LiquidChemical = "Liquid", LiquidMedical = "Liquid", LiquidIndustrial = "Liquid",
    LiquidUnknown = "Liquid",
    -- Clothing
    Clothing = "Clothing",
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
    ProtectiveGearNeck = "Clothing", ProtectiveGearUnderwear = "Clothing",
    ProtectiveGearBottom = "Clothing", ProtectiveGearOuterwear = "Clothing",
    -- Container
    Container = "Container", ContainerBag = "Container", ContainerBagBackpack = "Container",
    ContainerBagBandolier = "Container", ContainerBagDuffel = "Container",
    ContainerBagFanny = "Container", ContainerBagSatchel = "Container",
    ContainerWearable = "Container", ContainerWearableAmmo = "Container",
    ContainerAmmo = "Container", ContainerLiquid = "Container", ContainerBox = "Container",
    KeyRing = "Container", MementoOrContainer = "Container",
    -- Food root tokens
    Food = "Food", FoodNonPerishable = "Food", FoodPerishable = "Food",
    -- Food non-perishable
    FoodBaking = "Food", FoodCandy = "Food", FoodCheese = "Food", FoodCoffee = "Food",
    FoodEgg = "Food", FoodFruits = "Food", FoodHerb = "Food", FoodHotPepper = "Food",
    FoodInsect = "Food", FoodLivestock = "Food",
    FoodMeat = "Food", FoodMushroom = "Food", FoodNoExplicit = "Food", FoodNut = "Food",
    FoodPetFood = "Food", FoodPreserved = "Food", FoodSeed = "Food",
    FoodSnack = "Food", FoodSpice = "Food", FoodStaple = "Food",
    FoodStock = "Food", FoodSugar = "Food", FoodTea = "Food", FoodVegetables = "Food",
    FoodNonPerishableBaking = "Food", FoodNonPerishableBread = "Food", FoodNonPerishableCandy = "Food",
    FoodNonPerishableCheese = "Food", FoodNonPerishableDairy = "Food",
    FoodNonPerishableFruits = "Food", FoodNonPerishableMeat = "Food",
    FoodNonPerishableDish = "Food", FoodNonPerishablePortion = "Food",
    FoodNonPerishableSeafood = "Food", FoodNonPerishableVegetables = "Food",
    FoodNonPerishableBoxed = "Food", FoodNonPerishableCanned = "Food",
    FoodNonPerishableSnack = "Food",
    -- Food perishable
    FoodDish = "Food", FoodPortion = "Food", FoodSeafood = "Food",
    FoodPerishableBaking = "Food", FoodPerishableCandy = "Food", FoodPerishableCheese = "Food",
    FoodPerishableDairy = "Food", FoodPerishableBread = "Food", FoodPerishableDish = "Food",
    FoodPerishableFruits = "Food", FoodPerishableMeat = "Food",
    FoodPerishablePortion = "Food", FoodPerishableSeafood = "Food",
    FoodPerishableSnack = "Food", FoodPerishableVegetables = "Food", FoodPerishableMeal = "Food",
    FoodOrFirstAid = "Medical", FoodPreservedPickled = "Food",
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
    Resource = "Resource",
    Material = "Resource", ResourceFuel = "Resource", ResourceParts = "Resource",
    MaterialMetalworking = "Resource", MaterialTailoring = "Resource",
    MaterialPottery = "Resource", MaterialCarpentry = "Resource",
    MaterialMaintenance = "Resource", MaterialButchering = "Resource",
    MaterialFireSource = "Resource", MaterialOrJunk = "Resource", MaterialBundled = "Resource",
    MaterialHardware = "Resource", MaterialWood = "Resource", MaterialChemical = "Resource",
    MaterialConstruction = "Resource", MaterialGlass = "Resource", MaterialStone = "Resource",
    MaterialPaper = "Resource",
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
    LiteratureMap = "Literature",
    LiteratureComic = "Literature", LiteratureAdult = "Literature",
    LiteratureBrochure = "Literature", LiteratureFlier = "Literature",
    LiteratureRpgManual = "Literature",
    -- Gardening / Building seeds
    Gardening = "Building", GardeningSeed = "Building",
    GardeningSeedPacket = "Building", GardeningCompostable = "Building",
    GardeningCompost = "Building", GardeningFertilizer = "Building",
    GardeningPestControl = "Building",
    -- Electronics (MarketSense-specific)
    Electronics = "Electronics",
    ElectronicsBattery = "Electronics", ElectronicsGenerator = "Electronics",
    ElectronicsRadio = "Electronics", ElectronicsTelevision = "Electronics",
    ElectronicsCommunicator = "Electronics", ElectronicsTransmitter = "Electronics",
    ElectronicsLight = "Electronics", ElectronicsFlashlight = "Electronics",
    ElectronicsAppliance = "Electronics", ElectronicsLaundry = "Electronics",
    ElectronicsClock = "Electronics",
    -- Building (MarketSense-specific)
    Building = "Building",
    BuildingFixture = "Building", BuildingFixtureAppliance = "Building",
    BuildingFixtureLighting = "Building",
    BuildingFixturePlumbing = "Building", BuildingFurniture = "Building",
    BuildingFurnitureBed = "Building", BuildingFurnitureChair = "Building",
    BuildingFurnitureStorage = "Building", BuildingFurnitureCounter = "Building",
    BuildingFurnitureDecor = "Building", BuildingGarden = "Building",
    BuildingMoveable = "Building", BuildingSurvival = "Building",
    BuildingSurvivalSleepingBag = "Building", BuildingSurvivalTent = "Building",
    BuildingSurvivalTrap = "Building", BuildingVehicle = "Building",
    BuildingFurnitureTable = "Building", BuildingFurnitureLaundry = "Building",
    BuildingRecreation = "Building", BuildingRecreationFitness = "Building", BuildingRecreationDrum = "Building",
    BuildingMedical = "Building", BuildingMedicalGurney = "Building", BuildingMedicalBloodbag = "Building",
    BuildingCrafting = "Building", BuildingCraftingForge = "Building", BuildingCraftingMasonry = "Building",
    BuildingLogistics = "Building", BuildingLogisticsPallet = "Building",
    BuildingInfrastructure = "Building", BuildingInfrastructureTraffic = "Building",
    BuildingFuneral = "Building", BuildingFuneralCoffin = "Building",
    BuildingAgriculture = "Building", BuildingAgricultureHay = "Building",
    BuildingAgricultureLivestock = "Building", BuildingAgricultureScarecrow = "Building",
    BuildingGardenDecor = "Building", BuildingDisplay = "Building", BuildingDisplaySkeleton = "Building",
    BuildingWallDecor = "Building",
    BuildingWallDecorMap = "Building", BuildingWallDecorCertificate = "Building",
    BuildingWallDecorNoticeboard = "Building",
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
    WeaponCrafted = { "WeaponMelee" }, WeaponImprovised = { "WeaponMelee" },
    WeaponUnarmed = { "WeaponMelee" },
    Firearm = { "WeaponRanged" },
    FirearmHandgun = { "Firearm", "WeaponRanged" },
    FirearmRifle = { "Firearm", "WeaponRanged" },
    FirearmShotgun = { "Firearm", "WeaponRanged" },
    WeaponExplosive = { "Explosive" },
    -- Beverage
    BeverageWater = { "Beverage" }, BeverageMilk = { "Beverage" }, BeverageDairy = { "Beverage" },
    BeverageCoffee = { "Beverage" }, BeverageTea = { "Beverage" },
    BeverageSoftDrink = { "Beverage" }, BeverageJuice = { "Beverage" },
    BeverageSoda = { "BeverageSoftDrink", "Beverage" },
    BeverageBeer = { "Beverage" }, BeverageWine = { "Beverage" },
    BeverageAlcohol = { "Beverage" }, BeverageCocktail = { "Beverage" },
    BeverageEnergyDrink = { "Beverage" }, BeverageBox = { "Beverage" },
    -- Liquid hierarchy.  The special hierarchy renderer below presents
    -- these as Liquid > branch > leaf while these flat parents preserve
    -- useful inheritance for pricing and downstream consumers.
    LiquidBeverage = { "Liquid" }, LiquidWater = { "LiquidBeverage", "Liquid" },
    LiquidTaintedWater = { "LiquidWater", "LiquidBeverage", "Liquid" },
    LiquidCarbonatedWater = { "LiquidWater", "LiquidBeverage", "Liquid" },
    LiquidSoda = { "LiquidBeverage", "Liquid" }, LiquidJuice = { "LiquidBeverage", "Liquid" },
    LiquidSyrup = { "LiquidBeverage", "Liquid" },
    LiquidMilk = { "LiquidBeverage", "Liquid" }, LiquidCoffee = { "LiquidBeverage", "Liquid" },
    LiquidTea = { "LiquidBeverage", "Liquid" }, LiquidAlcohol = { "LiquidBeverage", "Liquid" },
    LiquidBeer = { "LiquidAlcohol", "LiquidBeverage", "Liquid" },
    LiquidWine = { "LiquidAlcohol", "LiquidBeverage", "Liquid" },
    LiquidBlood = { "LiquidIndustrial", "Liquid" },
    LiquidAnimalBlood = { "LiquidBlood", "LiquidIndustrial", "Liquid" },
    LiquidAnimalGrease = { "LiquidIndustrial", "Liquid" }, LiquidFuel = { "LiquidIndustrial", "Liquid" },
    LiquidDye = { "LiquidIndustrial", "Liquid" }, LiquidHairDye = { "LiquidDye", "LiquidIndustrial", "Liquid" },
    LiquidChemical = { "LiquidIndustrial", "Liquid" }, LiquidMedical = { "LiquidIndustrial", "Liquid" },
    LiquidIndustrial = { "Liquid" }, LiquidUnknown = { "Liquid" },
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
    ProtectiveGearNeck = { "ProtectiveGear" }, ProtectiveGearUnderwear = { "ProtectiveGear" },
    ProtectiveGearBottom = { "ProtectiveGear" }, ProtectiveGearOuterwear = { "ProtectiveGear" },
    -- Container
    ContainerBag = { "Container" },
    ContainerBagBackpack = { "ContainerBag", "Container" },
    ContainerBagBandolier = { "ContainerBag", "Container" },
    ContainerBagDuffel = { "ContainerBag", "Container" },
    ContainerBagFanny = { "ContainerBag", "Container" },
    ContainerBagSatchel = { "ContainerBag", "Container" },
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
    FoodHerb = { "FoodNonPerishable" }, FoodHotPepper = { "FoodSpice" },
    FoodInsect = { "FoodNonPerishable" }, FoodLivestock = { "FoodNonPerishable" },
    FoodMeat = { "FoodNonPerishable" }, FoodMushroom = { "FoodNonPerishable" },
    FoodNoExplicit = { "FoodNonPerishable" }, FoodNut = { "FoodNonPerishable" },
    FoodPetFood = { "FoodNonPerishable" }, FoodPreserved = { "FoodNonPerishable" },
    FoodSeed = { "FoodNonPerishable" }, FoodSnack = { "FoodNonPerishable" },
    FoodSpice = { "FoodNonPerishable" }, FoodStaple = { "FoodNonPerishable" },
    FoodStock = { "FoodNonPerishable" }, FoodSugar = { "FoodNonPerishable" },
    FoodTea = { "FoodNonPerishable" }, FoodVegetables = { "FoodNonPerishable" },
    FoodNonPerishableBaking = { "FoodNonPerishable", "FoodBaking" },
    FoodNonPerishableBread = { "FoodNonPerishable" },
    FoodNonPerishableCandy = { "FoodNonPerishable", "FoodCandy" },
    FoodNonPerishableCheese = { "FoodNonPerishable", "FoodCheese" },
    FoodNonPerishableDairy = { "FoodNonPerishable", "FoodCheese" },
    FoodNonPerishableFruits = { "FoodNonPerishable", "FoodFruits" },
    FoodNonPerishableMeat = { "FoodNonPerishable", "FoodMeat" },
    FoodNonPerishableDish = { "FoodNonPerishable", "FoodDish" },
    FoodNonPerishablePortion = { "FoodNonPerishable", "FoodPortion" },
    FoodNonPerishableSeafood = { "FoodNonPerishable", "FoodSeafood" },
    FoodNonPerishableVegetables = { "FoodNonPerishable", "FoodVegetables" },
    FoodNonPerishableBoxed = { "FoodNonPerishable" },
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
    FoodPerishablePortion = { "FoodPerishable", "FoodPortion" },
    FoodPerishableSeafood = { "FoodPerishable", "FoodSeafood" },
    FoodPerishableSnack = { "FoodPerishable", "FoodSnack" },
    FoodPerishableVegetables = { "FoodPerishable", "FoodVegetables" },
    FoodPerishableMeal = { "FoodPerishable" },
    FoodPreservedPickled = { "FoodPreserved", "FoodNonPerishable" },
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
    MaterialConstruction = { "Material" }, MaterialGlass = { "Material" },
    MaterialStone = { "Material" }, MaterialPaper = { "Material" },
    ResourceFuel = { "Resource" }, ResourceParts = { "Resource" },
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
    LiteratureRecipe = { "Literature" }, LiteratureMap = { "Literature" },
    SkillBook = { "Literature" },
    LiteratureComic = { "Literature" }, LiteratureAdult = { "Literature" },
    LiteratureBrochure = { "Literature" }, LiteratureFlier = { "Literature" },
    LiteratureRpgManual = { "Literature" },
    -- Gardening
    GardeningSeed = { "Gardening" },
    GardeningSeedPacket = { "Gardening" },
    GardeningCompostable = { "Gardening" },
    GardeningCompost = { "Gardening" },
    GardeningFertilizer = { "Gardening" },
    GardeningPestControl = { "Gardening" },
    -- Electronics
    ElectronicsBattery = { "Electronics" }, ElectronicsGenerator = { "Electronics" },
    ElectronicsRadio = { "Electronics" }, ElectronicsTelevision = { "Electronics" },
    ElectronicsCommunicator = { "Electronics" }, ElectronicsTransmitter = { "Electronics" },
    ElectronicsLight = { "Electronics" }, ElectronicsFlashlight = { "ElectronicsLight" },
    ElectronicsAppliance = { "Electronics" }, ElectronicsLaundry = { "ElectronicsAppliance", "Electronics" },
    ElectronicsClock = { "ElectronicsAppliance", "Electronics" },
    -- Building
    BuildingFixture = { "Building" },
    BuildingFixtureAppliance = { "BuildingFixture" },
    BuildingFixtureLighting = { "BuildingFixture" },
    BuildingFixturePlumbing = { "BuildingFixture" },
    BuildingFurniture = { "Building" },
    BuildingFurnitureBed = { "BuildingFurniture" },
    BuildingFurnitureChair = { "BuildingFurniture" },
    BuildingFurnitureStorage = { "BuildingFurniture" },
    BuildingFurnitureCounter = { "BuildingFurniture" },
    BuildingFurnitureDecor = { "BuildingFurniture" },
    BuildingGarden = { "Building" }, BuildingMoveable = { "Building" },
    BuildingSurvival = { "Building" },
    BuildingSurvivalSleepingBag = { "BuildingSurvival" },
    BuildingSurvivalTent = { "BuildingSurvival" },
    BuildingSurvivalTrap = { "BuildingSurvival" },
    BuildingVehicle = { "Building" },
    BuildingFurnitureTable = { "BuildingFurniture" },
    BuildingFurnitureLaundry = { "BuildingFurniture" },
    BuildingRecreationFitness = { "BuildingRecreation" },
    BuildingRecreationDrum = { "BuildingRecreation" },
    BuildingRecreation = { "Building" },
    BuildingMedicalGurney = { "BuildingMedical" },
    BuildingMedicalBloodbag = { "BuildingMedical" },
    BuildingMedical = { "Building" },
    BuildingCraftingForge = { "BuildingCrafting" },
    BuildingCraftingMasonry = { "BuildingCrafting" },
    BuildingCrafting = { "Building" },
    BuildingLogisticsPallet = { "BuildingLogistics" },
    BuildingLogistics = { "Building" },
    BuildingInfrastructureTraffic = { "BuildingInfrastructure" },
    BuildingInfrastructure = { "Building" },
    BuildingFuneralCoffin = { "BuildingFuneral" },
    BuildingFuneral = { "Building" },
    BuildingAgricultureHay = { "BuildingAgriculture" },
    BuildingAgricultureLivestock = { "BuildingAgriculture" },
    BuildingAgricultureScarecrow = { "BuildingAgriculture" },
    BuildingAgriculture = { "Building" },
    BuildingGardenDecor = { "BuildingGarden" },
    BuildingDisplaySkeleton = { "BuildingDisplay" },
    BuildingDisplay = { "Building" },
    BuildingWallDecorMap = { "BuildingWallDecor" },
    BuildingWallDecorCertificate = { "BuildingWallDecor" },
    BuildingWallDecorNoticeboard = { "BuildingWallDecor" },
    BuildingWallDecor = { "Building" },
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

    if text == root then
        return {
            root          = root,
            token         = text,
            subcategory   = "General",
            leaf          = "General",
            primaryPrefix = root .. ".General",
            path          = root .. "/General.txt",
            parents       = TagMapper.getParents(text),
        }
    end

    -- ContainerBag is a real branch token, not a leaf item subtype. Keep it
    -- at Container/Bag so its leaf variants render as Container > Bag > X.
    if text == "ContainerBag" then
        return {
            root          = "Container",
            token         = text,
            subcategory   = "Bag",
            leaf          = "Bag",
            primaryPrefix = "Container.Bag",
            path          = "Container/Bag.txt",
            parents       = TagMapper.getParents(text),
        }
    end

    if root == "Food" and string.sub(text, 1, 8) == "Beverage" then
        local leaf = string.sub(text, 9)
        if leaf == "" then leaf = "Beverage" end
        local primaryPrefix = "Food.Beverage"
        local path = "Food/Beverage.txt"
        if leaf ~= "Beverage" then
            primaryPrefix = primaryPrefix .. "." .. leaf
            path = "Food/Beverage/" .. leaf .. ".txt"
        end
        return {
            root          = root,
            token         = text,
            subcategory   = "Beverage",
            leaf          = leaf,
            primaryPrefix = primaryPrefix,
            path          = path,
            parents       = TagMapper.getParents(text),
        }
    end

    if root == "Liquid" then
        local hierarchy = {
            LiquidBeverage       = { "Beverage", "Beverage" },
            LiquidWater          = { "Water", "Water" },
            LiquidTaintedWater   = { "Water", "TaintedWater" },
            LiquidCarbonatedWater = { "Water", "CarbonatedWater" },
            LiquidSoda           = { "Soda", "Soda" },
            LiquidJuice          = { "Juice", "Juice" },
            LiquidSyrup          = { "Beverage", "Syrup" },
            LiquidMilk           = { "Dairy", "Milk" },
            LiquidCoffee         = { "Coffee", "Coffee" },
            LiquidTea            = { "Tea", "Tea" },
            LiquidAlcohol        = { "Alcohol", "Alcohol" },
            LiquidBeer           = { "Alcohol", "Beer" },
            LiquidWine           = { "Alcohol", "Wine" },
            LiquidBlood          = { "Blood", "Blood" },
            LiquidAnimalBlood    = { "Blood", "AnimalBlood" },
            LiquidAnimalGrease   = { "Animal", "Grease" },
            LiquidFuel           = { "Fuel", "Fuel" },
            LiquidDye            = { "Industrial", "Dye" },
            LiquidHairDye        = { "Industrial", "HairDye" },
            LiquidChemical       = { "Industrial", "Chemical" },
            LiquidMedical        = { "Medical", "Medical" },
            LiquidIndustrial     = { "Industrial", "Industrial" },
            LiquidUnknown        = { "Unknown", "Unknown" },
        }
        local selected = hierarchy[text] or { "Unknown", "Unknown" }
        return {
            root          = root,
            token         = text,
            subcategory   = selected[1],
            leaf          = selected[2],
            primaryPrefix = root .. "." .. selected[1] .. "." .. selected[2],
            path          = root .. "/" .. selected[1] .. "/" .. selected[2] .. ".txt",
            parents       = TagMapper.getParents(text),
        }
    end

    local function stripRootPrefix(value)
        local input = tostring(value or "")
        if #root < #input and string.sub(input, 1, #root) == root then
            return string.sub(input, #root + 1)
        end
        return input
    end

    -- Prefer the closest parent branch as subcategory.
    -- If unavailable, derive from the token itself so we do not create a generic bucket.
    local subcategory = "Root"
    local directParents = TOKEN_PARENTS[text]
    if directParents and directParents[1] then
        local firstParent = directParents[1]
        if firstParent ~= root and TOKEN_TO_ROOT[firstParent] == root then
            local strippedParent = stripRootPrefix(firstParent)
            subcategory = strippedParent ~= "" and strippedParent or "Root"
        end
    end
    if subcategory == "Root" then
        local strippedSelf = stripRootPrefix(text)
        subcategory = strippedSelf ~= "" and strippedSelf or root
    end

    -- Determine leaf: strip the flattened "root+subcategory" prefix when available.
    local leaf = text
    local fullPrefix = root .. (subcategory ~= "Root" and subcategory or "")
    if #fullPrefix < #text and string.sub(text, 1, #fullPrefix) == fullPrefix then
        local stripped = string.sub(text, #fullPrefix + 1)
        leaf = (stripped ~= "" and stripped) or text
    elseif subcategory ~= "Root" and #subcategory < #text and string.sub(text, 1, #subcategory) == subcategory then
        local stripped = string.sub(text, #subcategory + 1)
        leaf = (stripped ~= "" and stripped) or text
    elseif #root < #text and string.sub(text, 1, #root) == root then
        local stripped = string.sub(text, #root + 1)
        leaf = (stripped ~= "" and stripped) or text
    end
    if leaf == "" then
        leaf = subcategory
    end

    local primaryPrefix = root .. "." .. subcategory
    local path = root .. "/" .. subcategory .. ".txt"
    if leaf ~= subcategory then
        primaryPrefix = primaryPrefix .. "." .. leaf
        path = root .. "/" .. subcategory .. "/" .. leaf .. ".txt"
    end

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
