require "MarketSense/signatures/tags/MS_TagMapper"

MarketSense = MarketSense or {}
MarketSense.PostLabelResolver = MarketSense.PostLabelResolver or {}

local Resolver = MarketSense.PostLabelResolver
local TagMapper = MarketSense.TagMapper

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
    if type(list) ~= "table" then
        return
    end
    if value == nil or value == "" then
        return
    end
    list[#list + 1] = tostring(value)
end

local function contains(text, token)
    return string.find(tostring(text or ""), token, 1, true) ~= nil
end

local function containsAny(text, tokens, hits)
    local matched = false
    for _, token in ipairs(tokens or {}) do
        if contains(text, token) then
            matched = true
            push(hits, token)
        end
    end
    return matched
end

local function hasTag(ctx, token)
    return ctx and ctx.normalizedTags and ctx.normalizedTags[token] == true
end

local function hasTagAlias(ctx, token)
    return hasTag(ctx, token) or hasTag(ctx, "base" .. token)
end

local function copyTable(source)
    local copy = {}
    for key, value in pairs(source or {}) do
        copy[key] = value
    end
    return copy
end

local function copyArray(source)
    local copy = {}
    for _, value in ipairs(source or {}) do
        copy[#copy + 1] = value
    end
    return copy
end

local function buildText(ctx)
    return table.concat({
        ctx.fullLower or "",
        ctx.idLower or "",
        ctx.displayNameLower or "",
        ctx.iconLower or "",
        ctx.worldStaticModelLower or "",
        ctx.worldObjectSpriteLower or "",
        ctx.displayCategoryLower or "",
        ctx.lootTypeLower or "",
        ctx.foodTypeLower or "",
        ctx.evolvedRecipeNameLower or "",
        ctx.evolvedRecipeLower or "",
        ctx.doubleClickRecipeLower or "",
        ctx.replaceOnUseLower or "",
        ctx.replaceOnCookedLower or "",
        ctx.replaceOnDepleteLower or "",
        ctx.onCookedLower or "",
        ctx.customEatSoundLower or "",
    }, " ")
end

local function isFoodResult(result)
    local primary = tostring(result and result.primary or "")
    local category = tostring(result and result.category or "")
    return category == "Food"
        or string.sub(primary, 1, 4) == "Food"
        or string.sub(primary, 1, 8) == "Beverage"
end

local function isGenericFoodResult(result)
    local primary = tostring(result and result.primary or "")
    return primary == "Food"
        or primary == "FoodPerishable"
        or primary == "FoodNonPerishable"
        or primary == "FoodSpice"
        or primary == "FoodNoExplicit"
end

local function packagingSignal(ctx, text)
    local allText = text or buildText(ctx)
    return ctx.isCannedFood == true
        or ctx.isPackaged == true
        or hasTagAlias(ctx, "preservedfood")
        or contains(ctx.onCookedLower or "", "cannedfood")
        or containsAny(ctx.replaceOnUseLower or "", { "tincanempty", "emptyjar" })
        or containsAny(ctx.doubleClickRecipeLower or "", {
            "openboxofcannedfood",
            "opencannedfood",
            "openwaterrationcan",
            "openboxofwine",
            "openpackofbeer",
        })
        or containsAny(allText, { "canned", "jar", "rationcan", "tincan", "canopen", "_box", " box", "carton" })
end

local function strongCannedSignal(ctx, text)
    local allText = text or buildText(ctx)
    return ctx.isCannedFood == true
        or (ctx.lootTypeLower or "") == "cannedfood"
        or contains(ctx.onCookedLower or "", "cannedfood")
        or containsAny(ctx.replaceOnUseLower or "", { "tincanempty", "emptyjar" })
        or containsAny(ctx.doubleClickRecipeLower or "", {
            "openboxofcannedfood",
            "opencannedfood",
            "openwaterrationcan",
        })
        or containsAny(allText, { "canned", "rationcan", "fruitcocktail", "fruitbeverage" })
end

local function correctionResult(baseResult, token, action, reason, hits)
    if token == nil or token == "" then
        return baseResult
    end

    local result = TagMapper.makeResult(token, math.max(tonumber(baseResult and baseResult.confidence) or 0, 0.90), {
        stage = "label",
        source = "post_label_resolver",
    })
    local details = copyTable(baseResult and baseResult.details or {})
    details.labelCorrectionAction = action or "none"
    details.labelCorrectionFrom = tostring(baseResult and baseResult.primary or "")
    details.labelCorrectionTo = token
    details.labelCorrectionReason = reason or ""
    details.labelCorrectionHits = copyArray(hits)
    result.details = details
    return result
end

local function annotateNone(result)
    result = result or {}
    result.details = copyTable(result.details or {})
    result.details.labelCorrectionAction = result.details.labelCorrectionAction or "none"
    result.details.labelCorrectionFrom = result.details.labelCorrectionFrom or tostring(result.primary or "")
    result.details.labelCorrectionTo = result.details.labelCorrectionTo or tostring(result.primary or "")
    result.details.labelCorrectionReason = result.details.labelCorrectionReason or ""
    result.details.labelCorrectionHits = result.details.labelCorrectionHits or {}
    return result
end

local function isPerishableFood(ctx, result)
    local primary = tostring(result and result.primary or "")
    return string.sub(primary, 1, 15) == "FoodPerishable"
        or ctx.canAge == true
        or (tonumber(ctx.foodDaysFresh) or 0) > 0
        or (tonumber(ctx.foodDaysRotten) or 0) > 0
end

local function foodKindToken(ctx, result, suffix)
    if suffix == "Canned" then
        return "FoodNonPerishableCanned"
    end
    if suffix == "Boxed" then
        return "FoodNonPerishableBoxed"
    end
    if suffix == "Preserved" then
        return "FoodPreserved"
    end
    if isPerishableFood(ctx, result) and PERISHABLE_VARIANTS[suffix] then
        return "FoodPerishable" .. suffix
    end
    if NONPERISHABLE_VARIANTS[suffix] then
        return "FoodNonPerishable" .. suffix
    end
    return "Food" .. suffix
end

local function isDrugDisplay(ctx)
    return (ctx.displayCategoryToken or "") == "drugs"
end

local function isSmokingCue(ctx, text)
    local hits = {}
    local matched = hasTagAlias(ctx, "smokable")
        or (ctx.eatTypeLower or "") == "cigarettes"
        or (ctx.eatTypeLower or "") == "pipe"
        or containsAny(text, {
            "joint", "spliff", "blunt", "bong", "smokingpipe", "smoking pipe",
            "canpipe", "cannagar", "cigarillo", "cigaretterolled", "weedpipe",
            "crackpipe", "hookah",
        }, hits)
    return matched, hits
end

local function addCandidate(candidates, token, tier, score, action, reason, hits)
    if not token or token == "" or not TagMapper.isKnown(token) then
        return
    end

    local current = candidates[token]
    if current and (current.tier > tier or (current.tier == tier and current.score >= score)) then
        return
    end

    candidates[token] = {
        token = token,
        tier = tier,
        score = score,
        action = action,
        reason = reason,
        hits = copyArray(hits),
    }
end

local function chooseCandidate(candidates)
    local best = nil
    for _, candidate in pairs(candidates or {}) do
        if not best
            or candidate.tier > best.tier
            or (candidate.tier == best.tier and candidate.score > best.score)
            or (candidate.tier == best.tier and candidate.score == best.score and candidate.token < best.token) then
            best = candidate
        end
    end
    return best
end

function Resolver.correct(ctx, result)
    if not ctx or not result or not result.matched then
        return annotateNone(result)
    end

    local text = buildText(ctx)
    local foodLike = isFoodResult(result)
    local admittedFood = result.details and result.details.admissionAccepted == true
    local candidates = {}
    local hits = {}

    if ctx.isDung == true or hasTagAlias(ctx, "iscompostable")
        or containsAny(text, { "dung", "feces", "faeces", "manure", "guano" }, hits) then
        addCandidate(candidates, "GardeningCompostable", 120, 1.00, "reroute_root", "label_compost", hits)
    end

    hits = {}
    if hasTagAlias(ctx, "animalhead") or hasTagAlias(ctx, "animalbrain") or hasTagAlias(ctx, "feather")
        or (ctx.displayCategoryToken or "") == "animalpart"
        or containsAny(text, { "skull", " head", "_head", "bone", "tusk", "brain", "feather" }, hits) then
        addCandidate(candidates, "MaterialButchering", 118, 0.99, "reroute_root", "label_animal_remains", hits)
    end

    hits = {}
    if (ctx.displayCategoryToken or "") == "explosives"
        or (ctx.lootTypeLower or "") == "weapon"
        or containsAny(text, {
            "pipebomb", "bomb", "grenade", "mine", "trapremote", "explosive", "flametrap",
        }, hits) then
        addCandidate(candidates, "WeaponExplosive", 116, 0.99, "reroute_root", "label_explosive", hits)
    end

    hits = {}
    if containsAny(text, {
        "makeup", "eyeshadow", "lipstick", "mascara", "foundation", "blush", "rouge",
        "ratpoison", "poison",
    }, hits) then
        addCandidate(candidates, "MaterialChemical", 114, 0.98, "reroute_root", "label_chemical", hits)
    end

    hits = {}
    if containsAny(text, {
        "toiletpaper", "toilet paper", "papertowel", "paper towel", " tissue", "tissue ",
    }, hits) then
        addCandidate(candidates, "Material", 112, 0.97, "reroute_root", "label_paper_junk", hits)
    end

    hits = {}
    if containsAny(text, { "umbrella" }, hits) then
        addCandidate(candidates, "Misc", 110, 0.96, "reroute_root", "label_misc_item", hits)
    end

    hits = {}
    if (ctx.displayCategoryToken or "") == "reciperesource"
        or (ctx.lootTypeLower or "") == "reciperesource"
        or containsAny(text, { "sewingpattern", " pattern" }, hits) then
        addCandidate(candidates, "LiteratureRecipe", 108, 0.96, "reroute_root", "label_recipe_resource", hits)
    end

    if isDrugDisplay(ctx) then
        local smokingLike, smokingHits = isSmokingCue(ctx, text)
        if smokingLike then
            addCandidate(candidates, "Smoking", 106, 0.97, "reroute_root", "label_drug_smoking", smokingHits)
        else
            hits = {}
            if ctx.isCantEat == true
                and not ctx.hasFoodNutritionEvidence
                and not ctx.hasFoodRecipeEvidence
                and containsAny(text, {
                    "crack", "meth", "heroin", "cocaine", "paste", "mirror", "spoon",
                }, hits) then
                addCandidate(candidates, "MaterialChemical", 104, 0.95, "reroute_root", "label_drug_material", hits)
            end

            hits = {}
            if ctx.isCantEat == true
                and not ctx.hasFoodNutritionEvidence
                and not ctx.hasFoodRecipeEvidence
                and containsAny(text, {
                    "cannabis", "coca", "opium", "cured", "curing", "dry cannabis", " flower",
                    "leaf", "jar of",
                }, hits) then
                addCandidate(candidates, "Smoking", 103, 0.94, "reroute_root", "label_drug_leaf", hits)
            end
        end
    end

    if foodLike and admittedFood then
        local currentPrimary = tostring(result.primary or "")

        if containsAny(ctx.doubleClickRecipeLower or "", { "openboxofwine", "openpackofbeer" }, hits) then
            addCandidate(candidates, "BeverageBox", 90, 0.94, "refine_leaf", "label_beverage_box", hits)
        end

        hits = {}
        if packagingSignal(ctx, text) and containsAny(text, { "box", "_box", "carton" }, hits) then
            addCandidate(candidates, "FoodNonPerishableBoxed", 89, 0.92, "refine_leaf", "label_food_boxed", hits)
        end

        hits = {}
        if strongCannedSignal(ctx, text) and currentPrimary ~= "FoodNonPerishableBoxed" and currentPrimary ~= "BeverageBox" then
            addCandidate(candidates, "FoodNonPerishableCanned", 88, 0.91, "refine_leaf", "label_food_canned", hits)
        end

        hits = {}
        if hasTagAlias(ctx, "preservedfood") and not strongCannedSignal(ctx, text) then
            push(hits, "preservedfood")
            addCandidate(candidates, "FoodPreserved", 87, 0.90, "refine_leaf", "label_food_preserved", hits)
        end

        hits = {}
        if (ctx.foodTypeToken or "") == "herb"
            or containsAny(text, {
                "basil", "chamomile", "chives", "cilantro", "cinnamon", "lavender",
                "lemongrass", "lemon grass", "marigold", "mint", "oregano",
                "parsley", "rosemary", "sage", "thyme", "ginger",
            }, hits) then
            addCandidate(candidates, "FoodHerb", 84, 0.94, "refine_leaf", "label_food_herb", hits)
        end

        hits = {}
        if (ctx.foodTypeToken or "") == "stock"
            or containsAny(text, { "bouillon", "broth", "stock" }, hits) then
            addCandidate(candidates, "FoodStock", 84, 0.94, "refine_leaf", "label_food_stock", hits)
        end

        hits = {}
        if (ctx.foodTypeToken or "") == "petfood"
            or containsAny(text, { "catfood", "dogfood", "treats", "pet food" }, hits) then
            addCandidate(candidates, "FoodPetFood", 84, 0.94, "refine_leaf", "label_food_pet", hits)
        end

        hits = {}
        if (ctx.foodTypeToken or "") == "staple"
            or containsAny(text, {
                "cereal", "oatmeal", "oats", "oat ", "barley", "cornmeal", "cornflour",
                "rice", "pasta", "bean", "beans", "flour",
            }, hits) then
            addCandidate(candidates, "FoodStaple", 83, 0.93, "refine_leaf", "label_food_staple", hits)
        end

        hits = {}
        if (ctx.foodTypeToken or "") == "spice"
            or (ctx.foodTypeToken or "") == "salt"
            or ((ctx.isSpice == true or currentPrimary == "FoodSpice")
                and containsAny(text, {
                    "seasoning", "salt", "pepper", "powderedgarlic", "powderedonion",
                    "sauce", "paste", "vinegar", "sesameoil", "soy", "wasabi",
                }, hits)) then
            addCandidate(candidates, "FoodSpice", 82, 0.92, "refine_leaf", "label_food_spice", hits)
        end

        hits = {}
        if (ctx.foodTypeToken or "") == "candy"
            or containsAny(text, {
                "allsorts", "candy", "candies", "candycane", "caramel", "gummy",
                "gummies", "jellybean", "jellybeans", "licorice", "lollipop",
                "modjeska", "peppermint", "rockcandy", "hardcand", "jujube",
            }, hits) then
            addCandidate(candidates, foodKindToken(ctx, result, "Candy"), 82, 0.92, "refine_leaf", "label_food_candy", hits)
        end

        hits = {}
        if (ctx.foodTypeToken or "") == "baking"
            or containsAny(text, {
                "batter", "dough", "bakingsoda", "baking soda", "yeast", "cocoa",
                "cake", "muffin", "cookiedough", "browniepan",
            }, hits) then
            addCandidate(candidates, foodKindToken(ctx, result, "Baking"), 81, 0.91, "refine_leaf", "label_food_baking", hits)
        end

        hits = {}
        if (ctx.foodTypeToken or "") == "bread"
            or containsAny(text, {
                "bread", "bagel", "baguette", "bun", "croissant", "toast",
                "painauchocolat", "danish",
            }, hits) then
            addCandidate(candidates, foodKindToken(ctx, result, "Bread"), 81, 0.91, "refine_leaf", "label_food_bread", hits)
        end

        hits = {}
        if (ctx.foodTypeToken or "") == "cheese"
            or (ctx.foodTypeToken or "") == "dairy"
            or containsAny(text, { "butter", "cheese", "milkpowder", "milk powder" }, hits) then
            addCandidate(candidates, foodKindToken(ctx, result, "Dairy"), 81, 0.91, "refine_leaf", "label_food_dairy", hits)
        end

        hits = {}
        if containsAny(text, {
            "crisps", "chips", "tortillachips", "jerky", "cracker", "pretzel", "snack",
        }, hits) then
            addCandidate(candidates, foodKindToken(ctx, result, "Snack"), 80, 0.90, "refine_leaf", "label_food_snack", hits)
        end

        hits = {}
        if containsAny(text, {
            "apple", "banana", "berry", "fruit", "peach", "pear", "pineapple", "grape",
        }, hits) then
            addCandidate(candidates, foodKindToken(ctx, result, "Fruits"), 78, 0.89, "refine_leaf", "label_food_fruits", hits)
        end

        hits = {}
        if containsAny(text, {
            "carrot", "tomato", "broccoli", "cabbage", "corn", "eggplant", "leek",
            "pea", "potato", "vegetable", "avocado", "pepper", "capers", "olive",
        }, hits) then
            addCandidate(candidates, foodKindToken(ctx, result, "Vegetables"), 78, 0.89, "refine_leaf", "label_food_vegetables", hits)
        end

        hits = {}
        if containsAny(text, {
            "fish", "roe", "sardine", "seafood", "shrimp", "lobster", "trout", "oyster",
            "mussel",
        }, hits) then
            addCandidate(candidates, foodKindToken(ctx, result, "Seafood"), 78, 0.89, "refine_leaf", "label_food_seafood", hits)
        end

        hits = {}
        if containsAny(text, {
            "beef", "meat", "pork", "chicken", "steak", "sausage", "venison", "bacon",
            "ham", "baloney", "mutton",
        }, hits) then
            addCandidate(candidates, foodKindToken(ctx, result, "Meat"), 78, 0.89, "refine_leaf", "label_food_meat", hits)
        end

        if isGenericFoodResult(result) then
            hits = {}
            if containsAny(text, { "ration", "meal", "tvdinner", "dinner" }, hits) then
                addCandidate(candidates, "FoodPerishableMeal", 66, 0.85, "refine_leaf", "label_food_meal", hits)
            end
        end
    end

    local selected = chooseCandidate(candidates)
    if not selected or selected.token == tostring(result.primary or "") then
        return annotateNone(result)
    end
    return correctionResult(result, selected.token, selected.action, selected.reason, selected.hits)
end

return Resolver
