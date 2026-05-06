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

function Signature.match(ctx)
    if not itemTypeIs(ctx, "container") then return { matched = false, confidence = 0 } end
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
    elseif ctx.isFluidContainer then
        return TagMapper.makeResult("ContainerLiquid", 0.88, { source = "container_liquid" })
    end

    return TagMapper.makeResult("ContainerBox", 0.85, { source = "container_box" })
end

MarketSense.Signatures.Container = Signature
return Signature
