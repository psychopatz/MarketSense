require "MarketSense/signatures/tags/MS_TagMapper"

MarketSense = MarketSense or {}
MarketSense.Signatures = MarketSense.Signatures or {}

local Signature = {}
local TagMapper = MarketSense.TagMapper

local function hasTag(ctx, token)
    return ctx.normalizedTags and ctx.normalizedTags[token] == true
end
local function itemTypeIs(ctx, ...)
    local t = ctx.itemTypeToken or ""
    for _, v in ipairs({...}) do if t == v then return true end end
    return false
end

function Signature.match(ctx)
    if not itemTypeIs(ctx, "food", "eat", "eatsmall") and (ctx.displayCategoryToken or "") ~= "food" then
        return { matched = false, confidence = 0 }
    end
    -- Exclude non-food items
    if hasTag(ctx, "animalhead") or hasTag(ctx, "feather")
        or hasTag(ctx, "iscompostable") or hasTag(ctx, "animalbrain") then
        return { matched = false, confidence = 0 }
    end
    -- Smokable (tobacco, etc.) let Smoking sig handle it
    if hasTag(ctx, "smokable") then return { matched = false, confidence = 0 } end

    local perishable = ctx.canAge or (ctx.daysFresh or 0) > 0 or (ctx.daysRotten or 0) > 0
    local prefix = perishable and "FoodPerishable" or "FoodNonPerishable"

    if hasTag(ctx, "canbedividediinbowls") or (ctx.eatTypeLower or "") == "pot" then
        return TagMapper.makeResult(prefix .. "Dish", 0.90, { source = "food_dish" })
    end
    if hasTag(ctx, "fishmeat") then
        return TagMapper.makeResult(prefix .. "Seafood", 0.92, { source = "food_seafood" })
    end
    if hasTag(ctx, "cheese") then
        return TagMapper.makeResult(prefix .. "Dairy", 0.92, { source = "food_cheese" })
    end
    if hasTag(ctx, "preservedfood") then
        return TagMapper.makeResult("FoodPreserved", 0.90, { source = "food_preserved" })
    end
    if (ctx.lootTypeLower or "") == "cannedfood" and hasTag(ctx, "hasmetal") then
        return TagMapper.makeResult("FoodNonPerishableCanned", 0.94, { source = "food_canned" })
    end

    local eatType = ctx.eatTypeLower or ""
    if eatType == "2handbowl" or eatType == "bowl" or eatType == "plate" or eatType == "2hand" then
        return TagMapper.makeResult(prefix .. "Portion", 0.88, { source = "food_portion" })
    end
    if ctx.isSpice then
        return TagMapper.makeResult("FoodSpice", 0.88, { source = "food_spice" })
    end

    return TagMapper.makeResult(prefix, 0.80, { source = "food_generic" })
end

MarketSense.Signatures.Food = Signature
return Signature
