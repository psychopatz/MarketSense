require "MarketSense/DT_Core"

DynamicTrading = DynamicTrading or {}
DynamicTrading.Signatures = DynamicTrading.Signatures or {}

local Core = DynamicTrading.Core
local Signature = {}

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
    local matched, token = Core.ctxContains(ctx, {
        "fishing", "fishingrod", "fishingline", "fishinghook", "fishingnet",
        "bait", "worm", "lure", "chum", "rod", "hook", "net",
    })

    if not matched then
        return { matched = false, confidence = 0 }
    end

    if token == "bait" or token == "worm" or token == "lure" or token == "chum" then
        return success(0.96, "Resource", "Resource.Fishing", {
            "Resource.Fishing",
        })
    end

    return success(0.98, "Tool", "Tool.Fishing", {
        "Tool.Fishing",
    })
end

DynamicTrading.Signatures.Fishing = Signature
return Signature
