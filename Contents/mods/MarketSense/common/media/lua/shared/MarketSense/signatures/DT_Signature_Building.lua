require "MarketSense/DT_Core"

DynamicTrading = DynamicTrading or {}
DynamicTrading.Signatures = DynamicTrading.Signatures or {}

local Core = DynamicTrading.Core
local Signature = {}

local function success(confidence, primary, tags)
    return {
        matched = true,
        confidence = confidence,
        category = "Building",
        primary = primary,
        tags = tags,
    }
end

function Signature.match(ctx)
    local matched = ctx.isMoveable
        or ctx.hasWorldStaticModel
        or Core.ctxContains(ctx, {
            "furniture", "household", "vehiclemaintenance", "gardening", "camping",
            "trapping", "chair", "table", "cabinet", "shelf", "bed", "mattress",
            "sink", "toilet", "shower", "pipe", "valve", "fridge", "freezer", "oven",
            "stove", "microwave", "washer", "dryer", "lamp", "light", "bulb", "switch",
            "seed", "fertilizer", "compost", "tent", "sleepingbag", "bedroll", "trap",
            "engineparts", "brake", "suspension", "muffler", "tire",
        })

    if not matched then
        return { matched = false, confidence = 0 }
    end

    local primary = "Building.Moveable"

    if Core.ctxContains(ctx, { "chair" }) then
        primary = "Building.Furniture.Chair"
    elseif Core.ctxContains(ctx, { "table" }) then
        primary = "Building.Furniture.Table"
    elseif Core.ctxContains(ctx, { "cabinet", "shelf" }) or (ctx.capacity or 0) > 0 then
        primary = "Building.Furniture.Storage"
    elseif Core.ctxContains(ctx, { "bed", "mattress" }) then
        primary = "Building.Furniture.Bed"
    elseif Core.ctxContains(ctx, { "sink", "toilet", "shower", "pipe", "valve" }) then
        primary = "Building.Fixture.Plumbing"
    elseif Core.ctxContains(ctx, { "fridge", "freezer", "oven", "stove", "microwave", "washer", "dryer" }) then
        primary = "Building.Fixture.Appliance"
    elseif Core.ctxContains(ctx, { "lamp", "light", "bulb", "switch" }) then
        primary = "Building.Fixture.Electrical"
    elseif Core.ctxContains(ctx, { "seed" }) then
        primary = "Building.Garden.Seed"
    elseif Core.ctxContains(ctx, { "fertilizer", "compost", "gardening" }) then
        primary = "Building.Garden"
    elseif Core.ctxContains(ctx, { "tent", "sleepingbag", "bedroll" }) then
        primary = "Building.Survival"
    elseif Core.ctxContains(ctx, { "trap", "trapping" }) then
        primary = "Building.Survival.Trap"
    elseif Core.ctxContains(ctx, { "engineparts", "brake", "suspension", "muffler", "tire" }) then
        primary = "Building.Vehicle"
    elseif not ctx.isMoveable then
        primary = "Building.Furniture.Decor"
    end

    return success(0.80, primary, {
        primary,
    })
end

DynamicTrading.Signatures.Building = Signature
return Signature
