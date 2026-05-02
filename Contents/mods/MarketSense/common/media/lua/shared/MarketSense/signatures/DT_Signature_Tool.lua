require "MarketSense/DT_Core"

DynamicTrading = DynamicTrading or {}
DynamicTrading.Signatures = DynamicTrading.Signatures or {}

local Core = DynamicTrading.Core
local Signature = {}

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
    local toolSignal = (ctx.conditionMax or 0) > 0
        or (ctx.useDelta or 0) > 0
        or Core.ctxContains(ctx, {
            "tool", "cooking", "cookingweapon", "hammer", "saw", "drill", "wrench",
            "screwdriver", "shovel", "rake", "hoe", "trowel", "pickaxe", "pan",
            "pot", "kettle", "opener", "spatula", "whisk", "crowbar", "lock", "key",
            "scalpel", "suture", "tweezers", "forceps",
        })

    if not toolSignal then
        return { matched = false, confidence = 0 }
    end

    local primary = "Tool.General"
    local tags = {}

    if Core.ctxContains(ctx, { "hammer", "saw", "drill", "wrench", "screwdriver" }) then
        primary = "Tool.Crafting"
    elseif Core.ctxContains(ctx, { "shovel", "rake", "hoe", "trowel", "pickaxe" }) then
        primary = "Tool.Farming"
    elseif Core.ctxContains(ctx, { "fishingrod", "fishingline", "hook", "lure" }) then
        primary = "Tool.Fishing"
    elseif Core.ctxContains(ctx, { "scalpel", "suture", "tweezers", "forceps" }) then
        primary = "Tool.Medical.Surgical"
    elseif Core.ctxContains(ctx, { "bandage", "medical", "pill", "antibiotic" }) then
        primary = "Tool.Medical"
    elseif Core.ctxContains(ctx, { "pan", "pot", "kettle", "opener", "spatula", "whisk" }) then
        primary = "Tool.Cookware"
    elseif Core.ctxContains(ctx, { "crowbar", "lock", "key" }) then
        primary = "Tool.Utility"
    end

    tags[#tags + 1] = primary

    if (ctx.conditionMax or 0) >= 12 then
        tags[#tags + 1] = "Tool.Durable"
    elseif (ctx.conditionMax or 0) <= 3 and (ctx.conditionMax or 0) > 0 then
        tags[#tags + 1] = "Tool.Fragile"
    end

    if (ctx.useDelta or 0) > 0.20 then
        tags[#tags + 1] = "Tool.HighUse"
    elseif (ctx.useDelta or 0) > 0.05 then
        tags[#tags + 1] = "Tool.MediumUse"
    elseif (ctx.useDelta or 0) > 0 then
        tags[#tags + 1] = "Tool.LimitedUse"
    end

    return success(0.82, primary, tags)
end

DynamicTrading.Signatures.Tool = Signature
return Signature
