require "MarketSense/DT_RuntimeCache"

DynamicTrading = DynamicTrading or {}
DynamicTrading.PropertyReader = DynamicTrading.PropertyReader or {}

local PropertyReader = DynamicTrading.PropertyReader
local Core = DynamicTrading.Core
local Cache = DynamicTrading.RuntimeCache

local function positiveMagnitude(value)
    return math.abs(tonumber(value) or 0)
end

function PropertyReader.buildContext(scriptItemOrFullType)
    if type(scriptItemOrFullType) == "table" and scriptItemOrFullType.fullType and scriptItemOrFullType.item ~= nil then
        return scriptItemOrFullType
    end

    local scriptItem = nil
    local fullType = nil

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
    local canBeEquipped = Core.safeString(scriptItem, "getCanBeEquipped", "")
    local acceptItemFunction = Core.safeString(scriptItem, "getAcceptItemFunction", "")
    local openSound = Core.safeString(scriptItem, "getOpenSound", "")
    local closeSound = Core.safeString(scriptItem, "getCloseSound", "")
    local putInSound = Core.safeString(scriptItem, "getPutInSound", "")
    local pourType = Core.safeString(scriptItem, "getPourType", "")
    local eatType = Core.safeString(scriptItem, "getEatType", "")
    local bodyLocation = Core.safeString(scriptItem, "getBodyLocation", "")
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
        itemType = itemType,
        itemTypeLower = Core.lower(itemType),

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

        ammoType = ammoType,
        ammoTypeLower = Core.lower(ammoType),
        magazineType = magazineType,
        magazineTypeLower = Core.lower(magazineType),
        partType = partType,
        partTypeLower = Core.lower(partType),
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
        tags = Core.safeTags(scriptItem),

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
    }

    Cache.setContext(context.fullType, context)
    return Core.deepCopy(context)
end

return PropertyReader
