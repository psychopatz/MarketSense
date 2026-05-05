require "MarketSense/DT_Core"

DynamicTrading = DynamicTrading or {}
DynamicTrading.Signatures = DynamicTrading.Signatures or {}

local Core = DynamicTrading.Core
local Signature = {}

local ELECTRONICS_ID_PATTERNS = {
    "radio", "walkie", "generator", "battery", "electronic", "tv", "television",
    "computer", "phone", "telephone", "camera", "flashlight", "penlight", "handtorch",
    "lightbulb", "alarm", "clock",
}
local BATTERY_PATTERNS = { "battery", "cell" }
local GENERATOR_PATTERNS = { "generator", "solar" }
local COMMUNICATION_PATTERNS = { "radio", "walkie", "phone", "cb" }
local LIGHT_COMPONENT_PATTERNS = { "lightbulb", "bulb" }
local EXCLUDED_LIGHT_ITEM_IDS = {
    ["candle"] = true, ["candlelit"] = true, ["lighter"] = true, ["lighterbbq"] = true,
    ["lighterdisposable"] = true, ["lighterfluid"] = true, ["propane_refill"] = true,
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

local function success(confidence, primary, tags)
    return {
        matched = true,
        confidence = confidence,
        category = "Electronics",
        primary = primary,
        tags = tags,
    }
end

function Signature.match(ctx)
    local itemLower = tostring(ctx.idLower or "")
    local displayCategory = tostring(ctx.displayCategoryLower or "")
    local itemTypeLower = tostring(ctx.itemTypeLower or "")
    local bodyLocation = tostring(ctx.bodyLocationLower or "")
    local isMoveable = ctx.isMoveable
    if isMoveable then
        return { matched = false, confidence = 0 }
    end
    if EXCLUDED_LIGHT_ITEM_IDS[itemLower] then
        return { matched = false, confidence = 0 }
    end
    if displayCategory == "trapping" then
        return { matched = false, confidence = 0 }
    end
    if bodyLocation ~= "" then
        return { matched = false, confidence = 0 }
    end
    if itemTypeLower == "base:container"
        or itemTypeLower == "container"
        or itemTypeLower == "base:clothing"
        or itemTypeLower == "clothing"
        or itemTypeLower == "base:alarmclockclothing"
        or itemTypeLower == "base:literature"
        or itemTypeLower == "literature" then
        return { matched = false, confidence = 0 }
    end

    local isElectronicsId = containsAny(itemLower, ELECTRONICS_ID_PATTERNS)
    local isRadioItem = displayCategory == "communications" or containsAny(itemLower, { "radio", "walkie", "hamradio" })
    local isGeneralElectronics = displayCategory == "electronics"
    local isLightSource = displayCategory == "lightsource"
        and (containsAny(itemLower, { "flashlight", "torch", "penlight", "lantern" }) or hasScriptTag(ctx, { ["base:flashlight"] = true, ["base:litlantern"] = true, ["base:unlitlantern"] = true }))
    local isLightComponent = displayCategory == "electronics" and containsAny(itemLower, LIGHT_COMPONENT_PATTERNS)

    if not (isRadioItem or isGeneralElectronics or isLightSource or isLightComponent or isElectronicsId) then
        return { matched = false, confidence = 0 }
    end

    local primary = "Electronics.Gadget.General"
    local tags = {}
    local evidence = 0
    local hasSignal = (tonumber(ctx.transmitRange) or 0) > 0 or (tonumber(ctx.micRange) or 0) > 0
    local isPortable = containsAny(itemLower, { "walkie", "phone", "camera", "flashlight", "torch", "penlight", "radio" })

    if isRadioItem then
        evidence = evidence + 0.55
        local isTwoWay = containsAny(itemLower, { "walkie", "ham" }) or hasSignal
        if containsAny(itemLower, { "tv", "television" }) then
            primary = "Electronics.Television"
            evidence = evidence + 0.15
        elseif isTwoWay then
            if containsAny(itemLower, { "walkie" }) then
                primary = "Electronics.Radio.TwoWay.Walkie"
            elseif containsAny(itemLower, { "ham", "manpack" }) or not isPortable then
                primary = "Electronics.Radio.TwoWay.Ham"
            else
                primary = "Electronics.Radio.TwoWay.Portable"
            end
            evidence = evidence + 0.25
            tags[#tags + 1] = "Electronics.Radio.TwoWay"
        else
            primary = "Electronics.Radio.Broadcast"
            evidence = evidence + 0.2
            tags[#tags + 1] = "Electronics.Radio.Broadcast"
        end
        tags[#tags + 1] = "Electronics.Communicator"
        if hasSignal then
            tags[#tags + 1] = "Electronics.Transmitter"
            evidence = evidence + 0.1
        end
    elseif isLightSource then
        evidence = evidence + 0.55
        if containsAny(itemLower, { "lantern" }) then
            primary = "Electronics.Light.Lantern"
        else
            primary = "Electronics.Light.Flashlight"
        end
        tags[#tags + 1] = "Electronics.LightSource"
        evidence = evidence + 0.2
    elseif isLightComponent then
        primary = "Electronics.Light.Component"
        evidence = evidence + 0.7
    elseif containsAny(itemLower, BATTERY_PATTERNS) then
        primary = "Electronics.Battery"
        evidence = evidence + 0.6
        tags[#tags + 1] = "Electronics.PowerSource"
    elseif isGeneralElectronics then
        evidence = evidence + 0.55
        if containsAny(itemLower, GENERATOR_PATTERNS) then
            primary = "Electronics.Generator"
            tags[#tags + 1] = "Electronics.PowerGenerator"
            evidence = evidence + 0.25
        elseif containsAny(itemLower, COMMUNICATION_PATTERNS) then
            primary = "Electronics.Gadget.Communication"
            tags[#tags + 1] = "Electronics.Communicator"
            evidence = evidence + 0.2
        else
            primary = "Electronics.Gadget.General"
            evidence = evidence + 0.1
        end
    elseif containsAny(itemLower, GENERATOR_PATTERNS) then
        primary = "Electronics.Generator"
        evidence = evidence + 0.6
        tags[#tags + 1] = "Electronics.PowerGenerator"
    else
        evidence = evidence + 0.4
    end

    if isPortable then
        tags[#tags + 1] = "Electronics.Portable"
    end

    local confidence = math.min(1.0, evidence)
    if confidence <= 0.4 then
        return { matched = false, confidence = confidence }
    end

    tags[#tags + 1] = primary
    return success(confidence, primary, tags)
end

DynamicTrading.Signatures.Electronics = Signature
return Signature
