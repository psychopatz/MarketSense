require "MarketSense/signatures/tags/MS_TagMapper"

MarketSense = MarketSense or {}
MarketSense.Signatures = MarketSense.Signatures or {}

local Signature = {}
local TagMapper = MarketSense.TagMapper

local FOOD_TYPE_MAP = {
    animalfeed = "Livestock",
    bacon = "Meat",
    bakingfat = "Baking",
    bean = "Staple",
    beans = "Staple",
    beef = "Meat",
    berries = "Fruits",
    berry = "Fruits",
    bread = "Bread",
    candy = "Candy",
    catfood = "PetFood",
    cheese = "Cheese",
    chocolate = "Candy",
    citrus = "Fruits",
    cocoa = "NoExplicit",
    coffee = "Coffee",
    dairy = "Cheese",
    dogfood = "PetFood",
    dressing = "NoExplicit",
    egg = "Egg",
    fish = "Seafood",
    fruit = "Fruits",
    fruits = "Fruits",
    game = "Meat",
    garnish = "NoExplicit",
    greens = "Vegetables",
    herb = "Herb",
    herbal = "Herb",
    hotpepper = "HotPepper",
    insect = "Insect",
    lobster = "Seafood",
    meat = "Meat",
    meats = "Meat",
    mushroom = "Mushroom",
    noexplicit = "NoExplicit",
    nut = "Nut",
    oil = "Baking",
    pasta = "Staple",
    pepper = "HotPepper",
    pork = "Meat",
    poultry = "Meat",
    poulty = "Meat",
    preserved = "Preserved",
    rice = "Staple",
    roe = "Seafood",
    salt = "Spice",
    sauce = "NoExplicit",
    sausage = "Meat",
    seafood = "Seafood",
    seed = "Seed",
    snack = "Snack",
    soup = "Portion",
    spice = "Spice",
    spread = "NoExplicit",
    stock = "Stock",
    sugar = "Sugar",
    tea = "Tea",
    thickener = "Baking",
    vegetable = "Vegetables",
    vegetables = "Vegetables",
    venison = "Meat",

    beer = "Skip",
    champagne = "Skip",
    juice = "Skip",
    liquor = "Skip",
    milk = "Skip",
    softdrink = "Skip",
    wine = "Skip",
}

local PERISHABLE_VARIANTS = {
    Baking = true, Bread = true, Candy = true, Cheese = true, Dairy = true,
    Dish = true, Fruits = true, Meal = true, Meat = true, Portion = true,
    Seafood = true, Snack = true, Vegetables = true,
}

local NONPERISHABLE_VARIANTS = {
    Baking = true, Bread = true, Candy = true, Canned = true, Cheese = true,
    Dairy = true, Dish = true, Fruits = true, Meat = true, Portion = true,
    Seafood = true, Snack = true, Vegetables = true,
}

local function push(list, value)
    if value == nil or value == "" then
        return
    end
    list[#list + 1] = tostring(value)
end

local function cloneList(list)
    local result = {}
    for _, value in ipairs(list or {}) do
        result[#result + 1] = value
    end
    return result
end

local function hasTag(ctx, token)
    return ctx.normalizedTags and ctx.normalizedTags[token] == true
end

local function hasTagAlias(ctx, token)
    return hasTag(ctx, token) or hasTag(ctx, "base" .. token)
end

local function itemTypeIs(ctx, ...)
    local itemType = ctx.itemTypeToken or ""
    for _, token in ipairs({...}) do
        if itemType == token then
            return true
        end
    end
    return false
end

local function contains(text, token)
    return string.find(tostring(text or ""), token, 1, true) ~= nil
end

local function containsAny(text, tokens)
    for _, token in ipairs(tokens or {}) do
        if contains(text, token) then
            return true
        end
    end
    return false
end

local function detail(stage, source, extra)
    local details = {
        stage = stage,
        source = source,
    }
    for key, value in pairs(extra or {}) do
        details[key] = value
    end
    return details
end

local function makeResult(token, confidence, stage, source, extra)
    return TagMapper.makeResult(token, confidence, detail(stage, source, extra))
end

local function normalizeFoodType(ctx)
    local token = ctx.foodTypeToken or ""
    if token == "" then return nil end
    if string.sub(token, 1, 8) == "foodtype" then
        token = string.sub(token, 9)
    end
    return FOOD_TYPE_MAP[token] or token
end

local function hasAnyFoodTag(ctx)
    return hasTagAlias(ctx, "preservedfood")
        or hasTagAlias(ctx, "fishmeat")
        or hasTagAlias(ctx, "cheese")
        or hasTagAlias(ctx, "meat")
        or hasTagAlias(ctx, "animalmeat")
        or hasTagAlias(ctx, "fruit")
        or hasTagAlias(ctx, "fruits")
        or hasTagAlias(ctx, "vegetable")
        or hasTagAlias(ctx, "vegetables")
        or hasTagAlias(ctx, "candy")
        or hasTagAlias(ctx, "sweets")
        or hasTagAlias(ctx, "baking")
        or hasTagAlias(ctx, "flour")
        or hasTagAlias(ctx, "salt")
        or hasTagAlias(ctx, "spice")
        or hasTagAlias(ctx, "minoringredient")
end

local function hasPackagingEvidence(ctx)
    local text = table.concat({
        ctx.idLower or "",
        ctx.displayNameLower or "",
        ctx.iconLower or "",
        ctx.worldStaticModelLower or "",
        ctx.worldObjectSpriteLower or "",
        ctx.replaceOnUseLower or "",
        ctx.replaceOnCookedLower or "",
        ctx.onCookedLower or "",
        ctx.doubleClickRecipeLower or "",
    }, " ")

    return ctx.isCannedFood == true
        or ctx.isPackaged == true
        or hasTagAlias(ctx, "preservedfood")
        or hasTagAlias(ctx, "hasmetal")
        or (ctx.lootTypeLower or "") == "cannedfood"
        or contains(ctx.onCookedLower or "", "cannedfood")
        or containsAny(ctx.replaceOnUseLower or "", { "tincanempty", "emptyjar" })
        or containsAny(ctx.doubleClickRecipeLower or "", {
            "openboxofcannedfood",
            "opencannedfood",
            "openwaterrationcan",
        })
        or containsAny(text, { "canned", "jar", "rationcan", "tincan", "canopen" })
end

local function hasIdentityEvidence(ctx)
    return ctx.isFoodInstance == true
        or itemTypeIs(ctx, "food", "eat", "eatsmall")
        or (ctx.displayCategoryToken or "") == "food"
        or (ctx.lootTypeLower or "") == "food"
        or (ctx.lootTypeLower or "") == "cannedfood"
        or (ctx.foodTypeToken or "") ~= ""
end

local function hasNutritionEvidence(ctx)
    return ctx.hasFoodNutritionEvidence == true
end

local function hasSpoilageEvidence(ctx)
    return ctx.hasFoodSpoilageEvidence == true
end

local function hasRecipeEvidence(ctx)
    return ctx.hasFoodRecipeEvidence == true
end

local function buildAdmission(ctx)
    local vetoHits = {}
    local signalHits = {}

    if ctx.isFluidContainer == true then
        push(vetoHits, "fluid_container")
    end
    if hasTagAlias(ctx, "iscompostable") then
        push(vetoHits, "compostable")
    end
    if ctx.isDung == true then
        push(vetoHits, "is_dung")
    end
    if hasTagAlias(ctx, "animalhead") then
        push(vetoHits, "animal_head")
    end
    if hasTagAlias(ctx, "animalbrain") then
        push(vetoHits, "animal_brain")
    end
    if hasTagAlias(ctx, "feather") then
        push(vetoHits, "feather")
    end
    if hasTagAlias(ctx, "smokable") then
        push(vetoHits, "smokable")
    end
    if (ctx.displayCategoryToken or "") == "junk" then
        push(vetoHits, "display_junk")
    end
    if (ctx.displayCategoryToken or "") == "explosives" or (ctx.lootTypeLower or "") == "weapon" then
        push(vetoHits, "weapon_like")
    end
    if ctx.isDrainable == true and not ctx.isFoodInstance and not hasPackagingEvidence(ctx) then
        push(vetoHits, "drainable_non_food")
    end
    if (ctx.displayCategoryToken or "") == "medical" or (ctx.displayCategoryToken or "") == "firstaid"
        or (ctx.lootTypeLower or "") == "medical" then
        push(vetoHits, "medical_like")
    end
    if (ctx.displayCategoryToken or "") == "drugs"
        and ctx.isCantEat == true
        and not hasNutritionEvidence(ctx)
        and not hasRecipeEvidence(ctx) then
        push(vetoHits, "drug_non_edible")
    end

    if ctx.isFoodInstance == true then
        push(signalHits, "food_instance")
    end
    if itemTypeIs(ctx, "food", "eat", "eatsmall") then
        push(signalHits, "food_item_type")
    end
    if (ctx.displayCategoryToken or "") == "food" then
        push(signalHits, "display_food")
    end
    if (ctx.foodTypeToken or "") ~= "" then
        push(signalHits, "food_type")
    end
    if hasNutritionEvidence(ctx) then
        push(signalHits, "nutrition")
    end
    if hasSpoilageEvidence(ctx) then
        push(signalHits, "finite_spoilage")
    end
    if hasRecipeEvidence(ctx) then
        push(signalHits, "recipe")
    end
    if hasPackagingEvidence(ctx) then
        push(signalHits, "packaging")
    end
    if hasAnyFoodTag(ctx) then
        push(signalHits, "food_tag")
    end

    local accepted = false
    if #vetoHits == 0 then
        local hasContentEvidence = hasNutritionEvidence(ctx)
            or hasSpoilageEvidence(ctx)
            or hasRecipeEvidence(ctx)
            or hasPackagingEvidence(ctx)
            or hasAnyFoodTag(ctx)
            or (ctx.foodTypeToken or "") ~= ""
            or (ctx.eatTypeLower or "") ~= ""

        if hasPackagingEvidence(ctx)
            and ((ctx.displayCategoryToken or "") == "food"
                or (ctx.lootTypeLower or "") == "cannedfood"
                or ctx.isFoodInstance == true
                or hasNutritionEvidence(ctx)
                or hasAnyFoodTag(ctx)) then
            accepted = true
        elseif hasIdentityEvidence(ctx) and hasContentEvidence then
            accepted = true
        elseif ctx.isFoodInstance == true and hasContentEvidence then
            accepted = true
        end
    end

    return {
        accepted = accepted,
        reason = accepted and "admitted" or (#vetoHits > 0 and "vetoed" or "no_food_evidence"),
        vetoHits = vetoHits,
        signalHits = signalHits,
    }
end

local function admissionDetails(admission)
    return {
        admissionAccepted = admission.accepted == true,
        admissionReason = admission.reason or "",
        admissionVetoHits = cloneList(admission.vetoHits),
        admissionSignalHits = cloneList(admission.signalHits),
    }
end

local function perishablePrefix(ctx)
    local perishable = ctx.canAge == true
        or (tonumber(ctx.foodDaysFresh) or 0) > 0
        or (tonumber(ctx.foodDaysRotten) or 0) > 0
    return perishable and "FoodPerishable" or "FoodNonPerishable"
end

local function makeFoodResult(prefix, suffix, confidence, stage, source, admission, extra)
    if suffix == nil or suffix == "" then
        return nil
    end

    local details = admissionDetails(admission)
    for key, value in pairs(extra or {}) do
        details[key] = value
    end

    if suffix == "Skip" then
        return { matched = false, confidence = 0 }
    end
    if suffix == "Canned" then
        return makeResult("FoodNonPerishableCanned", confidence, stage, source, details)
    end
    if suffix == "Preserved" then
        return makeResult("FoodPreserved", confidence, stage, source, details)
    end
    if prefix == "FoodPerishable" and PERISHABLE_VARIANTS[suffix] then
        return makeResult(prefix .. suffix, confidence, stage, source, details)
    end
    if prefix == "FoodNonPerishable" and NONPERISHABLE_VARIANTS[suffix] then
        return makeResult(prefix .. suffix, confidence, stage, source, details)
    end
    return makeResult("Food" .. suffix, confidence, stage, source, details)
end

local function isCannedOrJarred(ctx)
    local text = table.concat({
        ctx.idLower or "",
        ctx.displayNameLower or "",
        ctx.iconLower or "",
        ctx.worldStaticModelLower or "",
        ctx.worldObjectSpriteLower or "",
        ctx.replaceOnUseLower or "",
        ctx.replaceOnCookedLower or "",
        ctx.onCookedLower or "",
        ctx.doubleClickRecipeLower or "",
        ctx.evolvedRecipeNameLower or "",
    }, " ")
    local replaceOnUse = ctx.replaceOnUseLower or ""

    if not hasPackagingEvidence(ctx) then
        return false
    end

    return containsAny(replaceOnUse, { "tincanempty", "emptyjar" })
        or containsAny(text, { "canned", "jar", "rationcan", "tincan", "canopen" })
        or (ctx.lootTypeLower or "") == "cannedfood"
        or contains(ctx.onCookedLower or "", "cannedfood")
end

local function packageStage(ctx, admission)
    local doubleClickRecipe = ctx.doubleClickRecipeLower or ""
    local onCooked = ctx.onCookedLower or ""
    local replaceOnUse = ctx.replaceOnUseLower or ""

    if contains(doubleClickRecipe, "openboxofcannedfood") then
        return makeResult("FoodNonPerishableBoxed", 0.97, "package", "food_box_recipe", admissionDetails(admission))
    end
    if contains(doubleClickRecipe, "openboxofwine") or contains(doubleClickRecipe, "openpackofbeer") then
        return makeResult("BeverageBox", 0.96, "package", "beverage_box_recipe", admissionDetails(admission))
    end
    if contains(doubleClickRecipe, "opencannedfood") or contains(doubleClickRecipe, "openwaterrationcan") then
        return makeResult("FoodNonPerishableCanned", 0.97, "package", "food_can_open_recipe", admissionDetails(admission))
    end
    if isCannedOrJarred(ctx) then
        return makeResult("FoodNonPerishableCanned", 0.96, "package", "food_canned_or_jarred_fields", admissionDetails(admission))
    end
    if hasTagAlias(ctx, "preservedfood") and hasTagAlias(ctx, "hasmetal")
        and (contains(onCooked, "cannedfood") or contains(replaceOnUse, "tincanempty")) then
        return makeResult("FoodNonPerishableCanned", 0.95, "package", "food_preserved_metal", admissionDetails(admission))
    end
    return nil
end

local function exactStage(ctx, prefix, admission)
    local eatType = ctx.eatTypeLower or ""
    local foodType = normalizeFoodType(ctx)

    if hasTagAlias(ctx, "canbedividedinbowls") or hasTagAlias(ctx, "canbedividediinbowls") or eatType == "pot" then
        return makeResult(prefix .. "Dish", 0.93, "exact", "food_dish", admissionDetails(admission))
    end
    if hasTagAlias(ctx, "fishmeat") then
        return makeResult(prefix .. "Seafood", 0.94, "exact", "food_seafood_tag", admissionDetails(admission))
    end
    if hasTagAlias(ctx, "cheese") then
        return makeResult(prefix .. "Cheese", 0.93, "exact", "food_cheese_tag", admissionDetails(admission))
    end
    if hasTagAlias(ctx, "meat") or hasTagAlias(ctx, "animalmeat") then
        return makeResult(prefix .. "Meat", 0.93, "exact", "food_meat_tag", admissionDetails(admission))
    end
    if hasTagAlias(ctx, "fruit") or hasTagAlias(ctx, "fruits") then
        return makeResult(prefix .. "Fruits", 0.92, "exact", "food_fruits_tag", admissionDetails(admission))
    end
    if hasTagAlias(ctx, "vegetable") or hasTagAlias(ctx, "vegetables") then
        return makeResult(prefix .. "Vegetables", 0.92, "exact", "food_vegetables_tag", admissionDetails(admission))
    end
    if hasTagAlias(ctx, "candy") or hasTagAlias(ctx, "sweets") then
        return makeResult(prefix .. "Candy", 0.91, "exact", "food_candy_tag", admissionDetails(admission))
    end
    if hasTagAlias(ctx, "baking") or hasTagAlias(ctx, "flour") then
        return makeResult(prefix .. "Baking", 0.91, "exact", "food_baking_tag", admissionDetails(admission))
    end
    if ctx.isSpice == true or hasTagAlias(ctx, "salt") or hasTagAlias(ctx, "spice") then
        return makeResult("FoodSpice", 0.91, "exact", "food_spice_fields", admissionDetails(admission))
    end
    if foodType then
        return makeFoodResult(prefix, foodType, 0.90, "exact", "food_type", admission, {
            foodType = foodType,
        })
    end
    return nil
end

local function recipeStage(ctx)
    local recipe = ctx.evolvedRecipeLower or ""
    local recipeName = ctx.evolvedRecipeNameLower or ""
    local sound = ctx.customEatSoundLower or ""
    local calories = tonumber(ctx.calories) or 0
    local proteins = tonumber(ctx.proteins) or 0
    local lipids = tonumber(ctx.lipids) or 0
    local thirst = tonumber(ctx.thirst) or 0

    if hasTagAlias(ctx, "fishmeat")
        or ((ctx.isFishingLure or contains(recipe, "addbaittochum"))
            and (ctx.isDangerousUncooked or contains(recipeName, "fish") or containsAny(ctx.idLower or "", { "fish", "roe" }))) then
        return "Seafood", "food_recipe_seafood"
    end
    if contains(recipe, "fruitsalad") or contains(recipe, "piesweet")
        or contains(sound, "eatingfruit")
        or containsAny(recipeName, { "fruit", "apple", "peach", "pineapple", "berry" }) then
        return "Fruits", "food_recipe_fruits"
    end
    if containsAny(recipe, { "stir fry", "stirfry", "salad", "soup", "stew" })
        and calories <= 180 and proteins <= 8 and lipids <= 8
        and (thirst > 0 or containsAny(recipeName, { "carrot", "tomato", "corn", "pea", "potato", "vegetable" })) then
        return "Vegetables", "food_recipe_vegetables"
    end
    if containsAny(recipeName, { "sardine", "fish", "roe" }) then
        return "Seafood", "food_recipe_seafood_name"
    end
    if containsAny(recipeName, { "beef", "meat", "pork", "chicken" })
        or (proteins >= 12 and calories >= 120 and not contains(recipe, "fruitsalad")) then
        return "Meat", "food_recipe_meat"
    end
    if containsAny(recipe, { "cake", "muffin", "pancakes", "oatmeal" }) and calories >= 200 then
        return "Baking", "food_recipe_baking"
    end
    return nil, nil
end

local function tokenStage(ctx)
    local text = table.concat({
        ctx.idLower or "",
        ctx.displayNameLower or "",
        ctx.iconLower or "",
        ctx.worldStaticModelLower or "",
        ctx.evolvedRecipeNameLower or "",
    }, " ")

    if containsAny(text, {
        "apple", "banana", "berry", "berries", "cherry", "fruit", "grape",
        "grapefruit", "lemon", "lime", "orange", "peach", "pear", "pineapple",
        "strawberr", "watermelon",
    }) then
        return "Fruits", "food_token_fruits"
    end
    if containsAny(text, {
        "beet", "broccoli", "cabbage", "carrot", "corn", "cucumber", "eggplant",
        "leek", "lettuce", "onion", "pea", "pepper", "potato", "radish",
        "tomato", "vegetable", "zucchini",
    }) then
        return "Vegetables", "food_token_vegetables"
    end
    if containsAny(text, {
        "catfish", "crappie", "fish", "gar", "lobster", "roe", "salmon",
        "sardine", "seafood", "shrimp", "trout",
    }) then
        return "Seafood", "food_token_seafood"
    end
    if containsAny(text, {
        "bacon", "beef", "chicken", "meat", "mutton", "pork", "poultry",
        "rabbit", "sausage", "steak", "venison",
    }) then
        return "Meat", "food_token_meat"
    end
    return nil, nil
end

function Signature.validateAdmission(ctx)
    if not ctx then
        return {
            accepted = false,
            reason = "missing_context",
            vetoHits = { "missing_context" },
            signalHits = {},
        }
    end
    return buildAdmission(ctx)
end

function Signature.match(ctx)
    if not ctx then
        return { matched = false, confidence = 0 }
    end

    local admission = Signature.validateAdmission(ctx)
    if admission.accepted ~= true then
        return { matched = false, confidence = 0, details = admissionDetails(admission) }
    end

    local prefix = perishablePrefix(ctx)
    local result = packageStage(ctx, admission)
    if result and result.matched then
        return result
    end

    if (ctx.foodTypeToken or "") == "noexplicit" and ctx.isSpice == true
        and (ctx.unhappy or 0) <= 5 and (ctx.hunger or 0) > 0
        and (ctx.eatTypeLower or "") ~= "glugfood"
        and (ctx.eatTypeLower or "") ~= "candrink" then
        return makeResult("FoodPreservedPickled", 0.89, "package", "food_pickled_fields", admissionDetails(admission))
    end
    if hasTagAlias(ctx, "preservedfood") then
        return makeResult("FoodPreserved", 0.89, "package", "food_preserved", admissionDetails(admission))
    end

    result = exactStage(ctx, prefix, admission)
    if result and result.matched then
        return result
    end

    local suffix, source = recipeStage(ctx)
    if suffix then
        result = makeFoodResult(prefix, suffix, 0.86, "recipe", source, admission)
        if result and result.matched then
            return result
        end
    end

    suffix, source = tokenStage(ctx)
    if suffix then
        result = makeFoodResult(prefix, suffix, 0.78, "token", source, admission)
        if result and result.matched then
            return result
        end
    end

    if (ctx.eatTypeLower or "") == "2handbowl"
        or (ctx.eatTypeLower or "") == "bowl"
        or (ctx.eatTypeLower or "") == "plate"
        or (ctx.eatTypeLower or "") == "2hand" then
        return makeResult(prefix .. "Portion", 0.82, "fallback", "food_portion", admissionDetails(admission))
    end

    return makeResult(prefix, 0.70, "fallback", "food_generic", admissionDetails(admission))
end

MarketSense.Signatures.Food = Signature
return Signature
