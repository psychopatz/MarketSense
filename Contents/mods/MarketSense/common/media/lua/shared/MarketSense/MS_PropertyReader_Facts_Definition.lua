require "MarketSense/MS_Core"
require "MarketSense/MS_PropertyReader_Signals"

MarketSense = MarketSense or {}

local Core = MarketSense.Core
local Signals = require "MarketSense/MS_PropertyReader_Signals"
local normalizeToken = Signals.normalizeToken

local function read(scriptItem, moduleName, typeName)
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
    local replaceOnCooked   = Core.safeString(scriptItem, "getReplaceOnCooked", "")
    local onCooked          = Core.safeString(scriptItem, "getOnCooked", "")
    local evolvedRecipe     = Core.safeString(scriptItem, "getEvolvedRecipe", "")
    local evolvedRecipeName = Core.safeString(scriptItem, "getEvolvedRecipeName", "")
    local canBeEquipped     = Core.safeString(scriptItem, "getCanBeEquipped", "")
    local acceptItemFunction = Core.safeString(scriptItem, "getAcceptItemFunction", "")
    local rangedToken       = Core.safeString(scriptItem, { "isRanged", "getRanged" }, "")
    local aimedFirearmToken = Core.safeString(scriptItem, { "isAimedFirearm", "getIsAimedFirearm" }, "")

    local modId = Core.safeString(scriptItem, { "getModID", "getModId", "getSourceMod" }, "")
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

    return {
        displayCategory = displayCategory,
        itemType = itemType,
        displayName = displayName,
        isHidden = isHidden,
        isObsolete = isObsolete,
        canSpawnAsLoot = canSpawnAsLoot,
        canBeForaged = canBeForaged,
        isCraftRecipeProduct = isCraftRecipeProduct,
        ammoType = ammoType,
        magazineType = magazineType,
        partType = partType,
        mountOn = mountOn,
        canStack = canStack,
        bodyLocation = bodyLocation,
        lootType = lootType,
        eatType = eatType,
        foodType = foodType,
        icon = icon,
        learnedRecipes = learnedRecipes,
        skillTrained = skillTrained,
        lvlSkillTrained = lvlSkillTrained,
        maxLevelTrained = maxLevelTrained,
        readType = readType,
        worldStaticModel = worldStaticModel,
        worldObjectSprite = worldObjectSprite,
        bloodClothingType = bloodClothingType,
        openSound = openSound,
        closeSound = closeSound,
        putInSound = putInSound,
        pourType = pourType,
        doubleClickRecipe = doubleClickRecipe,
        openingRecipe = openingRecipe,
        replaceOnDeplete = replaceOnDeplete,
        replaceOnCooked = replaceOnCooked,
        onCooked = onCooked,
        evolvedRecipe = evolvedRecipe,
        evolvedRecipeName = evolvedRecipeName,
        canBeEquipped = canBeEquipped,
        acceptItemFunction = acceptItemFunction,
        rangedToken = rangedToken,
        aimedFirearmToken = aimedFirearmToken,
        modId = modId,
        modName = modName,
        tags = tags,
        normalizedTags = normalizedTags,
        normalizedTagList = normalizedTagList,
    }
end

return { read = read }

