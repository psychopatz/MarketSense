require "MarketSense/MS_Core"
require "MarketSense/MS_PropertyReader_Signals"

MarketSense = MarketSense or {}

local Core = MarketSense.Core
local Signals = require "MarketSense/MS_PropertyReader_Signals"
local normalizeToken = Signals.normalizeToken
local preferNumber = Signals.preferNumber

local ContextModel = {}

function ContextModel.build(facts, scriptItem, fullType, moduleName, typeName, instance, isTemporary)
    local displayCategory = facts.displayCategory
    local itemType = facts.itemType
    local displayName = facts.displayName
    local isHidden = facts.isHidden
    local isObsolete = facts.isObsolete
    local canSpawnAsLoot = facts.canSpawnAsLoot
    local canBeForaged = facts.canBeForaged
    local isCraftRecipeProduct = facts.isCraftRecipeProduct
    local ammoType = facts.ammoType
    local magazineType = facts.magazineType
    local partType = facts.partType
    local mountOn = facts.mountOn
    local canStack = facts.canStack
    local bodyLocation = facts.bodyLocation
    local lootType = facts.lootType
    local eatType = facts.eatType
    local foodType = facts.foodType
    local icon = facts.icon
    local learnedRecipes = facts.learnedRecipes
    local skillTrained = facts.skillTrained
    local lvlSkillTrained = facts.lvlSkillTrained
    local maxLevelTrained = facts.maxLevelTrained
    local readType = facts.readType
    local worldStaticModel = facts.worldStaticModel
    local worldObjectSprite = facts.worldObjectSprite
    local bloodClothingType = facts.bloodClothingType
    local openSound = facts.openSound
    local closeSound = facts.closeSound
    local putInSound = facts.putInSound
    local pourType = facts.pourType
    local doubleClickRecipe = facts.doubleClickRecipe
    local openingRecipe = facts.openingRecipe
    local replaceOnDeplete = facts.replaceOnDeplete
    local replaceOnCooked = facts.replaceOnCooked
    local onCooked = facts.onCooked
    local evolvedRecipe = facts.evolvedRecipe
    local evolvedRecipeName = facts.evolvedRecipeName
    local canBeEquipped = facts.canBeEquipped
    local acceptItemFunction = facts.acceptItemFunction
    local rangedToken = facts.rangedToken
    local aimedFirearmToken = facts.aimedFirearmToken
    local hasRuntimeState = facts.hasRuntimeState
    local isFoodInstance = facts.isFoodInstance
    local isInventoryItemInstance = facts.isInventoryItemInstance
    local isLiteratureInstance = facts.isLiteratureInstance
    local isDrainableInstance = facts.isDrainableInstance
    local description = facts.description
    local hungerChange = facts.hungerChange
    local thirstChange = facts.thirstChange
    local unhappyChange = facts.unhappyChange
    local boredomChange = facts.boredomChange
    local stressChange = facts.stressChange
    local hunger = facts.hunger
    local thirst = facts.thirst
    local calories = facts.calories
    local carbohydrates = facts.carbohydrates
    local lipids = facts.lipids
    local proteins = facts.proteins
    local daysFresh = facts.daysFresh
    local daysRotten = facts.daysRotten
    local unhappy = facts.unhappy
    local boredom = facts.boredom
    local stress = facts.stress
    local customEatSound = facts.customEatSound
    local bandagePower = facts.bandagePower
    local reduceInfectionPower = facts.reduceInfectionPower
    local alcoholPower = facts.alcoholPower
    local foodSicknessChange = facts.foodSicknessChange
    local painReduction = facts.painReduction
    local fluReduction = facts.fluReduction
    local isMedicalLoot = facts.isMedicalLoot
    local canBandage = facts.canBandage
    local useSelf = facts.useSelf
    local replaceOnUse = facts.replaceOnUse
    local replaceOnUseOn = facts.replaceOnUseOn
    local isDisappearOnUse = facts.isDisappearOnUse
    local conditionMax = facts.conditionMax
    local currentCondition = facts.currentCondition
    local hasRuntimeCondition = facts.hasRuntimeCondition
    local conditionRatio = facts.conditionRatio
    local conditionLowerChance = facts.conditionLowerChance
    local useDelta = facts.useDelta
    local maxUses = facts.maxUses
    local currentUsesFloat = facts.currentUsesFloat
    local weightEmpty = facts.weightEmpty
    local stackCount = facts.stackCount
    local hitChance = facts.hitChance
    local aimingTime = facts.aimingTime
    local isTwoHandWeapon = facts.isTwoHandWeapon
    local lightStrength = facts.lightStrength
    local lightDistance = facts.lightDistance
    local lightCanEmit = facts.lightCanEmit
    local lightUseBattery = facts.lightUseBattery
    local lightHasBattery = facts.lightHasBattery
    local insulation = facts.insulation
    local insulationAvailable = facts.insulationAvailable == true or insulation ~= nil
    local windResistance = facts.windResistance
    local windResistanceAvailable = facts.windResistanceAvailable == true or windResistance ~= nil
    local waterResistance = facts.waterResistance
    local runSpeedModifier = facts.runSpeedModifier
    local combatSpeedModifier = facts.combatSpeedModifier
    local neckProtectionModifier = facts.neckProtectionModifier
    local deviceData = facts.deviceData
    local foodAge = facts.foodAge
    local hasRuntimeFoodAge = facts.hasRuntimeFoodAge
    local hasRuntimeFoodState = facts.hasRuntimeFoodState
    local isRotten = facts.isRotten
    local isFrozen = facts.isFrozen
    local isCooked = facts.isCooked
    local isBurnt = facts.isBurnt
    local heat = facts.heat
    local foodDaysFresh = facts.foodDaysFresh
    local foodDaysRotten = facts.foodDaysRotten
    local hasFoodNutritionEvidence = facts.hasFoodNutritionEvidence
    local hasFoodSpoilageEvidence = facts.hasFoodSpoilageEvidence
    local hasFoodRecipeEvidence = facts.hasFoodRecipeEvidence
    local isDung = facts.isDung
    local fluidContainer = facts.fluidContainer
    local fluidType = facts.fluidType
    local fluidCategory = facts.fluidCategory
    local fluidTypeString = facts.fluidTypeString
    local fluidContainerName = facts.fluidContainerName
    local fluidCategories = facts.fluidCategories
    local fluidCategoriesLower = facts.fluidCategoriesLower
    local fluidAmount = facts.fluidAmount
    local fluidCapacity = facts.fluidCapacity
    local fluidPrimaryAmount = facts.fluidPrimaryAmount
    local fluidFilledRatio = facts.fluidFilledRatio
    local fluidIsEmpty = facts.fluidIsEmpty
    local fluidIsMixture = facts.fluidIsMixture
    local fluid = facts.fluid
    local isActualLiquid = facts.isActualLiquid
    local modId = facts.modId
    local modName = facts.modName
    local tags = facts.tags
    local normalizedTags = facts.normalizedTags
    local normalizedTagList = facts.normalizedTagList

    local context = {
        item = scriptItem,
        fullType = fullType ~= "" and fullType or (moduleName .. "." .. typeName),
        moduleName = moduleName, typeName = typeName,
        sourceModId = modId, sourceModName = modName,
        idLower = Core.lower(typeName),
        fullLower = Core.lower(fullType ~= "" and fullType or (moduleName .. "." .. typeName)),
        displayName = displayName, displayNameLower = Core.lower(displayName),
        isHidden = isHidden,
        isObsolete = isObsolete,
        canSpawnAsLoot = canSpawnAsLoot,
        canBeForaged = canBeForaged,
        isCraftRecipeProduct = isCraftRecipeProduct,
        description = description, descriptionLower = Core.lower(description),
        displayCategory = displayCategory,
        displayCategoryLower = Core.lower(displayCategory),
        displayCategoryToken = normalizeToken(displayCategory),
        itemType = itemType, itemTypeLower = Core.lower(itemType),
        itemTypeToken = normalizeToken((string.match(Core.lower(itemType), "([^:]+)$") or itemType)),
        lootType = lootType, lootTypeLower = Core.lower(lootType),
        lootTypeToken = normalizeToken(lootType),
        weight = math.max(0, preferNumber(instance, scriptItem, { "getActualWeight", "getWeight" }, 0)),
        hunger = hunger,
        thirst = thirst,
        hungerChange = hungerChange,
        thirstChange = thirstChange,
        calories = calories,
        carbohydrates = carbohydrates,
        lipids = lipids,
        proteins = proteins,
        daysFresh = daysFresh,
        daysRotten = daysRotten,
        foodDaysFresh = foodDaysFresh,
        foodDaysRotten = foodDaysRotten,
        unhappy = unhappy,
        boredom = boredom,
        stress = stress,
        unhappyChange = unhappyChange,
        boredomChange = boredomChange,
        stressChange = stressChange,
        bandagePower = bandagePower,
        reduceInfectionPower = reduceInfectionPower,
        alcoholPower = alcoholPower,
        foodSicknessChange = foodSicknessChange,
        painReduction = painReduction,
        fluReduction = fluReduction,
        isMedicalLoot = isMedicalLoot,
        canBandage = canBandage,
        useSelf = useSelf,
        replaceOnUse = replaceOnUse ~= "" and replaceOnUse or nil,
        replaceOnUseOn = replaceOnUseOn ~= "" and replaceOnUseOn or nil,
        isDisappearOnUse = isDisappearOnUse,
        foodAge = foodAge,
        hasRuntimeFoodAge = hasRuntimeFoodAge,
        hasRuntimeFoodState = hasRuntimeFoodState,
        isRotten = isRotten,
        isFrozen = isFrozen,
        isCooked = isCooked,
        isBurnt = isBurnt,
        heat = heat,
        minDamage = math.max(0, preferNumber(instance, scriptItem, "getMinDamage", 0)),
        maxDamage = math.max(0, preferNumber(instance, scriptItem, "getMaxDamage", 0)),
        maxRange = math.max(0, preferNumber(instance, scriptItem, "getMaxRange", 0)),
        maxHit = math.max(1, preferNumber(instance, scriptItem, "getMaxHitCount", 1)),
        conditionMax = conditionMax,
        condition = currentCondition,
        conditionRatio = conditionRatio,
        conditionLowerChance = conditionLowerChance,
        hasRuntimeState = hasRuntimeState,
        hasRuntimeCondition = hasRuntimeCondition,
        hitChance = hitChance,
        aimingTime = aimingTime,
        -- Kept for consumers of the old field. It now means hit chance only;
        -- aiming time is exposed separately instead of being conflated with it.
        reliability = hitChance,
        useDelta = useDelta,
        maxUses = maxUses,
        currentUsesFloat = currentUsesFloat,
        remainingUsesRatio = currentUsesFloat,
        weightEmpty = weightEmpty,
        stackCount = stackCount,
        capacity = math.max(0, preferNumber(instance, scriptItem, "getCapacity", 0)),
        weightReduction = math.max(0, preferNumber(instance, scriptItem, "getWeightReduction", 0)),
        lightStrength = lightStrength,
        lightDistance = lightDistance,
        lightCanEmit = lightCanEmit,
        lightUseBattery = lightUseBattery,
        lightHasBattery = lightHasBattery,
        waterResistance = waterResistance,
        runSpeedModifier = runSpeedModifier,
        combatSpeedModifier = combatSpeedModifier,
        neckProtectionModifier = neckProtectionModifier,
        deviceData = deviceData,
        deviceDataAvailable = deviceData ~= nil,
        biteDefense = math.max(0, preferNumber(instance, scriptItem, "getBiteDefense", 0)),
        scratchDefense = math.max(0, preferNumber(instance, scriptItem, "getScratchDefense", 0)),
        bulletDefense = math.max(0, preferNumber(instance, scriptItem, "getBulletDefense", 0)),
        insulation = insulation ~= nil and math.max(0, insulation) or nil,
        insulationAvailable = insulationAvailable,
        windResistance = windResistance ~= nil and math.max(0, windResistance) or nil,
        windResistanceAvailable = windResistanceAvailable,
        bodyLocation = bodyLocation,
        bodyLocationLower = Core.lower(bodyLocation),
        bodyLocationToken = normalizeToken((string.match(Core.lower(bodyLocation), "([^:]+)$") or bodyLocation)),
        ammoType = ammoType, ammoTypeLower = Core.lower(ammoType),
        ammoTypeToken = normalizeToken((string.match(Core.lower(ammoType), "([^:]+)$") or ammoType)),
        magazineType = magazineType, magazineTypeLower = Core.lower(magazineType),
        magazineTypeToken = normalizeToken((string.match(Core.lower(magazineType), "([^:]+)$") or magazineType)),
        partType = partType, partTypeLower = Core.lower(partType), partTypeToken = normalizeToken(partType),
        mountOn = mountOn, mountOnLower = Core.lower(mountOn),
        canStack = canStack, canStackLower = Core.lower(canStack),
        rangedToken = rangedToken, rangedTokenLower = Core.lower(rangedToken),
        aimedFirearmToken = aimedFirearmToken, aimedFirearmTokenLower = Core.lower(aimedFirearmToken),
        canBeEquipped = canBeEquipped, canBeEquippedLower = Core.lower(canBeEquipped),
        acceptItemFunction = acceptItemFunction, acceptItemFunctionLower = Core.lower(acceptItemFunction),
        openSound = openSound, closeSound = closeSound, putInSound = putInSound,
        pourType = pourType, eatType = eatType, eatTypeLower = Core.lower(eatType),
        foodType = foodType, foodTypeLower = Core.lower(foodType), foodTypeToken = normalizeToken(foodType),
        doubleClickRecipe = doubleClickRecipe, doubleClickRecipeLower = Core.lower(doubleClickRecipe),
        openingRecipe = openingRecipe, openingRecipeLower = Core.lower(openingRecipe),
        replaceOnDeplete = replaceOnDeplete, replaceOnDepleteLower = Core.lower(replaceOnDeplete),
        replaceOnUse = replaceOnUse, replaceOnUseLower = Core.lower(replaceOnUse),
        replaceOnCooked = replaceOnCooked, replaceOnCookedLower = Core.lower(replaceOnCooked),
        onCooked = onCooked, onCookedLower = Core.lower(onCooked),
        evolvedRecipe = evolvedRecipe, evolvedRecipeLower = Core.lower(evolvedRecipe),
        evolvedRecipeName = evolvedRecipeName, evolvedRecipeNameLower = Core.lower(evolvedRecipeName),
        icon = icon, iconLower = Core.lower(icon),
        learnedRecipes = Core.listFromJavaCollection(learnedRecipes),
        skillTrained = skillTrained, skillTrainedLower = Core.lower(skillTrained),
        lvlSkillTrained = lvlSkillTrained,
        maxLevelTrained = maxLevelTrained,
        readType = readType, readTypeLower = Core.lower(readType), readTypeToken = normalizeToken(readType),
        worldStaticModel = worldStaticModel, worldStaticModelLower = Core.lower(worldStaticModel),
        worldObjectSprite = worldObjectSprite, worldObjectSpriteLower = Core.lower(worldObjectSprite),
        bloodClothingType = bloodClothingType, bloodClothingTypeLower = Core.lower(bloodClothingType),
        bloodClothingTypeToken = normalizeToken(bloodClothingType),
        fluidType = fluidType, fluidTypeLower = Core.lower(fluidType),
        fluidCategory = fluidCategory,
        fluidCategoryLower = Core.lower(fluidCategory),
        fluidTypeString = fluidTypeString, fluidTypeStringLower = Core.lower(fluidTypeString),
        fluidContainerName = fluidContainerName, fluidContainerNameLower = Core.lower(fluidContainerName),
        fluidCategories = fluidCategories,
        fluidCategoriesLower = fluidCategoriesLower,
        fluidAmount = fluidAmount,
        fluidCapacity = fluidCapacity,
        fluidPrimaryAmount = fluidPrimaryAmount,
        fluidFilledRatio = fluidFilledRatio,
        fluidIsEmpty = fluidIsEmpty,
        fluidIsMixture = fluidIsMixture,
        isActualLiquid = isActualLiquid,
        isFluidContainer = fluidContainer ~= nil,
        tags = tags, normalizedTagList = normalizedTagList, normalizedTags = normalizedTags,
        weaponCategories = Core.listFromJavaCollection(Core.safeCall(scriptItem, "getWeaponCategories", nil)),
        isTwoHandWeapon = isTwoHandWeapon,
        isSpice = Core.safeBoolean(scriptItem, "isSpice", false),
        isPoison = Core.safeBoolean(scriptItem, "isPoison", false),
        alcoholPower = alcoholPower,
        fatigueChange = Core.safeNumber(scriptItem, "getFatigueChange", 0),
        reduceInfectionPower = reduceInfectionPower,
        bandagePower = bandagePower,
        mechanicType = math.max(0, Core.safeNumber(instance or scriptItem, "getMechanicType", 0)),
        canAge = Core.safeBoolean(instance or scriptItem, "canAge", false),
        canBeWrite = Core.safeBoolean(instance or scriptItem, "canBeWrite", false),
        isCantEat = Core.safeBoolean(scriptItem, "isCantEat", false),
        customEatSound = customEatSound,
        customEatSoundLower = Core.lower(customEatSound),
        isMoveable = Core.startsWith(typeName, "Mov_"),
        hasWorldStaticModel = Core.safeString(scriptItem, "getWorldStaticModel", "") ~= "",
        isCookable = Core.safeBoolean(scriptItem, "isCookable", false),
        isDrainable = Core.safeBoolean(scriptItem, "isDrainable", false),
        isDrainableInstance = isDrainableInstance,
        canStoreWater = Core.safeBoolean(scriptItem, "CanStoreWater", false),
        isDung = isDung,
        hasOpenSound = openSound ~= "", hasCloseSound = closeSound ~= "",
        hasPutInSound = putInSound ~= "", hasPourType = pourType ~= "",
        hasEatType = eatType ~= "",
        isCannedFood = Core.safeBoolean(instance or scriptItem, { "isCannedFood", "getCannedFood" }, false),
        isPackaged = Core.safeBoolean(instance or scriptItem, { "isPackaged", "getPackaged" }, false),
        isFishingLure = Core.safeBoolean(instance or scriptItem, { "isFishingLure", "getFishingLure" }, false),
        isDangerousUncooked = Core.safeBoolean(instance or scriptItem, { "isDangerousUncooked", "getDangerousUncooked" }, false),
        isGoodHot = Core.safeBoolean(instance or scriptItem, { "isGoodHot", "getGoodHot" }, false),
        hasFluidContainer = Core.safeBoolean(scriptItem, { "isCanStoreWater", "CanStoreWater" }, false),
        instanceCreated = instance ~= nil,
        isFoodInstance = isFoodInstance,
        isInventoryItemInstance = isInventoryItemInstance,
        isLiteratureInstance = isLiteratureInstance,
        hasFoodNutritionEvidence = hasFoodNutritionEvidence,
        hasFoodSpoilageEvidence = hasFoodSpoilageEvidence,
        hasFoodRecipeEvidence = hasFoodRecipeEvidence,
        foodFacts = {
            isFoodInstance = isFoodInstance,
            displayCategory = displayCategory,
            itemType = itemType,
            lootType = lootType,
            foodType = foodType,
            hunger = hunger,
            thirst = thirst,
            hungerChange = hungerChange,
            thirstChange = thirstChange,
            calories = calories,
            carbohydrates = carbohydrates,
            lipids = lipids,
            proteins = proteins,
            unhappyChange = unhappyChange,
            boredomChange = boredomChange,
            stressChange = stressChange,
            daysFresh = foodDaysFresh,
            daysRotten = foodDaysRotten,
            foodAge = foodAge,
            hasRuntimeFoodAge = hasRuntimeFoodAge,
            isRotten = isRotten,
            isFrozen = isFrozen,
            isCooked = isCooked,
            isBurnt = isBurnt,
            heat = heat,
            isCantEat = Core.safeBoolean(scriptItem, "isCantEat", false),
            isCookable = Core.safeBoolean(scriptItem, "isCookable", false),
            isDung = isDung,
            normalizedTags = normalizedTagList,
        },
        foodFactTrace = {
            fullType = fullType ~= "" and fullType or (moduleName .. "." .. typeName),
            instanceCreated = instance ~= nil,
            isTemporary = isTemporary,
            isFoodInstance = isFoodInstance,
            foodType = foodType,
            lootType = lootType,
            eatType = eatType,
            doubleClickRecipe = doubleClickRecipe,
            openingRecipe = openingRecipe,
            replaceOnUse = replaceOnUse,
            onCooked = onCooked,
            isCannedFood = Core.safeBoolean(instance or scriptItem, { "isCannedFood", "getCannedFood" }, false),
            isPackaged = Core.safeBoolean(instance or scriptItem, { "isPackaged", "getPackaged" }, false),
            hasFoodNutritionEvidence = hasFoodNutritionEvidence,
            hasFoodSpoilageEvidence = hasFoodSpoilageEvidence,
            hasFoodRecipeEvidence = hasFoodRecipeEvidence,
            foodDaysFresh = foodDaysFresh,
            foodDaysRotten = foodDaysRotten,
            foodAge = foodAge,
            hasRuntimeFoodAge = hasRuntimeFoodAge,
            hasRuntimeFoodState = hasRuntimeFoodState,
            isRotten = isRotten,
            isFrozen = isFrozen,
            isCooked = isCooked,
            isBurnt = isBurnt,
            heat = heat,
            isDung = isDung,
        },
    }

    return context
end

MarketSense.PropertyReaderContextModel = ContextModel

return ContextModel
