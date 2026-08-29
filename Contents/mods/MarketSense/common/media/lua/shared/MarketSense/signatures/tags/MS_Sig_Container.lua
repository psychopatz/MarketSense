require "MarketSense/signatures/tags/MS_TagMapper"

MarketSense = MarketSense or {}
MarketSense.Signatures = MarketSense.Signatures or {}

local Signature = {}
local TagMapper = MarketSense.TagMapper

local AMMO_CONTAINER_TAGS = {
    "ammocase","reloadfastbullets","reloadfastmagazines","reloadfastshells"
}

local function hasTag(ctx, token)
    return ctx.normalizedTags and ctx.normalizedTags[token] == true
end
local function hasAnyTag(ctx, list)
    for _, t in ipairs(list) do if hasTag(ctx, t) then return true end end
    return false
end
local function itemTypeIs(ctx, t)
    return (ctx.itemTypeToken or "") == t
end
local function contains(text, token)
    return string.find(tostring(text or ""), token, 1, true) ~= nil
end

function Signature.match(ctx)
    local waterContainer = (ctx.displayCategoryToken or "") == "watercontainer"
        or ctx.canStoreWater == true
    if not itemTypeIs(ctx, "container") and not waterContainer then
        return { matched = false, confidence = 0 }
    end
    if hasTag(ctx, "hollowbook") then return { matched = false, confidence = 0 } end

    if hasTag(ctx, "keyring") then
        return TagMapper.makeResult("KeyRing", 0.98, { source = "container_keyring" })
    end

    local bl = ctx.bodyLocationToken or ""
    local hasBag = bl ~= "" or (ctx.bloodClothingTypeToken or ""):find("bag") ~= nil

    if hasBag then
        if hasAnyTag(ctx, AMMO_CONTAINER_TAGS) then
            return TagMapper.makeResult("ContainerWearableAmmo", 0.93, { source = "container_wearable_ammo" })
        end
        return TagMapper.makeResult("ContainerWearable", 0.93, { source = "container_wearable" })
    elseif hasTag(ctx, "ismemento") then
        return TagMapper.makeResult("MementoOrContainer", 0.85, { source = "container_memento" })
    elseif hasTag(ctx, "ammocase") then
        return TagMapper.makeResult("ContainerAmmo", 0.93, { source = "container_ammo" })
    elseif waterContainer then
        return TagMapper.makeResult("ContainerLiquid", 0.91, { source = "container_water" })
    elseif ctx.isFluidContainer then
        if (ctx.fluidTypeStringLower or "") ~= ""
            or (ctx.fluidTypeLower or "") ~= ""
            or (ctx.fluidCategoryLower or "") ~= "" then
            return { matched = false, confidence = 0 }
        end
        return TagMapper.makeResult("ContainerLiquid", 0.88, { source = "container_liquid" })
    end

    local text = (ctx.idLower or "") .. " " .. (ctx.displayNameLower or "") .. " "
        .. (ctx.descriptionLower or "") .. " " .. (ctx.iconLower or "")
    if contains(text, "box") or contains(text, "crate") or contains(text, "case") then
        return TagMapper.makeResult("ContainerBox", 0.85, { source = "container_box" })
    end

    return TagMapper.makeResult("Container", 0.80, { source = "container_generic" })
end

MarketSense.Signatures.Container = Signature
return Signature
