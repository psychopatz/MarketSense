require "MarketSense/DT_Core"

DynamicTrading = DynamicTrading or {}
DynamicTrading.Signatures = DynamicTrading.Signatures or {}

local Core = DynamicTrading.Core
local Signature = {}

local BACKPACK_ID_PATTERNS = { "backpack", "rucksack", "hikingbag", "schoolbag", "knapsack", "golfbag" }
local DUFFEL_ID_PATTERNS = { "duffel", "toolbag", "weaponbag", "medicalbag", "moneybag", "shotgunbag", "workerbag" }
local SATCHEL_ID_PATTERNS = { "satchel" }
local HANDBAG_ID_PATTERNS = { "purse", "handbag" }
local COOLER_ID_PATTERNS = { "cooler" }
local SACK_ID_PATTERNS = { "sack", "sandbag", "wheatsack", "seedsack" }
local BAG_ID_PATTERNS = {
    "bag_", "purse", "tote", "plasticbag", "garbagebag", "lunchbag",
    "briefcase", "satchel", "handbag", "grocerybag", "sack", "sandbag", "cooler",
}
local LIQUID_BUCKET_PATTERNS = { "bucket", "pail", "waterdish" }
local LIQUID_JAR_PATTERNS = { "jar" }
local LIQUID_BOTTLE_PATTERNS = { "bottle", "flask", "canteen", "wineskin", "waterbag" }
local LIQUID_CUP_PATTERNS = { "mug", "cup", "glass", "goblet", "tumbler", "bowl" }
local STASH_CASE_PATTERNS = { "lunchbox", "cookiejar", "case", "box", "tin", "cache", "parcel", "present", "album" }
local COOKWARE_LIQUID_EXCLUDES = { "saucepan", "cookingpot", "pot", "kettle" }

local LIQUID_WEARABLE_BODY_LOCATIONS = { ["base:satchel"] = true, ["base:back"] = true }
local WEARABLE_FANNY_LOCATIONS = { ["base:fannypackfront"] = true, ["base:fannypackback"] = true }
local WEARABLE_RIG_LOCATIONS = { ["base:webbing"] = true }
local WEARABLE_BANDOLIER_LOCATIONS = { ["base:ammostrap"] = true }
local WEARABLE_HOLSTER_LOCATIONS = { ["base:shoulderholster"] = true, ["base:ankleholster"] = true }

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

local function hasScriptTag(ctx, expected)
    for _, tag in ipairs(ctx.tags or {}) do
        if expected[Core.lower(tag)] then
            return true
        end
    end
    return false
end

local function classifyCapacityBand(capacity)
    if capacity >= 20 then
        return "High"
    elseif capacity >= 10 then
        return "Medium"
    elseif capacity > 3 then
        return "Low"
    end
    return "Tiny"
end

local function success(confidence, primary, tags)
    return {
        matched = true,
        confidence = confidence,
        category = "Container",
        primary = primary,
        tags = tags,
    }
end

function Signature.match(ctx)
    local capacity = math.max(0, tonumber(ctx.capacity) or 0)
    if capacity <= 0 then
        return { matched = false, confidence = 0 }
    end

    local displayCategory = tostring(ctx.displayCategoryLower or "")
    local bodyLocation = tostring(ctx.bodyLocationLower or "")
    local itemLower = tostring(ctx.idLower or "")
    local weightReduction = math.max(0, tonumber(ctx.weightReduction) or 0)

    local isContainerType = (ctx.itemTypeLower or "") == "base:container" or (ctx.itemTypeLower or "") == "container"
    local isClothingType = (ctx.itemTypeLower or "") == "base:clothing" or (ctx.itemTypeLower or "") == "base:alarmclockclothing"
    local hasFluidContainer = ctx.hasFluidContainer or ctx.canStoreWater
    local hasContainerIO = ctx.hasOpenSound or ctx.hasCloseSound or ctx.hasPutInSound
        or (ctx.canBeEquippedLower or "") ~= ""
        or (ctx.acceptItemFunctionLower or "") ~= ""
    local canBeEquipped = (ctx.canBeEquippedLower or "") ~= ""

    local isHollowBook = hasScriptTag(ctx, { ["base:hollowbook"] = true }) or string.find(itemLower, "hollowbook", 1, true) ~= nil
    local isKeyring = hasScriptTag(ctx, { ["base:keyring"] = true })
        or string.find(ctx.acceptItemFunctionLower or "", "acceptitemfunction.keyring", 1, true) ~= nil
    local isAmmoCase = hasScriptTag(ctx, { ["base:ammocase"] = true })
    
    local isRecipePackage = containsAny(ctx.doubleClickRecipeLower or "", { "unpack", "open", "takea" })
    local isIconPackage = containsAny(ctx.iconLower or "", { "parcel", "carton" })
    local isPackage = (isRecipePackage or isIconPackage) and containsAny(itemLower, { "box", "carton", "parcel", "bundle", "pack" })

    local isCookwareLiquid = hasFluidContainer
        and (displayCategory == "cooking" or displayCategory == "cookingweapon")
        and containsAny(itemLower, COOKWARE_LIQUID_EXCLUDES)

    if isCookwareLiquid then
        return { matched = false, confidence = 0 }
    end

    if not (hasFluidContainer or isContainerType or isClothingType or hasContainerIO) then
        return { matched = false, confidence = 0 }
    end

    local primary = "Container.General"
    local tags = {}

    if hasFluidContainer then
        if LIQUID_WEARABLE_BODY_LOCATIONS[bodyLocation] or (canBeEquipped and (isClothingType or bodyLocation ~= "")) then
            primary = "Container.Liquid.Wearable"
        elseif containsAny(itemLower, LIQUID_BUCKET_PATTERNS) or hasScriptTag(ctx, { ["base:bucket"] = true }) then
            primary = "Container.Liquid.Bucket"
        elseif containsAny(itemLower, LIQUID_JAR_PATTERNS) or hasScriptTag(ctx, { ["base:jar"] = true }) then
            primary = "Container.Liquid.Jar"
        elseif containsAny(itemLower, { "can" }) then
            primary = "Container.Liquid.Can"
        elseif containsAny(itemLower, LIQUID_BOTTLE_PATTERNS) then
            primary = "Container.Liquid.Bottle"
        elseif containsAny(itemLower, LIQUID_CUP_PATTERNS) then
            primary = "Container.Liquid.Cup"
        else
            primary = "Container.Liquid.General"
        end
    elseif isKeyring then
        primary = "Container.Utility.KeyRing"
    elseif isHollowBook then
        primary = "Container.Stash.Book"
    elseif isPackage then
        primary = "Container.Package"
    elseif WEARABLE_FANNY_LOCATIONS[bodyLocation] then
        primary = "Container.Bag.Fanny"
    elseif WEARABLE_RIG_LOCATIONS[bodyLocation] then
        primary = "Container.Bag.Rig"
    elseif WEARABLE_BANDOLIER_LOCATIONS[bodyLocation] or isAmmoCase then
        primary = "Container.Bag.Bandolier"
    elseif WEARABLE_HOLSTER_LOCATIONS[bodyLocation] then
        primary = "Container.Bag.Holster"
    elseif containsAny(itemLower, DUFFEL_ID_PATTERNS) then
        primary = "Container.Bag.Duffel"
    elseif containsAny(itemLower, SATCHEL_ID_PATTERNS) then
        primary = "Container.Bag.Satchel"
    elseif containsAny(itemLower, HANDBAG_ID_PATTERNS) then
        primary = "Container.Bag.Handbag"
    elseif containsAny(itemLower, COOLER_ID_PATTERNS) then
        primary = "Container.Bag.Cooler"
    elseif containsAny(itemLower, SACK_ID_PATTERNS) then
        primary = "Container.Bag.Sack"
    elseif (ctx.canBeEquippedLower or "") == "base:back" or bodyLocation == "base:back" or containsAny(itemLower, BACKPACK_ID_PATTERNS) then
        primary = "Container.Bag.Backpack"
    elseif displayCategory == "bag" or containsAny(itemLower, BAG_ID_PATTERNS) then
        primary = "Container.Bag.General"
    elseif containsAny(itemLower, STASH_CASE_PATTERNS) or (isContainerType and capacity <= 4 and bodyLocation == "" and not canBeEquipped) then
        primary = "Container.Stash.Case"
    elseif isContainerType then
        primary = "Container.General"
    else
        return { matched = false, confidence = 0 }
    end

    tags[#tags + 1] = primary

    tags[#tags + 1] = "Container.Capacity." .. classifyCapacityBand(capacity)

    if weightReduction >= 80 then
        tags[#tags + 1] = "Container.WeightReduction.High"
    elseif weightReduction >= 50 then
        tags[#tags + 1] = "Container.WeightReduction.Medium"
    elseif weightReduction > 0 then
        tags[#tags + 1] = "Container.WeightReduction.Low"
    end

    if hasFluidContainer then
        tags[#tags + 1] = "Container.Liquid"
    end

    if bodyLocation ~= "" or canBeEquipped then
        tags[#tags + 1] = "Container.Wearable"
    end

    local evidence = 0.3
    if hasFluidContainer then evidence = evidence + 0.3 end
    if isContainerType then evidence = evidence + 0.25 end
    if isClothingType and hasFluidContainer then evidence = evidence + 0.15 end
    if hasContainerIO then evidence = evidence + 0.15 end
    if bodyLocation ~= "" or canBeEquipped then evidence = evidence + 0.1 end
    if weightReduction > 0 then evidence = evidence + 0.1 end
    if primary ~= "Container.General" then evidence = evidence + 0.15 end

    local confidence = math.min(1.0, evidence)
    if confidence < 0.45 then
        return { matched = false, confidence = confidence }
    end

    return success(confidence, primary, tags)
end

DynamicTrading.Signatures.Container = Signature
return Signature
