require "MarketSense/MS_RuntimeCache"
require "MarketSense/MS_WorldObjectEvidence"
require "MarketSense/MS_ItemCapabilities"

MarketSense = MarketSense or {}
MarketSense.PropertyReader = MarketSense.PropertyReader or {}

local PropertyReader = MarketSense.PropertyReader
local Core           = MarketSense.Core
local Cache          = MarketSense.RuntimeCache

local function positiveMagnitude(value)
    return math.abs(tonumber(value) or 0)
end

local function normalizeToken(value)
    local text = Core.lower(value)
    text = string.gsub(text, "[^%w]", "")
    return text
end

local function readNumber(obj, methodNames)
    if obj == nil or methodNames == nil then
        return nil
    end

    local methods = type(methodNames) == "table" and methodNames or { methodNames }
    for _, methodName in ipairs(methods) do
        local value = Core.safeCall(obj, methodName, nil)
        value = tonumber(value)
        if value ~= nil then
            return value
        end
    end
    return nil
end

local function preferNumber(primaryObj, fallbackObj, methodNames, defaultValue)
    local value = readNumber(primaryObj, methodNames)
    if value ~= nil then
        return value
    end

    value = readNumber(fallbackObj, methodNames)
    if value ~= nil then
        return value
    end

    return tonumber(defaultValue) or 0
end

local function preferString(primaryObj, fallbackObj, methodNames, defaultValue)
    local value = Core.safeString(primaryObj, methodNames, "")
    if value ~= "" then
        return value
    end
    return Core.safeString(fallbackObj, methodNames, defaultValue or "")
end

local function isSentinelSpoilage(value)
    return (tonumber(value) or 0) >= 365000
end

local function readFluidCategories(fluid)
    local categories = {}
    if fluid == nil or FluidCategory == nil then
        return categories
    end

    -- Fluid:getCategories() returns a Guava ImmutableSet. Kahlua cannot
    -- safely enumerate that implementation, while the public PZ API gives
    -- us a stable category list and the supported isCategory predicate.
    local categoryList = FluidCategory.getList()
    for index = 0, categoryList:size() - 1 do
        local category = categoryList:get(index)
        if fluid:isCategory(category) then
            categories[#categories + 1] = tostring(category)
        end
    end
    return categories
end

function PropertyReader.buildContext(scriptItemOrFullType, inventoryItem)
    if type(scriptItemOrFullType) == "table" and scriptItemOrFullType.fullType and scriptItemOrFullType.item ~= nil then
        return scriptItemOrFullType
    end

    local scriptItem = nil
    local fullType = nil
    local instance = inventoryItem
    local isTemporary = false

    if type(scriptItemOrFullType) == "string" then
        fullType = scriptItemOrFullType
        -- A cached context is definition-level data. An explicit inventory
        -- instance carries live state (condition, weight, etc.) and must
        -- always be read afresh.
        if inventoryItem == nil then
            local cached = Cache.getContext(fullType)
            if cached then return Core.deepCopy(cached) end
        end
        scriptItem = Core.findScriptItem(fullType)
    else
        scriptItem = scriptItemOrFullType
        fullType = Core.safeString(scriptItem, { "getFullName", "getName" }, "")
    end

    local moduleName, typeName = Core.splitFullType(fullType)
    if scriptItem then
        local readModuleName = Core.safeString(scriptItem, "getModuleName", moduleName)
        if readModuleName ~= "" then moduleName = readModuleName end
        local readTypeName = Core.safeString(scriptItem, { "getName", "getTypeString", "getDisplayName" }, typeName)
        if readTypeName ~= "" then typeName = readTypeName end
        if moduleName ~= "" and moduleName ~= "Unknown" and typeName ~= "" then
            fullType = moduleName .. "." .. typeName
        end
    end

    local displayCategory = Core.safeString(scriptItem, { "getDisplayCategory", "getCategories" }, "")
    local itemType        = Core.safeString(scriptItem, { "getItemType", "getTypeString", "getType" }, "")
    local displayName     = Core.safeString(scriptItem, "getDisplayName", typeName)
    local isHidden        = Core.safeBoolean(scriptItem, "isHidden", false)
    local isObsolete      = Core.safeBoolean(scriptItem, "getObsolete", false)
    local canSpawnAsLoot  = Core.safeBoolean(scriptItem, "canSpawnAsLoot", false)
    local canBeForaged    = Core.safeBoolean(scriptItem, "canBeForaged", false)
    local isCraftRecipeProduct = Core.safeBoolean(scriptItem, "isCraftRecipeProduct", false)
    local ammoType        = Core.safeString(scriptItem, { "getAmmoType", "getMagazineType" }, "")
    local magazineType    = Core.safeString(scriptItem, "getMagazineType", "")
    local partType        = Core.safeString(scriptItem, "getPartType", "")
    local mountOn         = Core.safeString(scriptItem, "getMountOn", "")
    local canStack        = Core.safeString(scriptItem, "getCanStack", "")
    local bodyLocation    = Core.safeString(scriptItem, "getBodyLocation", "")
    local lootType        = Core.safeString(scriptItem, "getLootType", "")
    local eatType         = Core.safeString(scriptItem, "getEatType", "")
    local foodType        = Core.safeString(scriptItem, "getFoodType", "")
    local icon            = Core.safeString(scriptItem, { "getIcon", "getIconName" }, "")
    local learnedRecipes  = Core.safeCall(scriptItem, "getLearnedRecipes", nil)
    local skillTrained    = Core.safeString(scriptItem, "getSkillTrained", "")
    local lvlSkillTrained = Core.safeNumber(scriptItem, { "getLevelSkillTrained", "getLvlSkillTrained" }, -1)
    local maxLevelTrained = Core.safeNumber(scriptItem, "getMaxLevelTrained", -1)
    local readType        = Core.safeString(scriptItem, "getReadType", "")
    local worldStaticModel   = Core.safeString(scriptItem, "getWorldStaticModel", "")
    local worldObjectSprite  = Core.safeString(scriptItem, "getWorldObjectSprite", "")
    local bloodClothingType  = Core.safeString(scriptItem, "getBloodClothingType", "")
    local openSound   = Core.safeString(scriptItem, "getOpenSound", "")
    local closeSound  = Core.safeString(scriptItem, "getCloseSound", "")
    local putInSound  = Core.safeString(scriptItem, "getPutInSound", "")
    local pourType    = Core.safeString(scriptItem, "getPourType", "")
    local doubleClickRecipe = Core.safeString(scriptItem, "getDoubleClickRecipe", "")
    local openingRecipe = Core.safeString(scriptItem, "getOpeningRecipe", "")
    local replaceOnDeplete  = Core.safeString(scriptItem, "getReplaceOnDeplete", "")
    local replaceOnUse      = Core.safeString(scriptItem, "getReplaceOnUse", "")
    local replaceOnCooked   = Core.safeString(scriptItem, "getReplaceOnCooked", "")
    local onCooked          = Core.safeString(scriptItem, "getOnCooked", "")
    local evolvedRecipe     = Core.safeString(scriptItem, "getEvolvedRecipe", "")
    local evolvedRecipeName = Core.safeString(scriptItem, "getEvolvedRecipeName", "")
    local canBeEquipped     = Core.safeString(scriptItem, "getCanBeEquipped", "")
    local acceptItemFunction = Core.safeString(scriptItem, "getAcceptItemFunction", "")
    local rangedToken       = Core.safeString(scriptItem, { "isRanged", "getRanged" }, "")
    local aimedFirearmToken = Core.safeString(scriptItem, { "isAimedFirearm", "getIsAimedFirearm" }, "")
    local hasRuntimeState = inventoryItem ~= nil

    if not instance then
        instance = Core.createTemporaryInstance(fullType)
        isTemporary = instance ~= nil
    end

    local isFoodInstance = false
    local isInventoryItemInstance = false
    local isLiteratureInstance = false
    if instance and type(instanceof) == "function" then
        isFoodInstance        = instanceof(instance, "Food") == true
        isInventoryItemInstance = instanceof(instance, "InventoryItem") == true
        isLiteratureInstance  = instanceof(instance, "Literature") == true
    end

    local description = preferString(instance, scriptItem, { "getDescription", "getTooltip" }, "")

    local instanceFoodType = Core.safeString(instance, "getFoodType", "")
    if instanceFoodType ~= "" then foodType = instanceFoodType end
    local instanceLootType = Core.safeString(instance, "getLootType", "")
    if instanceLootType ~= "" then lootType = instanceLootType end
    local instanceEatType = Core.safeString(instance, "getEatType", "")
    if instanceEatType ~= "" then eatType = instanceEatType end

    -- Preserve native signed changes for valuation. The magnitude fields
    -- remain below for classifier compatibility.
    local hungerChange = preferNumber(instance, scriptItem, { "getHungChange", "getHungerChange" }, 0)
    local thirstChange = preferNumber(instance, scriptItem, { "getThirstChangeUnmodified", "getThirstChange" }, 0)
    local unhappyChange = preferNumber(instance, scriptItem, { "getUnhappyChangeUnmodified", "getUnhappyChange", "getUnhappy" }, 0)
    local boredomChange = preferNumber(instance, scriptItem, { "getBoredomChangeUnmodified", "getBoredomChange", "getBoredom" }, 0)
    local stressChange = preferNumber(instance, scriptItem, { "getStressChangeUnmodified", "getStressChange", "getStress" }, 0)
    local hunger = positiveMagnitude(hungerChange)
    local thirst = positiveMagnitude(thirstChange)
    local calories = math.max(0, preferNumber(instance, scriptItem, "getCalories", 0))
    local carbohydrates = math.max(0, preferNumber(instance, scriptItem, "getCarbohydrates", 0))
    local lipids = math.max(0, preferNumber(instance, scriptItem, "getLipids", 0))
    local proteins = math.max(0, preferNumber(instance, scriptItem, "getProteins", 0))
    local daysFresh = math.max(0, preferNumber(instance, scriptItem, "getDaysFresh", 0))
    local daysRotten = math.max(0, preferNumber(instance, scriptItem, "getDaysTotallyRotten", 0))
    local unhappy = positiveMagnitude(unhappyChange)
    local boredom = positiveMagnitude(boredomChange)
    local stress = positiveMagnitude(stressChange)
    local customEatSound = preferString(instance, scriptItem, "getCustomEatSound", "")
    local conditionMax = math.max(0, preferNumber(instance, scriptItem, "getConditionMax", 0))
    local currentCondition = conditionMax
    local hasRuntimeCondition = false
    if hasRuntimeState then
        local readCondition = readNumber(instance, "getCondition")
        if readCondition ~= nil then
            currentCondition = math.max(0, readCondition)
            hasRuntimeCondition = true
        end
    end
    local conditionRatio = nil
    if conditionMax > 0 then
        conditionRatio = math.max(0, math.min(1, currentCondition / conditionMax))
    end
    local hitChance = math.max(0, preferNumber(instance, scriptItem, "getHitChance", 0))
    local aimingTime = math.max(0, preferNumber(instance, scriptItem, "getAimingTime", 0))
    local isTwoHandWeapon = Core.safeBoolean(
        instance, "isTwoHandWeapon", Core.safeBoolean(scriptItem, "isTwoHandWeapon", false)
    )
    local foodAge = nil
    local hasRuntimeFoodAge = false
    local hasRuntimeFoodState = false
    local isRotten = false
    local isFrozen = false
    local isCooked = false
    local isBurnt = false
    local heat = 0
    if hasRuntimeState then
        foodAge = readNumber(inventoryItem, "getAge")
        hasRuntimeFoodAge = foodAge ~= nil
        hasRuntimeFoodState = true
        isRotten = Core.safeBoolean(inventoryItem, { "isRotten", "IsRotten" }, false)
        isFrozen = Core.safeBoolean(inventoryItem, "isFrozen", false)
        isCooked = Core.safeBoolean(inventoryItem, "isCooked", false)
        isBurnt = Core.safeBoolean(inventoryItem, "isBurnt", false)
        heat = readNumber(inventoryItem, "getHeat") or 0
    end
    local foodDaysFresh = isSentinelSpoilage(daysFresh) and 0 or daysFresh
    local foodDaysRotten = isSentinelSpoilage(daysRotten) and 0 or daysRotten
    local hasFoodNutritionEvidence = hunger > 0 or thirst > 0 or calories > 0
        or carbohydrates > 0 or lipids > 0 or proteins > 0
    local hasFoodSpoilageEvidence = foodDaysFresh > 0 or foodDaysRotten > 0
    local hasFoodRecipeEvidence = evolvedRecipe ~= "" or evolvedRecipeName ~= ""
        or doubleClickRecipe ~= "" or openingRecipe ~= "" or customEatSound ~= ""
    local isDung = Core.safeBoolean(instance or scriptItem, { "isDung", "getIsDung" }, false)

    local fluidContainer = Core.safeCall(instance or scriptItem, "getFluidContainer", nil)
    local fluidType = ""
    local fluidCategory = ""
    local fluidTypeString = ""
    local fluidContainerName = ""
    local fluidCategories = {}
    local fluidAmount = 0
    local fluidCapacity = 0
    local fluidPrimaryAmount = 0
    local fluidFilledRatio = 0
    local fluidIsEmpty = true
    local fluidIsMixture = false
    local fluid = nil
    if fluidContainer then
        fluidContainerName = Core.safeString(fluidContainer, "getContainerName", "")
        fluidAmount = math.max(0, readNumber(fluidContainer, "getAmount") or 0)
        fluidCapacity = math.max(0, readNumber(fluidContainer, "getCapacity") or 0)
        fluidPrimaryAmount = math.max(0, readNumber(fluidContainer, "getPrimaryFluidAmount") or 0)
        fluidFilledRatio = math.max(0, math.min(1,
            readNumber(fluidContainer, "getFilledRatio") or 0))
        fluid = Core.safeCall(fluidContainer, "getPrimaryFluid", nil)
        fluidIsEmpty = Core.safeBoolean(fluidContainer, "isEmpty", fluid == nil)
        fluidIsMixture = Core.safeBoolean(fluidContainer, "isMixture", false)
        if fluid then
            fluidType       = tostring(Core.safeCall(fluid, "getFluidType", ""))
            fluidTypeString = Core.safeString(fluid, "getFluidTypeString", "")
            fluidCategories = readFluidCategories(fluid)
        end
    end
    local fluidCategoriesLower = {}
    for _, category in ipairs(fluidCategories) do
        fluidCategoriesLower[#fluidCategoriesLower + 1] = Core.lower(category)
        if fluidCategory == "" then fluidCategory = tostring(category) end
    end
    local isActualLiquid = fluid ~= nil
        and ((fluidType ~= "") or (fluidTypeString ~= ""))

    local modId   = Core.safeString(scriptItem, { "getModID", "getModId", "getSourceMod" }, "")
    local modName = Core.safeString(scriptItem, { "getModName", "getModID", "getModId", "getSourceMod" }, "")
    if modId == "" and moduleName ~= "" then modId = moduleName end
    if modName == "" then
        modName = moduleName == "Base" and "Project Zomboid (Vanilla)"
                  or moduleName ~= "" and moduleName or "Unknown"
    end

    local tags = Core.safeTags(scriptItem)
    local normalizedTags = {}
    local normalizedTagList = {}
    for _, tag in ipairs(tags) do
        local normalized = normalizeToken(tag)
        if normalized ~= "" and not normalizedTags[normalized] then
            normalizedTags[normalized] = true
            normalizedTagList[#normalizedTagList + 1] = normalized
        end
    end

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
        hasRuntimeState = hasRuntimeState,
        hasRuntimeCondition = hasRuntimeCondition,
        hitChance = hitChance,
        aimingTime = aimingTime,
        -- Kept for consumers of the old field. It now means hit chance only;
        -- aiming time is exposed separately instead of being conflated with it.
        reliability = hitChance,
        useDelta = math.max(0, preferNumber(instance, scriptItem, "getUseDelta", 0)),
        capacity = math.max(0, preferNumber(instance, scriptItem, "getCapacity", 0)),
        weightReduction = math.max(0, preferNumber(instance, scriptItem, "getWeightReduction", 0)),
        biteDefense = math.max(0, preferNumber(instance, scriptItem, "getBiteDefense", 0)),
        scratchDefense = math.max(0, preferNumber(instance, scriptItem, "getScratchDefense", 0)),
        bulletDefense = math.max(0, preferNumber(instance, scriptItem, "getBulletDefense", 0)),
        insulation = math.max(0, preferNumber(instance, scriptItem, "getInsulation", 0)),
        windResistance = math.max(0, preferNumber(instance, scriptItem, { "getWindresistance", "getWindResistance", "getWindresist" }, 0)),
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
        alcoholPower = Core.safeNumber(scriptItem, "getAlcoholPower", 0),
        fatigueChange = Core.safeNumber(scriptItem, "getFatigueChange", 0),
        reduceInfectionPower = Core.safeNumber(scriptItem, "getReduceInfectionPower", 0),
        bandagePower = Core.safeNumber(scriptItem, "getBandagePower", 0),
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

    -- WorldObjectSprite is the bridge between an item script and the actual
    -- placeable object.  Read its PZ PropertyContainer once and derive a
    -- reusable capability record.  These are interface facts only; they do
    -- not mutate the item's native PZ categories or pricing inputs.
    context.worldObjectEvidence = MarketSense.WorldObjectEvidence.read(worldObjectSprite)
    context.capabilities = MarketSense.ItemCapabilities.analyze(context)
    context.capabilitySet = context.capabilities.capabilitySet
    context.capabilityRequirements = context.capabilities.requirements
    context.capabilityRequirementSet = context.capabilities.requirementSet
    context.capabilityEvidence = context.capabilities.evidence

    if isTemporary then Core.releaseTemporaryInstance(instance) end
    Cache.setContext(context.fullType, context)
    return Core.deepCopy(context)
end

return PropertyReader
