require "MarketSense/signatures/tags/MS_TagMapper"

MarketSense = MarketSense or {}
MarketSense.Signatures = MarketSense.Signatures or {}

local Signature = {}
local TagMapper = MarketSense.TagMapper

local JEWELRY_TAGS = {
    "amethystjewellery","diamondjewellery","emeraldjewellery","rubyjewellery",
    "sapphirejewellery","tinygoldscrap","tinysilverscrap","smallgoldscrap",
    "smallsilverscrap",
}

-- Body location token → display-category key
local BLTOK_TO_CAT = {
    dress="ClothingFullBody", longdress="ClothingFullBody",
    bodycostume="ClothingFullBody", fullsuit="ClothingFullBody",
    fullrobe="ClothingFullBody", bathrobe="ClothingFullBody",
    boilersuit="ClothingFullBody", pantsextra="ClothingFullBody",
    fullsuithead="ClothingFullBody", fullsuitheadscba="ClothingFullBody",
    jacket="ClothingOuterwear", jacketbulky="ClothingOuterwear",
    jacketdown="ClothingOuterwear", jacketsuit="ClothingOuterwear",
    fulltop="ClothingOuterwear", jackethat="ClothingOuterwear",
    jackethatbulky="ClothingOuterwear", torsoextravest="ClothingOuterwear",
    vesttexture="ClothingOuterwear",
    shirt="ClothingTop", tshirt="ClothingTop", shortsleeveshirt="ClothingTop",
    tanktop="ClothingTop", jersey="ClothingTop", sweater="ClothingTop",
    sweaterhat="ClothingTop", cuirass="ClothingTop",
    longskirt="ClothingBottom", pants="ClothingBottom",
    pantsskinny="ClothingBottom", shortsshort="ClothingBottom",
    shortpants="ClothingBottom", skirt="ClothingBottom",
    legs1="ClothingBottom", legs5="ClothingBottom",
    shoes="ClothingFootwear",
    socks="ClothingSocks",
    hands="ClothingHands", handsleft="ClothingHands", handsright="ClothingHands",
    hat="ClothingHead", fullhat="ClothingHead",
    underwear="ClothingUnderwear", underweartop="ClothingUnderwear",
    underwearbottom="ClothingUnderwear", underwearBottom="ClothingUnderwear", underwearextra1="ClothingUnderwear",
    underwearextra2="ClothingUnderwear", codpiece="ClothingUnderwear",
    torso1legs1="ClothingUnderwear",
    satchel="Accessory", scbanotank="Accessory", belt="Accessory",
    beltextra="Accessory",
    neck="AccessoryNeck", necklace="AccessoryNeck", necklacelong="AccessoryNeck",
    scarf="AccessoryNeck", gorget="AccessoryNeck", necktexture="AccessoryNeck",
    leftwrist="AccessoryArms", rightwrist="AccessoryArms",
    forearmleft="AccessoryArms", forearmright="AccessoryArms",
    leftarm="AccessoryArms", rightarm="AccessoryArms",
    elbowleft="AccessoryArms", elbowright="AccessoryArms",
    shoulderpadleft="AccessoryArms", shoulderparleft="AccessoryArms", shoulderpadright="AccessoryArms",
    sportsshoulderpad="AccessoryArms", sportsshoulderpadontop="AccessoryArms",
    leftringfinger="AccessoryHands", leftmiddlefinger="AccessoryHands",
    rightmiddlefinger="AccessoryHands", rightringfinger="AccessoryHands",
    ankleholster="AccessoryLegs", calfleft="AccessoryLegs",
    calfright="AccessoryLegs", calflefttexture="AccessoryLegs",
    calfrighttexture="AccessoryLegs", thighleft="AccessoryLegs",
    thighright="AccessoryLegs", gaiterleft="AccessoryLegs",
    gaiterright="AccessoryLegs", kneeleft="AccessoryLegs", kneeright="AccessoryLegs",
    shoulderholster="AccessoryTop", webbing="AccessoryTop",
    bellybutton="AccessoryTop", tail="AccessoryTop", back="AccessoryTop",
    ammostrap="AccessoryTop", torsoextra="AccessoryTop",
    torsoextravestbullet="AccessoryTop", torsoextravstbullet="AccessoryTop", fannypackback="AccessoryTop",
    fannypackfront="AccessoryTop",
    ears="AccessoryHead", eartop="AccessoryHead",
    mask="AccessoryFace", maskeyes="AccessoryFace", maskfull="AccessoryFace",
    eyes="AccessoryFace", nose="AccessoryFace", lefteye="AccessoryFace",
    righteye="AccessoryFace", makeup="AccessoryFace", scba="AccessoryFace",
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
    local bl = ctx.bodyLocationToken or ""
    if bl == "" then return { matched = false, confidence = 0 } end
    if bl == "wound" or bl == "bandage" or bl == "zeddmg" then
        return { matched = false, confidence = 0 }
    end
    if itemTypeIs(ctx, "container") then return { matched = false, confidence = 0 } end

    if hasAnyTag(ctx, JEWELRY_TAGS) then
        return TagMapper.makeResult("AccessoryJewelry", 0.92, { source = "apparel_jewelry" })
    end

    local origDisp = ctx.displayCategoryToken or ""
    local cat = BLTOK_TO_CAT[bl]
    if cat and origDisp == "protectivegear" then
        cat = cat:gsub("Clothing", "ProtectiveGear"):gsub("Accessory", "ProtectiveGear")
    end

    if cat then
        return TagMapper.makeResult(cat, 0.91, { source = "apparel_bodyloc", bl = bl })
    end
    return { matched = false, confidence = 0 }
end

MarketSense.Signatures.Apparel = Signature
return Signature
