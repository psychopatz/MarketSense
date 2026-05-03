require "MarketSense/DT_Core"

DynamicTrading = DynamicTrading or {}
DynamicTrading.Signatures = DynamicTrading.Signatures or {}

local Core = DynamicTrading.Core
local Signature = {}

local MEDICAL_SUPPLY_ID_PATTERNS = {
    "bandage", "bandaid", "pills", "antibiotics", "disinfectant",
    "cotton", "coldpack", "cataplasm", "comfrey", "plantain",
    "garlic", "mallow", "ginseng", "blackage", "alcoholwipes",
    "alcoholbandage", "splint",
}
local DRUG_ID_PATTERNS = {
    "cigarette", "cigar", "cigarillo", "tobacco", "smokingpipe_tobacco", "canpipe_tobacco",
}
local PILLS_PATTERNS = { "pills", "antibiotics", "tablet", "capsule" }
local VITAMIN_PATTERNS = { "vitamin" }
local BOTANICAL_PATTERNS = { "comfrey", "plantain", "garlic", "mallow", "ginseng", "blackage", "cataplasm" }
local MEDICAL_TOOL_PATTERNS = { "tweezers", "forceps", "suture", "scalpel", "stethoscope", "tonguedepressor" }

local MEDICAL_SUPPLY_TAGS = {
    ["base:consumable"] = true,
    ["base:comfrey"] = true,
    ["base:plantain"] = true,
    ["base:wildgarlic"] = true,
    ["base:commonmallow"] = true,
    ["base:herbaltea"] = true,
}
local DRUG_TAGS = {
    ["base:smokable"] = true,
    ["base:chewingtobacco"] = true,
    ["base:tobacco"] = true,
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

local function success(confidence, category, primary, tags)
    return {
        matched = true,
        confidence = confidence,
        category = category,
        primary = primary,
        tags = tags,
    }
end

function Signature.match(ctx)
    local itemLower = tostring(ctx.idLower or "")
    local displayCategory = tostring(ctx.displayCategoryLower or "")
    local typeValue = tostring(ctx.itemTypeLower or "")
    local bandagePower = tonumber(ctx.bandagePower) or 0
    local reduceInfection = tonumber(ctx.reduceInfectionPower) or 0

    local isFirstAid = displayCategory == "firstaid" or displayCategory == "bandage"
    local isMedicalFlag = Core.ctxContains(ctx, { "medical" })
    local isContainer = typeValue == "base:container" or string.sub(itemLower, 1, 10) == "firstaidkit"
    local isClothing = (ctx.bodyLocationLower or "") ~= ""
    local isMedicalTool = displayCategory == "firstaidweapon"
        or containsAny(itemLower, MEDICAL_TOOL_PATTERNS)
        or hasScriptTag(ctx, { ["base:removeglass"] = true, ["base:removebullet"] = true, ["base:tweezers"] = true })

    if isContainer or isClothing or isMedicalTool or string.sub(itemLower, 1, 8) == "bandage_" then
        return { matched = false, confidence = 0 }
    end

    local hasDrugTags = hasScriptTag(ctx, DRUG_TAGS)
    local isDrugId = containsAny(itemLower, DRUG_ID_PATTERNS)
    local isNicotineDrug = hasDrugTags or isDrugId

    local looksMedical = isFirstAid
        or isMedicalFlag
        or containsAny(itemLower, MEDICAL_SUPPLY_ID_PATTERNS)
        or isNicotineDrug
        or bandagePower > 0
        or reduceInfection > 0

    if not looksMedical then
        return { matched = false, confidence = 0 }
    end

    local evidence = 0
    if isFirstAid then evidence = evidence + 0.35 end
    if isMedicalFlag then evidence = evidence + 0.35 end
    if containsAny(itemLower, MEDICAL_SUPPLY_ID_PATTERNS) then evidence = evidence + 0.2 end
    if isNicotineDrug then evidence = evidence + 0.45 end
    if bandagePower > 0 then evidence = evidence + 0.25 end
    if reduceInfection > 0 then evidence = evidence + 0.3 end
    if hasScriptTag(ctx, MEDICAL_SUPPLY_TAGS) then evidence = evidence + 0.1 end

    local confidence = math.min(1.0, evidence)
    if confidence < 0.45 then
        return { matched = false, confidence = confidence }
    end

    if isNicotineDrug then
        return success(confidence, "Medical", "Medical.General.Drug", {
            "Medical.General.Drug",
            "Medical.Consumable",
        })
    end

    if containsAny(itemLower, VITAMIN_PATTERNS) then
        return success(confidence, "Medical", "Medical.General.Vitamin", {
            "Medical.General.Vitamin",
            "Medical.Consumable",
        })
    end

    if containsAny(itemLower, PILLS_PATTERNS) then
        return success(confidence, "Medical", "Medical.General.Pills", {
            "Medical.General.Pills",
            "Medical.Consumable",
        })
    end

    if containsAny(itemLower, BOTANICAL_PATTERNS)
        or hasScriptTag(ctx, {
            ["base:comfrey"] = true,
            ["base:plantain"] = true,
            ["base:wildgarlic"] = true,
            ["base:commonmallow"] = true,
            ["base:herbaltea"] = true,
        }) then
        return success(confidence, "Medical", "Medical.Healthcare.Botanical", {
            "Medical.Healthcare.Botanical",
            "Medical.Consumable",
        })
    end

    return success(confidence, "Medical", "Medical.Healthcare", {
        "Medical.Healthcare",
        "Medical.Consumable",
    })
end

DynamicTrading.Signatures.Medical = Signature
return Signature
