require "MarketSense/DT_Core"

DynamicTrading = DynamicTrading or {}
DynamicTrading.Signatures = DynamicTrading.Signatures or {}

local Core = DynamicTrading.Core
local Signature = {}

local function success(confidence, primary, tags)
    return {
        matched = true,
        confidence = confidence,
        category = "Food",
        primary = primary,
        tags = tags,
    }
end

function Signature.match(ctx)
    local foodSignal = (ctx.hunger or 0) > 0
        or (ctx.thirst or 0) > 0
        or (ctx.calories or 0) > 0
        or ctx.isCookable
        or Core.ctxContains(ctx, {
            "food", "drink", "water", "beer", "wine", "whiskey", "vodka", "coffee",
            "tea", "soda", "juice", "canned", "tin", "meat", "fish", "fruit",
            "vegetable", "bread", "rice", "pasta", "candy", "chocolate", "salt",
            "pepper", "spice",
        })

    if not foodSignal then
        return { matched = false, confidence = 0 }
    end

    local primary = "Food.NonPerishable.General"
    local tags = {}

    if Core.ctxContains(ctx, { "beer", "wine", "whiskey", "vodka" }) then
        primary = "Food.Drink.Alcohol"
        tags[#tags + 1] = "Food.Intoxicating"
    elseif (ctx.thirst or 0) > (ctx.hunger or 0) or Core.ctxContains(ctx, { "water", "coffee", "tea", "juice", "soda", "pop" }) then
        primary = "Food.Drink.NonAlcoholic"
    elseif Core.ctxContains(ctx, { "salt", "pepper", "spice" }) then
        primary = "Food.Cooking.Spice"
    elseif Core.ctxContains(ctx, { "canned", "tin" }) then
        primary = "Food.NonPerishable.Canned"
    elseif Core.ctxContains(ctx, { "meat" }) then
        primary = "Food.Perishable.Meat"
    elseif Core.ctxContains(ctx, { "fish" }) then
        primary = "Food.Perishable.Fish"
    elseif Core.ctxContains(ctx, { "fruit" }) then
        primary = "Food.Perishable.Fruit"
    elseif Core.ctxContains(ctx, { "vegetable" }) then
        primary = "Food.Perishable.Vegetable"
    elseif (ctx.daysFresh or 0) > 0 or ctx.isCookable then
        primary = "Food.Perishable.General"
    end

    tags[#tags + 1] = primary

    local nutrition = ((ctx.hunger or 0) * 100) + ((ctx.calories or 0) * 0.01)
    if nutrition >= 25 then
        tags[#tags + 1] = "Food.HighNutrition"
    elseif nutrition >= 10 then
        tags[#tags + 1] = "Food.MediumNutrition"
    else
        tags[#tags + 1] = "Food.LowNutrition"
    end

    if (ctx.unhappy or 0) + (ctx.boredom or 0) >= 20 then
        tags[#tags + 1] = "Food.LowQuality"
    end

    return success(0.89, primary, tags)
end

DynamicTrading.Signatures.Food = Signature
return Signature
