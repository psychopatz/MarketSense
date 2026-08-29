require "MarketSense/signatures/tags/MS_TagMapper"
require "MarketSense/MS_TagEvidence"

MarketSense = MarketSense or {}
MarketSense.Signatures = MarketSense.Signatures or {}

local Signature = {}
local TagMapper = MarketSense.TagMapper
local TagEvidence = MarketSense.TagEvidence

local function hasTag(ctx, token)
    return TagEvidence.has(ctx, token)
end

local function contains(text, token)
    return string.find(tostring(text or ""), token, 1, true) ~= nil
end

local function ammoLike(ctx)
    local disp = ctx.displayCategoryToken or ""
    return disp == "ammo" or hasTag(ctx, "ammo") or hasTag(ctx, "ammocase")
        or (ctx.ammoTypeLower or "") ~= "" or (ctx.magazineTypeLower or "") ~= ""
end

function Signature.match(ctx)
    local id = ctx.idLower or ""
    local name = ctx.displayNameLower or ""
    local icon = ctx.iconLower or ""
    local text = id .. " " .. name .. " " .. icon

    if not contains(text, "box") and not contains(text, "carton")
        and not contains(text, "pack") and not contains(text, "stack")
        and not contains(text, "bundle") then
        return { matched = false, confidence = 0 }
    end

    if ammoLike(ctx) then
        if contains(text, "mag") or contains(text, "clip") then
            return TagMapper.makeResult("AmmoMag", 0.89, { source = "boxes_ammo_mag" })
        end
        if contains(text, "carton") then
            return TagMapper.makeResult("AmmoCarton", 0.89, { source = "boxes_ammo_carton" })
        end
        return TagMapper.makeResult("AmmoBox", 0.89, { source = "boxes_ammo_box" })
    end

    if contains(text, "bundle") or contains(text, "stack") then
        if (ctx.lootTypeLower or "") == "material" or hasTag(ctx, "twigs") or hasTag(ctx, "wood") then
            return TagMapper.makeResult("MaterialBundled", 0.86, { source = "boxes_material_bundle" })
        end
    end

    if contains(text, "box") and ((ctx.itemTypeToken or "") == "container" or (ctx.capacity or 0) > 0) then
        return TagMapper.makeResult("ContainerBox", 0.84, { source = "boxes_container" })
    end

    return { matched = false, confidence = 0 }
end

MarketSense.Signatures.BoxesAndStacks = Signature
return Signature
