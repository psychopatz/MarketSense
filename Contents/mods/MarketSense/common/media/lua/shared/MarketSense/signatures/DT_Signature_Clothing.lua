require "MarketSense/DT_Core"

DynamicTrading = DynamicTrading or {}
DynamicTrading.Signatures = DynamicTrading.Signatures or {}

local Core = DynamicTrading.Core
local Signature = {}

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
    local armorScore = (ctx.biteDefense or 0) + (ctx.scratchDefense or 0) + (ctx.bulletDefense or 0)
    local matched = armorScore > 0 or Core.ctxContains(ctx, {
        "clothing", "accessory", "protectivegear", "shirt", "pants", "jacket",
        "coat", "hat", "helmet", "mask", "glove", "boot", "shoe", "ring",
        "necklace", "watch", "armor", "armour", "vest",
    })

    if not matched then
        return { matched = false, confidence = 0 }
    end

    local primary = "Clothing.Top"
    local tags = {}
    local body = ctx.bodyLocationLower or ""

    if string.find(body, "head", 1, true) or Core.ctxContains(ctx, { "hat", "helmet" }) then
        primary = armorScore > 0 and "Clothing.Armor.Head" or "Clothing.Head"
    elseif string.find(body, "face", 1, true) or Core.ctxContains(ctx, { "mask" }) then
        primary = armorScore > 0 and "Clothing.Armor.Face" or "Clothing.Face"
    elseif string.find(body, "hand", 1, true) or Core.ctxContains(ctx, { "glove" }) then
        primary = "Clothing.Hands"
    elseif string.find(body, "foot", 1, true) or Core.ctxContains(ctx, { "boot", "shoe" }) then
        primary = "Clothing.Feet"
    elseif string.find(body, "leg", 1, true) or Core.ctxContains(ctx, { "pants" }) then
        primary = "Clothing.Bottom"
    elseif Core.ctxContains(ctx, { "coat", "jacket", "outerwear" }) then
        primary = armorScore > 0 and "Clothing.Armor.Torso" or "Clothing.Outerwear"
    elseif Core.ctxContains(ctx, { "ring", "necklace" }) then
        primary = "Clothing.Accessory.Jewelry"
    elseif Core.ctxContains(ctx, { "watch" }) then
        primary = "Clothing.Accessory.Wrist.Watch"
    elseif armorScore > 0 or Core.ctxContains(ctx, { "vest", "armor", "armour" }) then
        primary = "Clothing.Armor.Torso"
    end

    tags[#tags + 1] = primary

    if armorScore > 0 then
        if armorScore >= 30 then
            tags[#tags + 1] = "Clothing.Armor.Heavy"
        elseif armorScore >= 15 then
            tags[#tags + 1] = "Clothing.Armor.Medium"
        else
            tags[#tags + 1] = "Clothing.Armor.Light"
        end
    end
    if (ctx.biteDefense or 0) > 0 then tags[#tags + 1] = "Clothing.BiteResistant" end
    if (ctx.scratchDefense or 0) > 0 then tags[#tags + 1] = "Clothing.ScratchResistant" end
    if (ctx.bulletDefense or 0) > 0 then tags[#tags + 1] = "Clothing.BulletResistant" end
    if (ctx.insulation or 0) > 0.1 then tags[#tags + 1] = "Clothing.Insulated" end
    if (ctx.windResistance or 0) > 0.1 then tags[#tags + 1] = "Clothing.WindResistant" end

    return success(0.87, primary, tags)
end

DynamicTrading.Signatures.Clothing = Signature
return Signature
