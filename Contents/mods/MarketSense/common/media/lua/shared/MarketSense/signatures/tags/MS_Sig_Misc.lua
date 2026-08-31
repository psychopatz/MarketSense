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

local function containsAny(text, tokens)
    for _, token in ipairs(tokens or {}) do
        if contains(text, token) then
            return true
        end
    end
    return false
end

local function evidenceText(ctx)
    return table.concat({
        ctx.fullLower or "", ctx.idLower or "", ctx.displayNameLower or "",
        ctx.descriptionLower or "", ctx.iconLower or "",
        ctx.worldStaticModelLower or "", ctx.worldObjectSpriteLower or "",
        ctx.tooltipLower or "",
    }, " ")
end

local function result(ctx, token, confidence, source, evidence)
    return TagMapper.makeResult(token, confidence, {
        source = source,
        evidence = evidence or {
            displayCategory = ctx.displayCategoryToken or "",
            itemId = ctx.idLower or "",
        },
    })
end

function Signature.match(ctx)
    local displayCategory = ctx.displayCategoryToken or ""
    if displayCategory == "junk" or displayCategory == "hidden"
        or displayCategory == "memento" or hasTag(ctx, "ismemento") then
        return { matched = false, confidence = 0 }
    end
    -- Sharpenable household items are still tools (for example scissors and
    -- straight razors); leave them for the fallback Tool signature.
    if hasTag(ctx, "sharpenable") or hasTag(ctx, "scissors") or hasTag(ctx, "razor") then
        return { matched = false, confidence = 0 }
    end

    local text = evidenceText(ctx)
    local itemId = ctx.idLower or ""

    if displayCategory == "fishing"
        or hasTag(ctx, "fishinghook") or hasTag(ctx, "fishingline")
        or hasTag(ctx, "fishingnet") or hasTag(ctx, "fishinglure") then
        return result(ctx, "MiscFishing", 0.94, "misc_display_or_fishing_tag")
    end
    if displayCategory == "security"
        or hasTag(ctx, "buildingkey") or hasTag(ctx, "lock")
        or containsAny(itemId, { "key", "padlock", "combinationpadlock" }) then
        return result(ctx, "MiscSecurity", 0.94, "misc_security_display_or_key_evidence")
    end
    if displayCategory == "navigation"
        or containsAny(text, { "compass", "navigation" }) then
        return result(ctx, "MiscNavigation", 0.92, "misc_navigation_evidence")
    end
    if displayCategory == "firesource" or displayCategory == "lightsource"
        or hasTag(ctx, "startfire") or hasTag(ctx, "lighter")
        or hasTag(ctx, "lighterfluid") or hasTag(ctx, "isfiretinder")
        or containsAny(text, { "firestarter", "fire_tinder", "lighterfluid", "matchbox", "matches" }) then
        return result(ctx, "MiscFire", 0.95, "misc_fire_source_or_tag")
    end
    if displayCategory == "camping"
        and (hasTag(ctx, "startfire") or hasTag(ctx, "isfiretinder")) then
        return result(ctx, "MiscFire", 0.93, "misc_camping_fire_tag")
    end
    if displayCategory == "sports" or displayCategory == "instrument"
        or containsAny(text, {
            "baseball", "basketball", "bowlingpin", "football", "golfball",
            "poolball", "soccerball", "tennisball", "dart", "guitarpick",
            "tuningfork", "whistle",
        }) then
        return result(ctx, "MiscRecreation", 0.91, "misc_recreation_display_or_name")
    end
    if displayCategory == "entertainment"
        or containsAny(text, { "vhs_", "vhs", "disc_retail", "cassette" }) then
        return result(ctx, "MiscEntertainment", 0.91, "misc_entertainment_display_or_name")
    end
    if displayCategory == "trapping"
        or containsAny(itemId, { "trapbox", "trapcage", "trapcrate", "trapmouse", "trapsnare", "trapstick" }) then
        return result(ctx, "MiscTrapping", 0.93, "misc_trapping_display_or_name")
    end
    if displayCategory == "animal"
        or containsAny(itemId, { "corpse", "frog", "leash", "animal" }) then
        return result(ctx, "MiscAnimal", 0.88, "misc_animal_display_or_name")
    end
    if hasTag(ctx, "purifywater") or hasTag(ctx, "respiratorfilter")
        or hasTag(ctx, "gasmaskfilter") or hasTag(ctx, "oxygentank")
        or hasTag(ctx, "ragfilter")
        or containsAny(text, { "waterpurification", "respiratorfilter", "gasmaskfilter", "insectrepellent", "oxygen_tank", "extinguisher", "ratpoison" }) then
        return result(ctx, "MiscSafety", 0.93, "misc_safety_tag_or_name")
    end
    if displayCategory == "household" or displayCategory == "appearance"
        or containsAny(text, {
            "calculator", "clipboard", "correctionfluid", "doily", "eraser",
            "hairgel", "hairspray", "marker", "mirror", "soap", "sponge",
            "toiletbrush", "umbrella", "closedumbrella", "waybackrod",
        }) then
        return result(ctx, "MiscHousehold", 0.88, "misc_household_display_or_name")
    end
    if displayCategory == "accessory" and containsAny(text, { "respirator", "gasmask", "oxygen" }) then
        return result(ctx, "MiscSafety", 0.90, "misc_safety_accessory")
    end
    if containsAny(text, { "fishinghook", "fishingline", "fishingnet", "jiglure", "minnowlure", "bobber" }) then
        return result(ctx, "MiscFishing", 0.88, "misc_fishing_name")
    end
    if containsAny(text, { "padlock", "key_blank", "car_key", "carkey", "combinationpadlock" }) then
        return result(ctx, "MiscSecurity", 0.88, "misc_security_name")
    end
    if containsAny(text, { "waybackrod", "percedwood", "poolball", "wheel", "oxygen_tank" }) then
        return result(ctx, "MiscUtility", 0.84, "misc_utility_name")
    end

    return { matched = false, confidence = 0 }
end

MarketSense.Signatures.Misc = Signature
return Signature
