require "MarketSense/DT_Core"

DynamicTrading = DynamicTrading or {}
DynamicTrading.Signatures = DynamicTrading.Signatures or {}

local Core = DynamicTrading.Core
local Signature = {}

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
    local matched = Core.ctxContains(ctx, {
        "electronics", "communications", "lightsource", "radio", "walkie", "hamradio",
        "generator", "battery", "tv", "television", "phone", "camera", "flashlight",
        "torch", "penlight", "lightbulb", "lantern",
    })

    if not matched then
        return { matched = false, confidence = 0 }
    end

    local primary = "Electronics.Gadget.General"
    local tags = {}

    if Core.ctxContains(ctx, { "generator" }) then
        primary = "Electronics.Generator"
        tags[#tags + 1] = "Electronics.PowerGenerator"
    elseif Core.ctxContains(ctx, { "battery" }) then
        primary = "Electronics.Battery"
        tags[#tags + 1] = "Electronics.PowerSource"
    elseif Core.ctxContains(ctx, { "radio", "walkie", "hamradio" }) then
        if Core.ctxContains(ctx, { "walkie", "hamradio" }) then
            primary = "Electronics.Radio.TwoWay"
            tags[#tags + 1] = "Electronics.Transmitter"
        else
            primary = "Electronics.Radio.Broadcast"
        end
        tags[#tags + 1] = "Electronics.Communicator"
    elseif Core.ctxContains(ctx, { "flashlight", "torch", "penlight", "lightbulb", "lantern" }) then
        primary = "Electronics.Light.Flashlight"
        tags[#tags + 1] = "Electronics.LightSource"
    elseif Core.ctxContains(ctx, { "tv", "television" }) then
        primary = "Electronics.Television"
    end

    tags[#tags + 1] = primary

    if Core.ctxContains(ctx, { "radio", "walkie", "phone", "camera", "flashlight", "torch" }) then
        tags[#tags + 1] = "Electronics.Portable"
    end

    return success(0.90, primary, tags)
end

DynamicTrading.Signatures.Electronics = Signature
return Signature
