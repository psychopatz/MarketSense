require "MarketSense/DT_Core"

DynamicTrading = DynamicTrading or {}
DynamicTrading.Signatures = DynamicTrading.Signatures or {}

local Core = DynamicTrading.Core
local Signature = {}

local function success(confidence, primary, tags)
    return {
        matched = true,
        confidence = confidence,
        category = "Container",
        primary = primary,
        tags = tags,
    }
end

function Signature.match(ctx)
    local matched = (ctx.capacity or 0) > 0
        or (ctx.weightReduction or 0) > 0
        or ctx.canStoreWater
        or Core.ctxContains(ctx, {
            "bag", "backpack", "rucksack", "hikingbag", "schoolbag", "duffel",
            "toolbag", "weaponbag", "medicalbag", "satchel", "purse", "handbag",
            "sack", "sandbag", "cooler", "box", "case", "tin", "cache",
            "bottle", "flask", "canteen", "bucket", "jar", "mug", "cup",
        })

    if not matched then
        return { matched = false, confidence = 0 }
    end

    local primary = "Container.General"
    local tags = {}

    if ctx.canStoreWater or Core.ctxContains(ctx, { "bottle", "flask", "canteen", "bucket", "jar", "mug", "cup" }) then
        primary = "Container.Liquid.General"
    elseif Core.ctxContains(ctx, { "backpack", "rucksack", "hikingbag", "schoolbag" }) then
        primary = "Container.Bag.Backpack"
    elseif Core.ctxContains(ctx, { "duffel", "toolbag", "weaponbag", "medicalbag" }) then
        primary = "Container.Bag.Duffel"
    elseif Core.ctxContains(ctx, { "satchel" }) then
        primary = "Container.Bag.Satchel"
    elseif Core.ctxContains(ctx, { "purse", "handbag" }) then
        primary = "Container.Bag.Handbag"
    elseif Core.ctxContains(ctx, { "cooler" }) then
        primary = "Container.Bag.Cooler"
    elseif Core.ctxContains(ctx, { "sack", "sandbag" }) then
        primary = "Container.Bag.Sack"
    elseif Core.ctxContains(ctx, { "box", "case", "tin", "cache" }) then
        primary = "Container.Stash.Case"
    elseif (ctx.capacity or 0) > 0 or (ctx.weightReduction or 0) > 0 then
        primary = "Container.Bag.General"
    end

    tags[#tags + 1] = primary

    if (ctx.capacity or 0) >= 25 then
        tags[#tags + 1] = "Container.Capacity.High"
    elseif (ctx.capacity or 0) >= 12 then
        tags[#tags + 1] = "Container.Capacity.Medium"
    elseif (ctx.capacity or 0) >= 4 then
        tags[#tags + 1] = "Container.Capacity.Low"
    else
        tags[#tags + 1] = "Container.Capacity.Tiny"
    end

    if (ctx.weightReduction or 0) >= 80 then
        tags[#tags + 1] = "Container.WeightReduction.High"
    elseif (ctx.weightReduction or 0) >= 50 then
        tags[#tags + 1] = "Container.WeightReduction.Medium"
    elseif (ctx.weightReduction or 0) > 0 then
        tags[#tags + 1] = "Container.WeightReduction.Low"
    end

    return success(0.91, primary, tags)
end

DynamicTrading.Signatures.Container = Signature
return Signature
