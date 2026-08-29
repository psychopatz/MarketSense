require "MarketSense/signatures/tags/MS_TagMapper"
require "MarketSense/MS_TagEvidence"

MarketSense = MarketSense or {}
MarketSense.Signatures = MarketSense.Signatures or {}

local Signature = {}
local TagMapper = MarketSense.TagMapper
local TagEvidence = MarketSense.TagEvidence

local CUTLERY_TAGS = {
    fork = true, spoon = true, chopsticks = true, cutlery = true,
    butterknife = true, kitchenknife = true,
}

local UTENSIL_TAGS = {
    crudetongs = true, tongs = true, rollingpin = true, spatula = true,
    ladle = true, whisk = true, cookingutensil = true,
}

local function hasTag(ctx, token)
    return TagEvidence.has(ctx, token)
end

local function anyTag(ctx, map)
    local token = TagEvidence.best(ctx, map)
    return token
end

local function contains(text, token)
    return string.find(tostring(text or ""), token, 1, true) ~= nil
end

function Signature.match(ctx)
    local itemType = ctx.itemTypeToken or ""
    if itemType == "food" or itemType == "eat" or itemType == "eatsmall" then
        return { matched = false, confidence = 0 }
    end

    local disp = ctx.displayCategoryToken or ""
    local id = ctx.idLower or ""
    local name = ctx.displayNameLower or ""
    local search = id .. " " .. name .. " " .. (ctx.descriptionLower or "")
        .. " " .. (ctx.iconLower or "")
    local cookingDisplay = disp == "cooking" or disp == "cookingweapon"
    local tag = anyTag(ctx, CUTLERY_TAGS)
    if not tag then
        tag = anyTag(ctx, UTENSIL_TAGS)
    end

    if not cookingDisplay and not ctx.isCookable then
        if not tag and not contains(search, "pan") and not contains(search, "pot")
            and not contains(search, "cup") and not contains(search, "mug")
            and not contains(search, "glass") and not contains(search, "spoon")
            and not contains(search, "fork") and not contains(search, "tongs")
            and not contains(search, "spatula") and not contains(search, "ladle")
            and not contains(search, "whisk") and not contains(search, "bowl") then
            return { matched = false, confidence = 0 }
        end
    end

    tag = anyTag(ctx, CUTLERY_TAGS)
    if tag then
        return TagMapper.makeResult("CookingCutlery", 0.93, { source = "cooking_cutlery", tag = tag })
    end

    tag = anyTag(ctx, UTENSIL_TAGS)
    if tag then
        return TagMapper.makeResult("CookingUtensil", 0.92, { source = "cooking_utensil", tag = tag })
    end

    if ctx.canStoreWater or contains(string.lower(ctx.pourType or ""), "mug")
        or contains(search, "mug") or contains(search, "cup") or contains(search, "glass") then
        return TagMapper.makeResult("CookingCup", 0.90, { source = "cooking_cup" })
    end

    if ctx.isCookable or contains(search, "pan") or contains(search, "pot")
        or contains(search, "skillet") or contains(search, "saucepan")
        or contains(search, "wok") or contains(search, "griddle") then
        return TagMapper.makeResult("CookingPan", 0.91, { source = "cooking_pan" })
    end

    if cookingDisplay then
        return TagMapper.makeResult("Cooking", 0.88, { source = "cooking_display" })
    end

    return { matched = false, confidence = 0 }
end

MarketSense.Signatures.Cooking = Signature
return Signature
