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

function Signature.match(ctx)
    local disp = ctx.displayCategoryToken or ""
    local text = (ctx.idLower or "") .. " " .. (ctx.displayNameLower or "") .. " "
        .. (ctx.descriptionLower or "") .. " " .. (ctx.iconLower or "")
    if (ctx.itemTypeToken or "") == "weapon" and hasTag(ctx, "firearm") and disp ~= "ammo" then
        return { matched = false, confidence = 0 }
    end

    local isAmmo = disp == "ammo" or (ctx.lootTypeLower or "") == "ammo"
        or hasTag(ctx, "ammo") or (ctx.ammoTypeLower or "") ~= "" or (ctx.magazineTypeLower or "") ~= ""

    if not isAmmo then
        return { matched = false, confidence = 0 }
    end

    if hasTag(ctx, "ammocase") then
        return TagMapper.makeResult("AmmoBox", 0.95, { source = "ammo_case" })
    end
    if contains(text, "magazine") or contains(text, "clip") or contains(text, "mag") then
        return TagMapper.makeResult("AmmoMag", 0.94, { source = "ammo_mag" })
    end
    if contains(text, "carton") then
        return TagMapper.makeResult("AmmoCarton", 0.93, { source = "ammo_carton" })
    end
    if contains(text, "box") or contains(text, "shells") then
        return TagMapper.makeResult("AmmoBox", 0.93, { source = "ammo_box" })
    end

    return TagMapper.makeResult("Ammo", 0.95, { source = "ammo_auto" })
end

MarketSense.Signatures.Ammo = Signature
return Signature
