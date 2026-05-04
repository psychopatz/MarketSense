require "MarketSense/DT_Core"

DynamicTrading = DynamicTrading or {}
DynamicTrading.Signatures = DynamicTrading.Signatures or {}

local Core = DynamicTrading.Core
local Signature = {}

local LITERATURE_DISPLAY_CATS = {
    ["literature"] = true,
    ["skillbook"] = true,
    ["book"] = true,
    ["reciperesource"] = true,
    ["cartography"] = true,
}

local CARD_ID_PATTERNS = { "card_", "postcard", "carddeck", "tarotcarddeck" }
local LITERATURE_ID_PATTERNS = {
    "skillbook", "book", "mag", "magazine", "comic", "schematic", "manual",
    "guide", "journal", "recipeclipping", "tarotcarddeck", "carddeck", "card_", "postcard",
}
local MEDIA_ID_PATTERNS = { "vhs", "cassette", "disc_", "dvd", "cdplayer", "cd" }

local function containsAny(text, patterns)
    local source = tostring(text or "")
    if source == "" then
        return false
    end
    for _, pattern in ipairs(patterns or {}) do
        if string.find(source, pattern, 1, true) then
            return true
        end
    end
    return false
end

local function hasCollectionEntries(collection)
    if collection == nil then
        return false
    end
    local size = Core.safeNumber(collection, "size", 0)
    return size > 0
end

local function getMediaCategory(ctx)
    return Core.lower(Core.safeString(ctx.item, "getMediaCategory", ""))
end

local function hasMapProperty(ctx)
    if Core.safeBoolean(ctx.item, "isMap", false) then
        return true
    end
    local mapValue = Core.safeString(ctx.item, "getMap", "")
    return mapValue ~= ""
end

local function hasSkillLearning(ctx)
    return (ctx.skillTrained or "") ~= ""
end

local function hasRecipeLearning(ctx)
    if ctx.learnedRecipes and #ctx.learnedRecipes > 0 then
        return true
    end
    return Core.safeString(ctx.item, "getTeaches", "") ~= ""
end

local function hasReadingMetadata(ctx)
    return (Core.safeNumber(ctx.item, "getNumberOfPages", 0) > 0)
        or (Core.safeNumber(ctx.item, "getPageToWrite", 0) > 0)
        or Core.safeBoolean(ctx.item, "isCanBeWrite", false)
        or Core.safeString(ctx.item, "getLiteratureOnRead", "") ~= ""
end

local function isCardItem(itemLower)
    return containsAny(itemLower, CARD_ID_PATTERNS)
end

local function isLiteratureItem(ctx)
    local itemLower = tostring(ctx.idLower or "")
    local displayCategory = tostring(ctx.displayCategoryLower or "")
    local typeToken = tostring(ctx.itemTypeLower or "")

    local hasTypeLiterature = typeToken == "literature" or typeToken == "base:literature"
    local hasTypeMap = typeToken == "base:map"
    if typeToken == "base:container" then
        return false
    end

    local hasMap = hasMapProperty(ctx)
    local hasMediaCategory = getMediaCategory(ctx) ~= ""
    local hasRecipe = hasRecipeLearning(ctx)
    local hasSkill = hasSkillLearning(ctx)
    local hasReadingMeta = hasReadingMetadata(ctx)
    local looksLikeLiteratureId = containsAny(itemLower, LITERATURE_ID_PATTERNS)
    local looksLikeMediaId = containsAny(itemLower, MEDIA_ID_PATTERNS)

    local isGardenSeedLike = string.find(itemLower, "bagseed", 1, true) ~= nil
        or string.sub(itemLower, -4) == "seed"
        or string.find(itemLower, "_seed", 1, true) ~= nil
    if isGardenSeedLike then
        return false
    end

    if (ctx.ammoTypeLower or "") ~= "" then
        return false
    end
    if typeToken == "weapon" or typeToken == "base:weapon" then
        return false
    end

    if hasTypeLiterature or hasTypeMap then
        return true
    end
    if hasMap then
        return true
    end
    if hasMediaCategory then
        return true
    end
    if LITERATURE_DISPLAY_CATS[displayCategory] then
        return true
    end
    if looksLikeLiteratureId then
        return true
    end
    if displayCategory == "entertainment" and looksLikeMediaId then
        return true
    end
    if (hasRecipe or hasSkill or hasReadingMeta) and (looksLikeLiteratureId or displayCategory == "reciperesource") then
        return true
    end

    return (looksLikeLiteratureId and (hasRecipe or hasSkill or hasReadingMeta))
        or (looksLikeMediaId and hasMediaCategory)
end

local function success(confidence, primary, tags)
    return {
        matched = true,
        confidence = confidence,
        category = "Literature",
        primary = primary,
        tags = tags,
    }
end

function Signature.match(ctx)
    if not isLiteratureItem(ctx) then
        return { matched = false, confidence = 0 }
    end

    local itemLower = tostring(ctx.idLower or "")
    local displayCategory = tostring(ctx.displayCategoryLower or "")
    local typeToken = tostring(ctx.itemTypeLower or "")
    local hasRecipe = hasRecipeLearning(ctx)
    local hasSkill = hasSkillLearning(ctx)
    local hasMap = hasMapProperty(ctx)
    local hasMediaCategory = getMediaCategory(ctx) ~= ""

    local primary = "Literature.Book"

    if hasRecipe or string.find(itemLower, "schematic", 1, true) ~= nil or string.find(itemLower, "recipe", 1, true) ~= nil then
        primary = "Literature.Recipe"
    elseif hasMediaCategory or containsAny(itemLower, { "vhs", "cassette", "disc_", "dvd" }) then
        primary = "Literature.Media"
    elseif hasSkill or string.find(itemLower, "skillbook", 1, true) ~= nil then
        primary = "Literature.SkillBook"
    elseif isCardItem(itemLower) then
        primary = "Literature.Cards"
    elseif typeToken == "base:map" or hasMap or displayCategory == "cartography" then
        primary = "Literature.Media"
    elseif containsAny(itemLower, { "mag", "magazine", "comic" }) then
        primary = "Literature.Media"
    end

    return success(0.95, primary, { primary })
end

DynamicTrading.Signatures.Literature = Signature
return Signature
