require "MarketSense/DT_Core"

DynamicTrading = DynamicTrading or {}
DynamicTrading.Signatures = DynamicTrading.Signatures or {}

local Core = DynamicTrading.Core
local Signature = {}

local EXCLUDED_BODY_LOCATIONS = { ["base:zeddmg"] = true, ["base:wound"] = true, ["base:bandage"] = true }
local COSMETIC_BODY_LOCATIONS = {
    ["base:makeup_fullface"] = true,
    ["base:makeup_eyes"] = true,
    ["base:makeup_eyesshadow"] = true,
    ["base:makeup_lips"] = true,
}
local JEWELRY_TAGS = {
    ["base:amethyst_jewellery"] = true,
    ["base:diamond_jewellery"] = true,
    ["base:emerald_jewellery"] = true,
    ["base:ruby_jewellery"] = true,
    ["base:sapphire_jewellery"] = true,
    ["base:two_diamond_jewellery"] = true,
    ["base:two_emerald_jewellery"] = true,
    ["base:two_ruby_jewellery"] = true,
    ["base:two_sapphire_jewellery"] = true,
    
    -- Jewelry Scrap (Robust)
    ["base:tinygoldscrap"] = true, ["base:tinysilverscrap"] = true,
    ["base:smallgoldscrap"] = true, ["base:smallsilverscrap"] = true,
    ["base:smallergoldscrap"] = true, ["base:smallersilverscrap"] = true,
    ["base:smallestgoldscrap"] = true, ["base:smallestsilverscrap"] = true,
}

local HEAD_LOCATIONS = { ["base:hat"] = true, ["base:fullhat"] = true, ["base:jackethat"] = true, ["base:sweaterhat"] = true, ["base:fullsuithead"] = true }
local FACE_LOCATIONS = { ["base:mask"] = true, ["base:maskeyes"] = true, ["base:maskfull"] = true, ["base:scba"] = true, ["base:scbanotank"] = true }
local EYE_LOCATIONS = { ["base:eyes"] = true, ["base:lefteye"] = true, ["base:righteye"] = true }
local HAND_LOCATIONS = { ["base:hands"] = true, ["base:handsleft"] = true, ["base:handsright"] = true }
local FOOT_LOCATIONS = { ["base:shoes"] = true, ["base:socks"] = true, ["base:gaiter_left"] = true, ["base:gaiter_right"] = true }
local TOP_LOCATIONS = { ["base:tshirt"] = true, ["base:shirt"] = true, ["base:shortsleeveshirt"] = true, ["base:tanktop"] = true, ["base:sweater"] = true, ["base:jersey"] = true, ["base:fulltop"] = true }
local OUTERWEAR_LOCATIONS = {
    ["base:jacket"] = true,
    ["base:jacketsuit"] = true,
    ["base:jacket_bulky"] = true,
    ["base:jacket_down"] = true,
    ["base:torsoextra"] = true,
    ["base:torsoextravest"] = true,
    ["base:bathrobe"] = true,
}
local BOTTOM_LOCATIONS = {
    ["base:pants"] = true,
    ["base:pants_skinny"] = true,
    ["base:shortpants"] = true,
    ["base:shortsshort"] = true,
    ["base:skirt"] = true,
    ["base:longskirt"] = true,
    ["base:legs1"] = true,
    ["base:pantsextra"] = true,
}
local UNDERWEAR_TOP_LOCATIONS = { ["base:underweartop"] = true, ["base:underwearextra1"] = true, ["base:underwearextra2"] = true }
local UNDERWEAR_BOTTOM_LOCATIONS = { ["base:underwearbottom"] = true }
local UNDERWEAR_FULL_LOCATIONS = { ["base:underwear"] = true }
local DRESS_LOCATIONS = { ["base:dress"] = true, ["base:longdress"] = true }
local FULLBODY_LOCATIONS = { ["base:boilersuit"] = true, ["base:fullsuit"] = true, ["base:torso1legs1"] = true }
local UTILITY_ACCESSORY_LOCATIONS = {
    ["base:belt"] = true,
    ["base:beltextra"] = true,
    ["base:webbing"] = true,
    ["base:ammostrap"] = true,
    ["base:fannypackfront"] = true,
    ["base:fannypackback"] = true,
    ["base:shoulderholster"] = true,
    ["base:ankleholster"] = true,
    ["base:back"] = true,
    ["base:satchel"] = true,
}
local NECK_ACCESSORY_LOCATIONS = { ["base:scarf"] = true, ["base:neck"] = true }
local WRIST_LOCATIONS = { ["base:leftwrist"] = true, ["base:rightwrist"] = true }
local JEWELRY_EAR_LOCATIONS = { ["base:ears"] = true, ["base:eartop"] = true }
local JEWELRY_NECK_LOCATIONS = { ["base:necklace"] = true, ["base:necklace_long"] = true }
local JEWELRY_RING_LOCATIONS = {
    ["base:left_middlefinger"] = true,
    ["base:right_middlefinger"] = true,
    ["base:left_ringfinger"] = true,
    ["base:right_ringfinger"] = true,
}

local ARMOR_LOCATIONS = {
    ["base:torsoextravestbullet"] = true,
    ["base:cuirass"] = true,
    ["base:gorget"] = true,
    ["base:calf_right"] = true,
    ["base:calf_left"] = true,
    ["base:thigh_right"] = true,
    ["base:thigh_left"] = true,
    ["base:forearm_right"] = true,
    ["base:forearm_left"] = true,
    ["base:elbow_right"] = true,
    ["base:elbow_left"] = true,
    ["base:knee_right"] = true,
    ["base:knee_left"] = true,
    ["base:shoulderpadleft"] = true,
    ["base:shoulderpadright"] = true,
    ["base:sportshoulderpad"] = true,
    ["base:sportshoulderpadontop"] = true,
    ["base:rightarm"] = true,
    ["base:leftarm"] = true,
    ["base:codpiece"] = true,
}

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

local function resolveArmorSlot(body)
    if HEAD_LOCATIONS[body] then return "Head" end
    if FACE_LOCATIONS[body] then return "Face" end
    if HAND_LOCATIONS[body] then return "Hands" end
    if FOOT_LOCATIONS[body] then return "Feet" end
    if body == "base:gorget" then return "Neck" end
    if string.find(body, "arm", 1, true) ~= nil or string.find(body, "shoulder", 1, true) ~= nil then return "Arms" end
    if string.find(body, "calf", 1, true) ~= nil or string.find(body, "thigh", 1, true) ~= nil or string.find(body, "knee", 1, true) ~= nil then return "Legs" end
    return "Torso"
end

local function resolveNonArmorSlot(ctx, itemLower, displayCategory, body)
    if COSMETIC_BODY_LOCATIONS[body] then return "Accessory.Cosmetic" end
    if JEWELRY_EAR_LOCATIONS[body] then return "Accessory.Jewelry.Ears" end
    if JEWELRY_NECK_LOCATIONS[body] then return "Accessory.Jewelry.Necklace" end
    if JEWELRY_RING_LOCATIONS[body] then return "Accessory.Jewelry.Ring" end
    if WRIST_LOCATIONS[body] then
        if string.find(itemLower, "watch", 1, true) ~= nil then
            return "Accessory.Wrist.Watch"
        end
        return "Accessory.Wrist"
    end
    if EYE_LOCATIONS[body] then return "Accessory.Eyes" end
    if NECK_ACCESSORY_LOCATIONS[body] then return "Accessory.Neck" end
    if UTILITY_ACCESSORY_LOCATIONS[body] then return "Accessory.Utility" end
    if HEAD_LOCATIONS[body] then return "Head" end
    if FACE_LOCATIONS[body] then return "Face" end
    if HAND_LOCATIONS[body] then return "Hands" end
    if FOOT_LOCATIONS[body] then return "Feet" end
    if UNDERWEAR_TOP_LOCATIONS[body] then return "Underwear.Top" end
    if UNDERWEAR_BOTTOM_LOCATIONS[body] then return "Underwear.Bottom" end
    if UNDERWEAR_FULL_LOCATIONS[body] then return "Underwear.General" end
    if DRESS_LOCATIONS[body] then return "Dress" end
    if FULLBODY_LOCATIONS[body] then return "FullBody" end
    if OUTERWEAR_LOCATIONS[body] then return "Outerwear" end
    if TOP_LOCATIONS[body] then return "Top" end
    if BOTTOM_LOCATIONS[body] then return "Bottom" end

    if displayCategory == "accessory" or hasScriptTag(ctx, JEWELRY_TAGS) then
        if hasScriptTag(ctx, JEWELRY_TAGS) or containsAny(itemLower, { "ring", "necklace", "earring", "bracelet", "locket", "dogtag" }) then
            return "Accessory.Jewelry"
        end
        return "Accessory"
    end
    if containsAny(itemLower, { "dress", "gown" }) then return "Dress" end
    if containsAny(itemLower, { "jacket", "coat", "vest", "robe", "poncho" }) then return "Outerwear" end
    if containsAny(itemLower, { "shirt", "tshirt", "sweater", "jumper", "blouse", "jersey" }) then return "Top" end
    if containsAny(itemLower, { "pants", "trousers", "shorts", "skirt" }) then return "Bottom" end
    if containsAny(itemLower, { "shoe", "boot", "sneaker", "sock" }) then return "Feet" end
    if containsAny(itemLower, { "glove", "mitt" }) then return "Hands" end
    if containsAny(itemLower, { "hat", "cap", "helmet" }) then return "Head" end
    if containsAny(itemLower, { "mask", "gasmask" }) then return "Face" end
    return "General"
end

local function success(confidence, primary, tags)
    return {
        matched = true,
        confidence = confidence,
        category = "Clothing",
        primary = primary,
        tags = tags,
    }
end

function Signature.match(ctx)
    local body = tostring(ctx.bodyLocationLower or "")
    local itemLower = tostring(ctx.idLower or "")
    local displayCategory = tostring(ctx.displayCategoryLower or "")
    local isClothingType = (ctx.itemTypeLower or "") == "clothing" or (ctx.itemTypeLower or "") == "base:clothing" or (ctx.itemTypeLower or "") == "base:alarmclockclothing"
    local canEquip = body ~= "" or isClothingType

    if not canEquip or EXCLUDED_BODY_LOCATIONS[body] or string.sub(itemLower, 1, 7) == "zeddmg_" or string.sub(itemLower, 1, 6) == "wound_" or string.sub(itemLower, 1, 8) == "bandage_" then
        return { matched = false, confidence = 0 }
    end

    local bite = tonumber(ctx.biteDefense) or 0
    local scratch = tonumber(ctx.scratchDefense) or 0
    local bullet = tonumber(ctx.bulletDefense) or 0
    local blunt = tonumber(ctx.bluntDefense) or 0
    local maxDefense = math.max(bite, scratch, bullet, blunt)
    local isArmor = displayCategory == "protectivegear" or ARMOR_LOCATIONS[body] == true or bullet > 0 or containsAny(itemLower, { "armor", "armour", "bulletvest", "greave", "vambrace", "gorget", "cuirass", "helmet", "visor" }) or maxDefense >= 90

    local clothingType = isArmor and ("Armor." .. resolveArmorSlot(body)) or resolveNonArmorSlot(ctx, itemLower, displayCategory, body)

    local primary = "Clothing.Top"
    local tags = {}
    local evidence = 0
    if isClothingType then evidence = evidence + 0.35 end
    if body ~= "" then evidence = evidence + 0.3 end
    if displayCategory == "clothing" or displayCategory == "accessory" or displayCategory == "protectivegear" then evidence = evidence + 0.2 end
    if maxDefense > 0 then evidence = evidence + 0.1 end
    if clothingType ~= "General" then evidence = evidence + 0.1 end

    local confidence = math.min(1.0, evidence)
    if confidence < 0.45 then
        return { matched = false, confidence = confidence }
    end

    primary = "Clothing." .. clothingType

    tags[#tags + 1] = primary

    if isArmor then
        if maxDefense >= 90 then
            tags[#tags + 1] = "Clothing.Armor.Heavy"
        elseif maxDefense >= 60 then
            tags[#tags + 1] = "Clothing.Armor.Medium"
        else
            tags[#tags + 1] = "Clothing.Armor.Light"
        end
    elseif maxDefense >= 25 then
        tags[#tags + 1] = "Clothing.Protective"
    end

    if bite >= 20 then tags[#tags + 1] = "Clothing.BiteResistant" end
    if scratch >= 20 then tags[#tags + 1] = "Clothing.ScratchResistant" end
    if bullet > 0 then tags[#tags + 1] = "Clothing.BulletResistant" end
    if blunt >= 20 then tags[#tags + 1] = "Clothing.BluntResistant" end
    if (ctx.insulation or 0) > 0.1 then tags[#tags + 1] = "Clothing.Insulated" end
    if (ctx.windResistance or 0) > 0.1 then tags[#tags + 1] = "Clothing.WindResistant" end

    if containsAny(itemLower, { "police", "sheriff" }) then
        tags[#tags + 1] = "Clothing.Authority"
    elseif containsAny(itemLower, { "military", "tactical", "army", "swat" }) then
        tags[#tags + 1] = "Clothing.Tactical"
    elseif containsAny(itemLower, { "medical", "doctor", "hospital" }) then
        tags[#tags + 1] = "Clothing.Medical"
    end

    return success(confidence, primary, tags)
end

DynamicTrading.Signatures.Clothing = Signature
return Signature
