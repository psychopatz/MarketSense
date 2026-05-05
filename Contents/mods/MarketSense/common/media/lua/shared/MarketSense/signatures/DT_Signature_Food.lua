require "MarketSense/DT_Core"

DynamicTrading = DynamicTrading or {}
DynamicTrading.Signatures = DynamicTrading.Signatures or {}

local Core = DynamicTrading.Core
local Signature = {}

local FOOD_ID_PATTERNS = {
    "food", "meat", "fish", "fruit", "vegetable", "bread", "meal",
    "drink", "beverage", "alcohol", "beer", "wine", "juice", "coffee",
    "tea", "milk", "soda", "pop", "spice", "condiment", "seasoning",
    "dessert", "candy", "chocolate", "cereal", "soup", "stew", "snack",
    "bitters", "dough", "batter", "canned", "bouillon", "mushroom", "berry",
    "rationcan", "dentedcan", "mysterycan",
}
local ALCOHOL_ID_PATTERNS = {
    "alcohol", "ale", "beer", "brandy", "champagne", "cider", "gin",
    "lager", "liqueur", "liquer", "liquor", "mead", "port", "rum",
    "tequila", "vodka", "whiskey", "whisky", "wine", "bitters",
}
local DRINK_ID_PATTERNS = { "drink", "beverage", "juice", "coffee", "tea", "pop", "soda", "cola", "milk", "water" }
local MEAT_ID_PATTERNS = { "meat", "fish", "chicken", "pork", "beef", "bacon", "sausage", "rashers" }
local FRUIT_ID_PATTERNS = { "fruit", "apple", "banana", "orange", "berry", "avocado", "peach", "pear", "lemon", "lime" }
local VEGETABLE_ID_PATTERNS = { "vegetable", "carrot", "potato", "lettuce", "tomato", "broccoli", "cabbage", "pepper", "leek", "onion" }
local SPICE_ID_PATTERNS = { "spice", "condiment", "seasoning", "salt", "pepper", "basil", "thyme", "oregano", "rosemary", "sage", "bouillon" }
local GRAIN_ID_PATTERNS = { "bread", "grain", "cereal", "rice", "pasta", "noodle", "oat", "flour", "bun", "barley", "corn", "bagel", "baguette" }
local SWEET_ID_PATTERNS = { "candy", "chocolate", "cookie", "cake", "cupcake", "dessert", "sweet", "donut", "hardcandies", "muffin", "gummy" }
local NON_PERISHABLE_ID_PATTERNS = { "canned", "tin", "tinned", "jar", "pack", "package", "dried", "dehydrated", "powdered" }
local COOKING_ID_PATTERNS = { "dough", "batter", "mix", "soup", "stew", "chili", "bouillon", "sauce" }

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

local function isCanItem(itemLower)
    return string.sub(itemLower, -3) == "can"
        or string.find(itemLower, "canned", 1, true) ~= nil
        or string.find(itemLower, "tinned", 1, true) ~= nil
        or string.find(itemLower, "_can", 1, true) ~= nil
        or string.find(itemLower, "can_", 1, true) ~= nil
        or string.find(itemLower, "rationcan", 1, true) ~= nil
end

local function hasCookingMetadata(ctx)
    return ctx.isCookable or ctx.hasPourType or ctx.hasEatType
end

local function hasConsumptionMetadata(ctx)
    return (ctx.unhappy or 0) ~= 0
        or (ctx.boredom or 0) ~= 0
        or (ctx.stress or 0) ~= 0
end

local function isPerishable(daysFresh, daysRotten)
    return daysFresh > 0 and (daysFresh < 30 or daysRotten > 0)
end

local function classifyFoodSubtype(itemLower, ctx, isDrink, perishable)
    if isDrink or ctx.isFluidContainer then
        local fType = ctx.fluidTypeStringLower or ""
        local fCat = ctx.fluidCategory or ""
        
        if fCat == "Alcoholic" or fType:contains("beer") or fType:contains("wine") or fType:contains("alcohol") or containsAny(itemLower, ALCOHOL_ID_PATTERNS) then
            return "Drink", "Alcohol"
        elseif fType:contains("milk") then
            return "Drink", "Milk"
        elseif fType:contains("soda") or fType:contains("pop") or fType:contains("cola") then
            return "Drink", "SoftDrink"
        elseif fType:contains("juice") then
            return "Drink", "Juice"
        elseif fType:contains("coffee") then
            return "Drink", "Coffee"
        elseif fType:contains("tea") then
            return "Drink", "Tea"
        elseif fType:contains("water") or fCat == "Water" then
            return "Drink", "Water"
        end
        
        if containsAny(itemLower, ALCOHOL_ID_PATTERNS) then
            return "Drink", "Alcohol"
        end
        return "Drink", "NonAlcoholic"
    end

    if ctx.isSpice or containsAny(itemLower, SPICE_ID_PATTERNS) then
        return "Cooking", "Spice"
    end

    if isCanItem(itemLower) then
        return "NonPerishable", "Canned"
    end

    if containsAny(itemLower, MEAT_ID_PATTERNS) then
        if string.find(itemLower, "fish", 1, true) ~= nil then
            return perishable and "Perishable" or "NonPerishable", "Fish"
        end
        return perishable and "Perishable" or "NonPerishable", "Meat"
    end

    -- Snippet from CAEC: Guessing snack vs meal based on caloric density
    local weight = ctx.weight or 1
    local calories = ctx.calories or 0
    local caloricDensity = weight > 0 and (calories / weight) or 0

    if ctx.eatTypeLower == "bowl" or ctx.eatTypeLower == "plate" or ctx.eatTypeLower == "pot" then
        return perishable and "Perishable" or "NonPerishable", "Meal"
    end

    if caloricDensity > 300 and not perishable then
        return "NonPerishable", "Sweets"
    end

    if containsAny(itemLower, FRUIT_ID_PATTERNS) then
        return perishable and "Perishable" or "NonPerishable", "Fruit"
    end
    if containsAny(itemLower, VEGETABLE_ID_PATTERNS) then
        return perishable and "Perishable" or "NonPerishable", "Vegetable"
    end
    if containsAny(itemLower, SWEET_ID_PATTERNS) then
        return perishable and "Perishable" or "NonPerishable", "Sweets"
    end
    if containsAny(itemLower, GRAIN_ID_PATTERNS) then
        return perishable and "Perishable" or "NonPerishable", "Grain"
    end
    if containsAny(itemLower, NON_PERISHABLE_ID_PATTERNS) then
        return "NonPerishable", "Canned"
    end
    if hasCookingMetadata(ctx) or containsAny(itemLower, COOKING_ID_PATTERNS) then
        return "Cooking", "Ingredient"
    end
    return perishable and "Perishable" or "NonPerishable", "General"
end

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
    local itemLower = tostring(ctx.idLower or "")
    local displayCategory = tostring(ctx.displayCategoryLower or "")
    local typeValue = tostring(ctx.itemTypeLower or "")
    local bodyLocation = tostring(ctx.bodyLocationLower or "")

    if string.sub(itemLower, 1, 7) == "zeddmg_"
        or displayCategory == "zeddmg"
        or bodyLocation == "base:zeddmg"
        or bodyLocation == "base:wound"
        or bodyLocation == "base:bandage"
        or displayCategory == "firstaid"
        or displayCategory == "firstaidweapon"
        or displayCategory == "bandage" then
        return { matched = false, confidence = 0 }
    end

    if typeValue == "base:clothing"
        or typeValue == "clothing"
        or typeValue == "base:container"
        or typeValue == "container"
        or typeValue == "base:literature"
        or typeValue == "literature"
        or typeValue == "base:weapon"
        or typeValue == "weapon" then
        return { matched = false, confidence = 0 }
    end

    local hunger = tonumber(ctx.hunger) or 0
    local thirst = tonumber(ctx.thirst) or 0
    local calories = tonumber(ctx.calories) or 0
    local daysFresh = tonumber(ctx.daysFresh) or 0
    local daysRotten = tonumber(ctx.daysRotten) or 0

    local hasNutrition = calories > 0
    local hasFreshness = daysFresh > 0 or daysRotten > 0
    local isDisplayFood = displayCategory == "food"
    local isTypeFood = typeValue == "food" or typeValue == "base:food" or typeValue == "eat" or typeValue == "eatsmall"
    local isFoodInstance = ctx.isFoodInstance == true
    local foodLikeId = containsAny(itemLower, FOOD_ID_PATTERNS)

    local hasFoodSignals = hunger ~= 0
        or thirst ~= 0
        or hasNutrition
        or hasFreshness
        or hasConsumptionMetadata(ctx)
        or hasCookingMetadata(ctx)

    local hasFoodContext = isDisplayFood
        or isTypeFood
        or isFoodInstance
        or hasFoodSignals
        or (foodLikeId and (hunger ~= 0 or thirst ~= 0 or hasNutrition or hasFreshness))

    if not hasFoodContext then
        return { matched = false, confidence = 0 }
    end

    if not (isDisplayFood or isTypeFood or isFoodInstance or hasFoodSignals) then
        return { matched = false, confidence = 0 }
    end

    local isDrink = (containsAny(itemLower, DRINK_ID_PATTERNS) or containsAny(itemLower, ALCOHOL_ID_PATTERNS))
        or (thirst > 0 and hunger == 0 and calories == 0 and (isDisplayFood or isTypeFood))

    local perishable = isPerishable(daysFresh, daysRotten)
    local category, subtype = classifyFoodSubtype(itemLower, ctx, isDrink, perishable)
    local primary = "Food." .. category .. "." .. subtype
    local tags = {}
    local evidence = 0

    if isDisplayFood then evidence = evidence + 0.25 end
    if isTypeFood then evidence = evidence + 0.2 end
    if foodLikeId then evidence = evidence + 0.15 end
    if isCanItem(itemLower) then evidence = evidence + 0.2 end
    if hunger ~= 0 then evidence = evidence + (math.abs(hunger) >= 5 and 0.2 or 0.1) end
    if thirst ~= 0 then evidence = evidence + (math.abs(thirst) >= 3 and 0.2 or 0.1) end
    if isDrink then evidence = evidence + 0.15 end
    if hasNutrition then evidence = evidence + 0.15 end
    if hasFreshness then evidence = evidence + 0.1 end
    if hasCookingMetadata(ctx) then evidence = evidence + 0.1 end
    if hasConsumptionMetadata(ctx) then evidence = evidence + 0.1 end
    if category == "Drink" or category == "Cooking" or subtype ~= "General" then evidence = evidence + 0.1 end

    local confidence = math.min(1.0, evidence)
    if confidence < 0.4 then
        return { matched = false, confidence = confidence }
    end

    tags[#tags + 1] = primary
    if subtype == "Alcohol" then
        tags[#tags + 1] = "Food.Intoxicating"
    end

    local nutrition = (math.abs(hunger) * 100) + (calories * 0.01)
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

    return success(confidence, primary, tags)
end

DynamicTrading.Signatures.Food = Signature
return Signature
