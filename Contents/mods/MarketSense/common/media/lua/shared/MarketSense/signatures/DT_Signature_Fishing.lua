require "MarketSense/DT_Core"

DynamicTrading = DynamicTrading or {}
DynamicTrading.Signatures = DynamicTrading.Signatures or {}

local Core = DynamicTrading.Core
local Signature = {}

local FISHING_DISPLAY_CATEGORIES = { ["fishing"] = true, ["fishingweapon"] = true }
local FISHING_RESOURCE_TAGS = { ["base:fishinghook"] = true, ["base:fishingline"] = true, ["base:fishingnet"] = true }
local FISHING_TOOL_TAGS = { ["base:fishingrod"] = true }

local FISHING_TOOL_ID_PATTERNS = { "fishingrod", "gaffhook" }
local FISHING_RESOURCE_ID_PATTERNS = { "fishingline", "fishinghook", "fishingnet", "bobber", "lure", "fishingtrash" }
local BAIT_RESOURCE_ID_PATTERNS = {
    "bait", "chum", "worm", "cricket", "grasshopper", "maggot", "caterpillar", "leech",
    "tadpole", "slug", "snail", "termite", "centipede", "cockroach", "pillbug", "sawflylarva",
    "millipede", "fishguts",
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
    local displayCategory = tostring(ctx.displayCategoryLower or "")
    local itemLower = tostring(ctx.idLower or "")
    local itemType = tostring(ctx.itemTypeLower or "")

    local hasFishingDisplayCategory = FISHING_DISPLAY_CATEGORIES[displayCategory] == true
    local hasFishingScriptHints = hasScriptTag(ctx, FISHING_RESOURCE_TAGS) or hasScriptTag(ctx, FISHING_TOOL_TAGS)

    if not hasFishingDisplayCategory and not hasFishingScriptHints then
        if not containsAny(itemLower, FISHING_TOOL_ID_PATTERNS)
            and not containsAny(itemLower, FISHING_RESOURCE_ID_PATTERNS)
            and not containsAny(itemLower, BAIT_RESOURCE_ID_PATTERNS) then
            return { matched = false, confidence = 0 }
        end
    end

    local isTool = displayCategory == "fishingweapon"
        or hasScriptTag(ctx, FISHING_TOOL_TAGS)
        or (string.find(itemType, "weapon", 1, true) ~= nil and containsAny(itemLower, FISHING_TOOL_ID_PATTERNS))

    local isBaitResource = containsAny(itemLower, BAIT_RESOURCE_ID_PATTERNS)
        or (displayCategory == "fishing" and containsAny(itemLower, { "lure" }))

    local isResource = hasScriptTag(ctx, FISHING_RESOURCE_TAGS)
        or (displayCategory == "fishing" and itemType ~= "base:container" and itemType ~= "base:clothing" and itemType ~= "base:literature")
        or containsAny(itemLower, FISHING_RESOURCE_ID_PATTERNS)
        or isBaitResource

    if not isTool and not isResource then
        return { matched = false, confidence = 0 }
    end

    local evidence = 0
    if hasFishingDisplayCategory then evidence = evidence + 0.35 end
    if isTool then evidence = evidence + 0.35 end
    if isBaitResource then evidence = evidence + 0.7 end
    if hasFishingScriptHints then evidence = evidence + 0.3 end
    if containsAny(itemLower, FISHING_TOOL_ID_PATTERNS) or containsAny(itemLower, FISHING_RESOURCE_ID_PATTERNS) or isBaitResource then
        evidence = evidence + 0.15
    end

    local confidence = math.min(1.0, evidence)
    if confidence < 0.4 then
        return { matched = false, confidence = confidence }
    end

    if isTool then
        return success(confidence, "Tool", "Tool.Fishing", {
            "Tool.Fishing",
        })
    end

    return success(confidence, "Resource", "Resource.Fishing", {
        "Resource.Fishing",
    })
end

DynamicTrading.Signatures.Fishing = Signature
return Signature
