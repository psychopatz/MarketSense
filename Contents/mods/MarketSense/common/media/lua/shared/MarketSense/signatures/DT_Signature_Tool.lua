require "MarketSense/DT_Core"

DynamicTrading = DynamicTrading or {}
DynamicTrading.Signatures = DynamicTrading.Signatures or {}

local Core = DynamicTrading.Core
local Signature = {}

local TOOL_ID_PATTERNS = {
    "tool", "hammer", "saw", "drill", "wrench", "screwdriver",
    "shovel", "rake", "hoe", "trowel", "pickaxe", "flashlight", "rope",
    "lock", "key", "crowbar",
}
local CRAFTING_TOOL_PATTERNS = { "hammer", "saw", "drill", "wrench", "screwdriver", "welder" }
local FARMING_TOOL_PATTERNS = {
    "shovel", "rake", "leafrake", "hoe", "gardenhoe", "handshovel", "handfork", "gardenfork",
    "pitchfork", "pickaxe", "scythe", "handscythe", "primitivescythe", "sickle",
}
local MEDICAL_TOOL_PATTERNS = { "tweezers", "forceps", "suture", "scalpel", "stethoscope", "tonguedepressor", "medical" }
local SURGICAL_TOOL_PATTERNS = { "scalpel", "suture", "forceps" }

local COOKWARE_TOOL_PATTERNS = {
    "bakingpan", "bakingtray", "fryingpan", "gridlepan", "griddlepan", "saucepan", "cookingpot", "roastingpan",
    "kettle", "tinopener", "canopener", "bastingbrush", "bottleopener", "cheesegrater", "grillbrush", "kitchentongs",
    "ladle", "muffintray", "ovenmitt", "pizzacutter", "skewerswooden", "spatula", "strainer", "whisk", "woodenspoon",
}

local MEDICAL_TOOL_TAGS = { ["base:removeglass"] = true, ["base:removebullet"] = true, ["base:tweezers"] = true }
local COOKWARE_SCRIPT_TAGS = {
    ["base:canopener"] = true,
    ["base:mixingutensil"] = true,
    ["base:grater"] = true,
    ["base:bottleopener"] = true,
}
local COOKWARE_WEAK_SCRIPT_TAGS = { ["base:cookable"] = true }
local COOKWARE_DISPLAY_CATEGORIES = { ["cooking"] = true, ["cookingweapon"] = true }

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

local function success(confidence, primary, tags)
    return {
        matched = true,
        confidence = confidence,
        category = "Tool",
        primary = primary,
        tags = tags,
    }
end

function Signature.match(ctx)
    local itemLower = tostring(ctx.idLower or "")
    local displayCategory = tostring(ctx.displayCategoryLower or "")
    local useDelta = tonumber(ctx.useDelta) or 0
    local conditionMax = tonumber(ctx.conditionMax) or 0
    local minDamage = tonumber(ctx.minDamage) or 0
    local maxDamage = tonumber(ctx.maxDamage) or 0

    local hasCookwareTag = hasScriptTag(ctx, COOKWARE_SCRIPT_TAGS)
    local hasWeakCookwareTag = hasScriptTag(ctx, COOKWARE_WEAK_SCRIPT_TAGS)
    local isCookwareId = containsAny(itemLower, COOKWARE_TOOL_PATTERNS)
    local hasCookingProperties = ctx.isCookable or ctx.hasPourType or ctx.hasEatType
    local isCookingDisplay = COOKWARE_DISPLAY_CATEGORIES[displayCategory] == true

    local cookwareContext = hasCookwareTag
        or hasCookingProperties
        or (isCookingDisplay and (isCookwareId or hasWeakCookwareTag))

    if cookwareContext then
        local evidence = 0
        if isCookingDisplay then evidence = evidence + (displayCategory == "cookingweapon" and 0.35 or 0.3) end
        if hasCookwareTag then evidence = evidence + 0.35 end
        if hasWeakCookwareTag and isCookingDisplay then evidence = evidence + 0.15 end
        if isCookwareId then evidence = evidence + 0.25 end
        if hasCookingProperties then evidence = evidence + 0.2 end
        if conditionMax >= 1 then evidence = evidence + 0.1 end
        if useDelta > 0 then evidence = evidence + 0.1 end

        local confidence = math.min(1.0, evidence)
        if confidence >= 0.45 then
            local tags = { "Tool.Cookware" }
            if conditionMax > 50 then
                tags[#tags + 1] = "Tool.Durable"
            elseif conditionMax > 0 and conditionMax < 15 then
                tags[#tags + 1] = "Tool.Fragile"
            end
            return success(confidence, "Tool.Cookware", tags)
        end
    end

    local isMedicalDisplay = displayCategory == "firstaid" or displayCategory == "firstaidweapon"
    local hasMedicalToolTags = hasScriptTag(ctx, MEDICAL_TOOL_TAGS)
    local isMedicalToolId = containsAny(itemLower, MEDICAL_TOOL_PATTERNS)
    local isSurgicalTool = displayCategory == "firstaidweapon" or containsAny(itemLower, SURGICAL_TOOL_PATTERNS)
    local medicalContext = displayCategory == "firstaidweapon" or hasMedicalToolTags or isMedicalToolId

    if medicalContext or isMedicalDisplay then
        local evidence = 0
        if isMedicalDisplay then evidence = evidence + (displayCategory == "firstaidweapon" and 0.45 or 0.35) end
        if hasMedicalToolTags then evidence = evidence + 0.35 end
        if isMedicalToolId then evidence = evidence + 0.2 end
        if conditionMax >= 1 then evidence = evidence + 0.1 end
        if minDamage > 0 or maxDamage > 0 then evidence = evidence + 0.2 end
        if isSurgicalTool then evidence = evidence + 0.3 end

        local confidence = math.min(1.0, evidence)
        if confidence >= 0.45 then
            local primary = isSurgicalTool and "Tool.Medical.Surgical" or "Tool.Medical"
            local tags = { primary }
            return success(confidence, primary, tags)
        end
    end

    if useDelta == 0 and conditionMax < 3 then
        return { matched = false, confidence = 0 }
    end

    local primary = "Tool.General"
    local tags = {}
    local evidence = 0

    if useDelta > 0 then evidence = evidence + 0.25 end
    if conditionMax > 3 then evidence = evidence + 0.25 end
    if containsAny(itemLower, TOOL_ID_PATTERNS) then evidence = evidence + 0.2 end

    if containsAny(itemLower, CRAFTING_TOOL_PATTERNS) then
        primary = "Tool.Crafting"
        evidence = evidence + 0.15
    elseif containsAny(itemLower, FARMING_TOOL_PATTERNS) then
        primary = "Tool.Farming"
        evidence = evidence + 0.15
    elseif containsAny(itemLower, { "fishingrod", "fishingline", "hook", "lure" }) then
        primary = "Tool.Fishing"
        evidence = evidence + 0.1
    elseif containsAny(itemLower, { "crowbar", "lock", "key" }) then
        primary = "Tool.Utility"
        evidence = evidence + 0.1
    elseif containsAny(itemLower, { "flashlight", "lens", "light" }) then
        primary = "Tool.Light"
        evidence = evidence + 0.1
    end

    local confidence = math.min(1.0, evidence)
    if confidence <= 0.35 then
        return { matched = false, confidence = confidence }
    end

    tags[#tags + 1] = primary

    if conditionMax > 50 then
        tags[#tags + 1] = "Tool.Durable"
    elseif conditionMax > 0 and conditionMax < 15 then
        tags[#tags + 1] = "Tool.Fragile"
    end

    local totalUses = useDelta > 0 and math.floor(1.0 / useDelta) or 0
    if totalUses > 100 then
        tags[#tags + 1] = "Tool.HighUse"
    elseif totalUses > 30 then
        tags[#tags + 1] = "Tool.MediumUse"
    elseif totalUses > 0 then
        tags[#tags + 1] = "Tool.LimitedUse"
    end

    return success(confidence, primary, tags)
end

DynamicTrading.Signatures.Tool = Signature
return Signature
