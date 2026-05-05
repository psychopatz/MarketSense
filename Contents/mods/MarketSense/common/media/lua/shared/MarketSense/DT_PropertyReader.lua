require "MarketSense/DT_RuntimeCache"

DynamicTrading = DynamicTrading or {}
DynamicTrading.PropertyReader = DynamicTrading.PropertyReader or {}

local PropertyReader = DynamicTrading.PropertyReader
local Core = DynamicTrading.Core
local Cache = DynamicTrading.RuntimeCache

local function positiveMagnitude(value)
    return math.abs(tonumber(value) or 0)
end

local function normalizeToken(value)
    local text = Core.lower(value)
    text = string.gsub(text, "[^%w]", "")
    return text
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
        local cached = Cache.getContext(fullType)
        if cached then
            return Core.deepCopy(cached)
        end
        scriptItem = Core.findScriptItem(fullType)
    else
        scriptItem = scriptItemOrFullType
        fullType = Core.safeString(scriptItem, { "getFullName", "getName" }, "")
    end

    local moduleName, typeName = Core.splitFullType(fullType)
    if scriptItem then
        local readModuleName = Core.safeString(scriptItem, "getModuleName", moduleName)
        if readModuleName ~= "" then
            moduleName = readModuleName
        end

        local readTypeName = Core.safeString(scriptItem, { "getName", "getTypeString", "getDisplayName" }, typeName)
        if readTypeName ~= "" then
            typeName = readTypeName
        end

        if fullType == "" and moduleName ~= "" and typeName ~= "" then
            fullType = moduleName .. "." .. typeName
        end
    end

    local displayCategory = Core.safeString(scriptItem, { "getDisplayCategory", "getCategories" }, "")
    local itemType = Core.safeString(scriptItem, { "getTypeString", "getType" }, "")
    local displayName = Core.safeString(scriptItem, "getDisplayName", typeName)
    local ammoType = Core.safeString(scriptItem, { "getAmmoType", "getMagazineType" }, "")
    local magazineType = Core.safeString(scriptItem, "getMagazineType", "")
    local partType = Core.safeString(scriptItem, "getPartType", "")
    local mountOn = Core.safeString(scriptItem, "getMountOn", "")
    local canStack = Core.safeString(scriptItem, "getCanStack", "")
    local rangedToken = Core.safeString(scriptItem, { "isRanged", "getRanged" }, "")
    local aimedFirearmToken = Core.safeString(scriptItem, { "isAimedFirearm", "getIsAimedFirearm" }, "")
    local ammo = Core.safeCall(scriptItem, "getAmmoType", nil)
    local magazine = Core.safeCall(scriptItem, "getMagazineType", nil)
    local canBeEquipped = Core.safeString(scriptItem, "getCanBeEquipped", "")
    local acceptItemFunction = Core.safeString(scriptItem, "getAcceptItemFunction", "")
    local openSound = Core.safeString(scriptItem, "getOpenSound", "")
    local closeSound = Core.safeString(scriptItem, "getCloseSound", "")
    local putInSound = Core.safeString(scriptItem, "getPutInSound", "")
    local pourType = Core.safeString(scriptItem, "getPourType", "")
    local eatType = Core.safeString(scriptItem, "getEatType", "")
    local doubleClickRecipe = Core.safeString(scriptItem, "getDoubleClickRecipe", "")
    local icon = Core.safeString(scriptItem, { "getIcon", "getIconName" }, "")
    local bodyLocation = Core.safeString(scriptItem, "getBodyLocation", "")
    local lootType = Core.safeString(scriptItem, "getLootType", "")
    local learnedRecipes = Core.safeCall(scriptItem, "getLearnedRecipes", nil)
    local skillTrained = Core.safeString(scriptItem, "getSkillTrained", "")
    local readType = Core.safeString(scriptItem, "getReadType", "")
    local worldStaticModel = Core.safeString(scriptItem, "getWorldStaticModel", "")
    local worldObjectSprite = Core.safeString(scriptItem, "getWorldObjectSprite", "")
    local bloodClothingType = Core.safeString(scriptItem, "getBloodClothingType", "")

    if not instance then
        instance = Core.createTemporaryInstance(fullType)
        isTemporary = instance ~= nil
    end

    local isFoodInstance = false
    local isInventoryItemInstance = false
    local isLiteratureInstance = false
    if instance and type(instanceof) == "function" then
        isFoodInstance = instanceof(instance, "Food") == true
        isInventoryItemInstance = instanceof(instance, "InventoryItem") == true
        isLiteratureInstance = instanceof(instance, "Literature") == true
    end

    local fluidContainer = Core.safeCall(instance or scriptItem, "getFluidContainer", nil)
    local fluidType = ""
    local fluidCategory = ""
    local fluidTypeString = ""
    local fluidContainerName = ""
    if fluidContainer then
        fluidContainerName = Core.safeString(fluidContainer, "getContainerName", "")
        local fluid = Core.safeCall(fluidContainer, "getPrimaryFluid", nil)
        if fluid then
            fluidType = tostring(Core.safeCall(fluid, "getFluidType", ""))
            fluidCategory = tostring(Core.safeCall(fluid, "getFluidCategory", ""))
            fluidTypeString = Core.safeString(fluid, "getFluidTypeString", "")
        end
    end

    local modId = Core.safeString(scriptItem, { "getModID", "getModId", "getSourceMod" }, "")
    local modName = Core.safeString(scriptItem, { "getModName", "getModID", "getModId", "getSourceMod" }, "")

    if modId == "" and moduleName ~= "" then
        modId = moduleName
    end

    if modName == "" then
        if moduleName == "Base" then
            modName = "Project Zomboid (Vanilla)"
        elseif moduleName ~= "" then
            modName = moduleName
        else
            modName = "Unknown"
        end
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
        moduleName = moduleName,
        typeName = typeName,
        sourceModId = modId,
        sourceModName = modName,
        idLower = Core.lower(typeName),
        fullLower = Core.lower(fullType ~= "" and fullType or (moduleName .. "." .. typeName)),
        displayName = displayName,
        displayNameLower = Core.lower(displayName),

        displayCategory = displayCategory,
        displayCategoryLower = Core.lower(displayCategory),
        displayCategoryToken = normalizeToken(displayCategory),
        itemType = itemType,
        itemTypeLower = Core.lower(itemType),
        itemTypeToken = normalizeToken((string.match(Core.lower(itemType), "([^:]+)$") or itemType)),
        lootType = lootType,
        lootTypeLower = Core.lower(lootType),
        lootTypeToken = normalizeToken(lootType),

        weight = math.max(0, Core.safeNumber(scriptItem, { "getActualWeight", "getWeight" }, 0)),
        hunger = positiveMagnitude(Core.safeNumber(scriptItem, "getHungerChange", 0)),
        thirst = positiveMagnitude(Core.safeNumber(scriptItem, "getThirstChange", 0)),
        calories = math.max(0, Core.safeNumber(scriptItem, "getCalories", 0)),
        daysFresh = math.max(0, Core.safeNumber(scriptItem, "getDaysFresh", 0)),
        daysRotten = math.max(0, Core.safeNumber(scriptItem, "getDaysTotallyRotten", 0)),
        unhappy = positiveMagnitude(Core.safeNumber(scriptItem, { "getUnhappyChange", "getUnhappy" }, 0)),
        boredom = positiveMagnitude(Core.safeNumber(scriptItem, { "getBoredomChange", "getBoredom" }, 0)),
        stress = positiveMagnitude(Core.safeNumber(scriptItem, { "getStressChange", "getStress" }, 0)),

        minDamage = math.max(0, Core.safeNumber(scriptItem, "getMinDamage", 0)),
        maxDamage = math.max(0, Core.safeNumber(scriptItem, "getMaxDamage", 0)),
        maxRange = math.max(0, Core.safeNumber(scriptItem, "getMaxRange", 0)),
        maxHit = math.max(1, Core.safeNumber(scriptItem, "getMaxHitCount", 1)),
        conditionMax = math.max(0, Core.safeNumber(scriptItem, "getConditionMax", 0)),
        reliability = math.max(0, Core.safeNumber(scriptItem, { "getHitChance", "getAimingTime" }, 0)),
        useDelta = math.max(0, Core.safeNumber(scriptItem, "getUseDelta", 0)),

        capacity = math.max(0, Core.safeNumber(scriptItem, "getCapacity", 0)),
        weightReduction = math.max(0, Core.safeNumber(scriptItem, "getWeightReduction", 0)),

        biteDefense = math.max(0, Core.safeNumber(scriptItem, "getBiteDefense", 0)),
        scratchDefense = math.max(0, Core.safeNumber(scriptItem, "getScratchDefense", 0)),
        bulletDefense = math.max(0, Core.safeNumber(scriptItem, "getBulletDefense", 0)),
        insulation = math.max(0, Core.safeNumber(scriptItem, "getInsulation", 0)),
        windResistance = math.max(0, Core.safeNumber(scriptItem, "getWindResistance", 0)),
        bodyLocation = bodyLocation,
        bodyLocationLower = Core.lower(bodyLocation),
        bodyLocationToken = normalizeToken((string.match(Core.lower(bodyLocation), "([^:]+)$") or bodyLocation)),

        ammoType = ammoType,
        ammoTypeLower = Core.lower(ammoType),
        ammoTypeToken = normalizeToken((string.match(Core.lower(ammoType), "([^:]+)$") or ammoType)),
        magazineType = magazineType,
        magazineTypeLower = Core.lower(magazineType),
        magazineTypeToken = normalizeToken((string.match(Core.lower(magazineType), "([^:]+)$") or magazineType)),
        partType = partType,
        partTypeLower = Core.lower(partType),
        partTypeToken = normalizeToken(partType),
        mountOn = mountOn,
        mountOnLower = Core.lower(mountOn),
        canStack = canStack,
        canStackLower = Core.lower(canStack),
        rangedToken = rangedToken,
        rangedTokenLower = Core.lower(rangedToken),
        aimedFirearmToken = aimedFirearmToken,
        aimedFirearmTokenLower = Core.lower(aimedFirearmToken),
        canBeEquipped = canBeEquipped,
        canBeEquippedLower = Core.lower(canBeEquipped),
        acceptItemFunction = acceptItemFunction,
        acceptItemFunctionLower = Core.lower(acceptItemFunction),
        openSound = openSound,
        closeSound = closeSound,
        putInSound = putInSound,
        pourType = pourType,
        eatType = eatType,
        eatTypeLower = Core.lower(eatType),
        doubleClickRecipe = doubleClickRecipe,
        doubleClickRecipeLower = Core.lower(doubleClickRecipe),
        icon = icon,
        iconLower = Core.lower(icon),
        learnedRecipes = Core.listFromJavaCollection(learnedRecipes),
        skillTrained = skillTrained,
        skillTrainedLower = Core.lower(skillTrained),
        readType = readType,
        readTypeLower = Core.lower(readType),
        readTypeToken = normalizeToken(readType),
        worldStaticModel = worldStaticModel,
        worldStaticModelLower = Core.lower(worldStaticModel),
        worldObjectSprite = worldObjectSprite,
        worldObjectSpriteLower = Core.lower(worldObjectSprite),
        bloodClothingType = bloodClothingType,
        bloodClothingTypeLower = Core.lower(bloodClothingType),
        bloodClothingTypeToken = normalizeToken(bloodClothingType),
        
        fluidType = fluidType,
        fluidCategory = fluidCategory,
        fluidCategoryLower = Core.lower(fluidCategory),
        fluidTypeString = fluidTypeString,
        fluidTypeStringLower = Core.lower(fluidTypeString),
        fluidContainerName = fluidContainerName,
        fluidContainerNameLower = Core.lower(fluidContainerName),
        isFluidContainer = fluidContainer ~= nil,
        
        tags = tags,
        normalizedTagList = normalizedTagList,
        normalizedTags = normalizedTags,

        weaponCategories = Core.listFromJavaCollection(Core.safeCall(scriptItem, "getWeaponCategories", nil)),
        isTwoHandWeapon = Core.safeBoolean(scriptItem, "isTwoHandWeapon", false),
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
        customEatSound = Core.safeString(instance or scriptItem, "getCustomEatSound", ""),
        customEatSoundLower = Core.lower(Core.safeString(instance or scriptItem, "getCustomEatSound", "")),

        isMoveable = Core.startsWith(typeName, "Mov_"),
        hasWorldStaticModel = Core.safeString(scriptItem, "getWorldStaticModel", "") ~= "",
        isCookable = Core.safeBoolean(scriptItem, "isCookable", false),
        isDrainable = Core.safeBoolean(scriptItem, "isDrainable", false),
        canStoreWater = Core.safeBoolean(scriptItem, "CanStoreWater", false),
        hasOpenSound = openSound ~= "",
        hasCloseSound = closeSound ~= "",
        hasPutInSound = putInSound ~= "",
        hasPourType = pourType ~= "",
        hasEatType = eatType ~= "",
        hasFluidContainer = Core.safeBoolean(scriptItem, { "isCanStoreWater", "CanStoreWater" }, false),
        instanceCreated = instance ~= nil,
        isFoodInstance = isFoodInstance,
        isInventoryItemInstance = isInventoryItemInstance,
        isLiteratureInstance = isLiteratureInstance,
    }

    if isTemporary then
        Core.releaseTemporaryInstance(instance)
    end

    Cache.setContext(context.fullType, context)
    return Core.deepCopy(context)
end

return PropertyReader
