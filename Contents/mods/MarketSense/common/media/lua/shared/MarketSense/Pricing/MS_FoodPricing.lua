require "MarketSense/MS_Config"
require "MarketSense/MS_TagUtils"
require "MarketSense/MS_Core"
require "MarketSense/Pricing/MS_YieldResolver"

MarketSense = MarketSense or {}
MarketSense.FoodPricing = MarketSense.FoodPricing or {}

local FoodPricing = MarketSense.FoodPricing
local Config = MarketSense.ItemRuntimeConfig
local TagUtils = MarketSense.TagUtils
local Core = MarketSense.Core
local YieldResolver = MarketSense.YieldResolver

local DEFAULTS = {
    model = "food_v2",
    anchor = 10.0,
    floor = 1.0,
    ceiling = 250.0,
    -- Food.getHungerChange/getThirstChange expose native values. Item scripts
    -- store those two fields in hundredths (for example -30 becomes -0.30).
    hungerScale = 0.30,
    thirstScale = 0.30,
    caloriesScale = 600.0,
    hungerWeight = 0.55,
    thirstWeight = 0.20,
    caloriesWeight = 0.25,
    maxHungerUnits = 6.0,
    maxThirstUnits = 6.0,
    maxCaloriesUnits = 6.0,
    minimumRationUnits = 0.25,
    moodBenefitWeight = 0.015,
    moodPenaltyWeight = 0.020,
    moodFloor = 0.70,
    moodCeiling = 1.20,
    weightPenalty = 0.035,
    bulkFloor = 0.75,
    shelfLifeFloor = 0.90,
    shelfLifeCeiling = 1.10,
    shelfLifeDaysScale = 30.0,
    freshnessFloor = 0.45,
    rottenMultiplier = 0.08,
    ingredientMultiplier = 0.35,
    spiceMultiplier = 0.65,
    insectMultiplier = 0.78,
    petFoodMultiplier = 0.25,
    seedMultiplier = 0.20,
    preservedMultiplier = 1.05,
    cannedMultiplier = 1.08,
    packagedMultiplier = 1.03,
    uncookedMultiplier = 0.85,
    cookedMultiplier = 1.15,
    burntMultiplier = 0.45,
    harmfulChangeMultiplier = 0.015,
    harmfulChangeFloor = 0.65,
    bundleMultiplier = 1.0,
    bundlePremium = 0.0,
}

local function number(value, fallback)
    value = tonumber(value)
    if value == nil then return fallback end
    return value
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function settings()
    local configured = Config and Config.foodPricing
    if type(configured) ~= "table" then
        return DEFAULTS
    end

    local result = {}
    for key, fallback in pairs(DEFAULTS) do
        result[key] = configured[key] ~= nil and configured[key] or fallback
    end
    return result
end

local function tagPresent(details, tag)
    return TagUtils.hasTag(details.expandedTags or details.tags or {}, tag)
end

local function signedValue(ctx, signedKey, magnitudeKey)
    if ctx[signedKey] ~= nil then
        return number(ctx[signedKey], 0)
    end
    return -(number(ctx[magnitudeKey], 0) or 0)
end

local function benefit(value)
    return math.max(0, -(number(value, 0) or 0))
end

local function harm(value)
    return math.max(0, number(value, 0) or 0)
end

local function diminishingUnits(value, scale, cap)
    value = math.max(0, number(value, 0) or 0)
    scale = math.max(0.01, number(scale, 1) or 1)
    cap = math.max(0, number(cap, 0) or 0)
    return math.min(cap, math.sqrt(value / scale))
end

local function countEvolvedRecipes(ctx)
    local text = tostring(ctx.evolvedRecipe or "")
    if text == "" then
        text = tostring(ctx.evolvedRecipeName or "")
    end
    local count = 0
    for _ in string.gmatch(text, "[^;,]+") do
        count = count + 1
    end
    return count
end

local function roleMultiplier(ctx, details, c)
    local multiplier = 1.0
    local role = "edible"

    local hasResolvedYield = details.yieldResolution
        and details.yieldResolution.status == "resolved"
    if ctx.isCantEat == true and not hasResolvedYield then
        multiplier = number(c.ingredientMultiplier, DEFAULTS.ingredientMultiplier)
        role = "ingredient"
    end
    if tagPresent(details, "FoodSeed") then
        multiplier = math.min(multiplier, number(c.seedMultiplier, DEFAULTS.seedMultiplier))
        role = "seed"
    elseif tagPresent(details, "FoodPetFood") then
        multiplier = math.min(multiplier, number(c.petFoodMultiplier, DEFAULTS.petFoodMultiplier))
        role = "pet_food"
    elseif tagPresent(details, "FoodInsect") then
        multiplier = multiplier * number(c.insectMultiplier, DEFAULTS.insectMultiplier)
        role = "insect"
    elseif tagPresent(details, "FoodSpice") or ctx.isSpice == true then
        multiplier = multiplier * number(c.spiceMultiplier, DEFAULTS.spiceMultiplier)
        role = "spice"
    end

    if tagPresent(details, "FoodPreserved") or tagPresent(details, "FoodPreservedPickled") then
        multiplier = multiplier * number(c.preservedMultiplier, DEFAULTS.preservedMultiplier)
    elseif tagPresent(details, "FoodNonPerishableCanned") or ctx.isCannedFood == true then
        multiplier = multiplier * number(c.cannedMultiplier, DEFAULTS.cannedMultiplier)
    elseif ctx.isPackaged == true then
        multiplier = multiplier * number(c.packagedMultiplier, DEFAULTS.packagedMultiplier)
    end

    return clamp(multiplier, 0.05, 1.50), role
end

local function copyPath(path)
    local result = {}
    for key, value in pairs(path or {}) do result[key] = value end
    return result
end

local function inheritedFoodState(parent, child, output)
    if output and output.inheritFoodAge == true and parent.hasRuntimeFoodAge == true then
        child.foodAge = parent.foodAge
        child.hasRuntimeFoodAge = true
        child.hasRuntimeFoodState = parent.hasRuntimeFoodState == true
        child.isRotten = parent.isRotten == true
        child.isFrozen = parent.isFrozen == true
    end
    return child
end

local function calculateBundle(ctx, details, yieldInfo, c)
    local Pricing = MarketSense.Pricing
    if not Pricing or type(Pricing.calculateDetails) ~= "function" then
        return nil, "pricing API unavailable"
    end

    local path = copyPath(details._yieldPath)
    local total = 0
    local contributions = {}
    for _, output in ipairs(yieldInfo.outputs or {}) do
        local quantity = number(output.quantity, 0)
        local chance = number(output.chance, 1.0)
        local fullType = tostring(output.fullType or "")
        if fullType == "" then return nil, "output item is unresolved" end
        if quantity <= 0 then return nil, "output quantity is not positive" end
        if chance < 1.0 then
            return nil, "probabilistic output is not deterministic"
        end
        if path[fullType] then return nil, "yield cycle detected" end

        local childContext = MarketSense.PropertyReader
            and MarketSense.PropertyReader.buildContext(fullType) or nil
        if type(childContext) ~= "table" or childContext.item == nil then
            return nil, "output item is unavailable: " .. fullType
        end
        childContext = inheritedFoodState(ctx, childContext, output)

        local childPath = copyPath(path)
        childPath[fullType] = true
        local childDetails = Pricing.calculateDetails(
            childContext, false, nil, { yieldPath = childPath }
        )
        local childYield = childDetails.yieldResolution
        if type(childYield) == "table"
            and childYield.status == "resolved"
            and childYield.evaluation == "fallback" then
            return nil, "nested bundle evaluation failed: " .. fullType
        end
        local unitValue = number(childDetails.rawScore, nil)
        if unitValue == nil then
            return nil, "output item did not produce a raw score: " .. fullType
        end
        local value = unitValue * quantity
        total = total + value
        contributions[#contributions + 1] = {
            fullType = fullType,
            quantity = quantity,
            unitRawScore = unitValue,
            contribution = value,
            model = childDetails.priceHeuristic
                and childDetails.priceHeuristic.model or nil,
            role = childDetails.priceHeuristic
                and childDetails.priceHeuristic.role or nil,
        }
    end

    if #contributions == 0 then return nil, "yield has no outputs" end
    local multiplier = number(c.bundleMultiplier, DEFAULTS.bundleMultiplier)
    local premium = number(c.bundlePremium, DEFAULTS.bundlePremium)
    local score = (total * multiplier) + premium
    local floor = math.max(0, number(c.floor, DEFAULTS.floor) or DEFAULTS.floor)
    local ceiling = math.max(floor, number(c.ceiling, DEFAULTS.ceiling) or DEFAULTS.ceiling)
    score = clamp(score, floor, ceiling)
    return score, {
        model = tostring(c.model or DEFAULTS.model) .. "_bundle",
        anchor = number(c.anchor, DEFAULTS.anchor),
        mode = #contributions > 1 and "multi_output_bundle" or "bundle",
        recipe = yieldInfo.recipe,
        yieldResolution = Core.deepCopy(yieldInfo),
        outputValue = total,
        bundleMultiplier = multiplier,
        bundlePremium = premium,
        contributions = contributions,
        score = score,
    }
end

local function freshnessMultiplier(ctx, c)
    if ctx.hasRuntimeFoodAge ~= true or ctx.foodAge == nil then
        return 1.0, "definition_freshness"
    end

    local age = math.max(0, number(ctx.foodAge, 0) or 0)
    local fresh = math.max(0, number(ctx.foodDaysFresh, 0) or 0)
    local rotten = math.max(0, number(ctx.foodDaysRotten, 0) or 0)

    if ctx.isRotten == true or (rotten > 0 and age >= rotten) then
        return clamp(number(c.rottenMultiplier, DEFAULTS.rottenMultiplier), 0.01, 1.0), "rotten"
    end
    if rotten <= fresh then
        return 1.0, "no_spoilage_window"
    end
    if age <= fresh then
        return 1.0, "fresh"
    end

    local progress = clamp((age - fresh) / (rotten - fresh), 0, 1)
    local floor = clamp(number(c.freshnessFloor, DEFAULTS.freshnessFloor), 0.05, 1.0)
    return 1.0 - ((1.0 - floor) * progress), "stale"
end

local function shelfLifeMultiplier(ctx, c)
    local rotten = math.max(0, number(ctx.foodDaysRotten, 0) or 0)
    local fresh = math.max(0, number(ctx.foodDaysFresh, 0) or 0)
    local horizon = math.max(fresh, rotten)
    if horizon <= 0 then
        return 1.0, "unknown_or_nonaging"
    end

    local floor = clamp(number(c.shelfLifeFloor, DEFAULTS.shelfLifeFloor), 0.50, 1.0)
    local ceiling = math.max(
        floor,
        number(c.shelfLifeCeiling, DEFAULTS.shelfLifeCeiling)
    )
    local scale = math.max(1.0, number(c.shelfLifeDaysScale, DEFAULTS.shelfLifeDaysScale))
    local progress = clamp(math.sqrt(horizon / scale), 0, 1)
    return floor + ((ceiling - floor) * progress), "static_horizon"
end

local function moodMultiplier(ctx, c)
    local unhappy = signedValue(ctx, "unhappyChange", "unhappy")
    local boredom = signedValue(ctx, "boredomChange", "boredom")
    local stress = signedValue(ctx, "stressChange", "stress")
    local benefitValue = benefit(unhappy) + benefit(boredom) + benefit(stress)
    local harmValue = harm(unhappy) + harm(boredom) + harm(stress)
    local multiplier = 1.0
        + (benefitValue * number(c.moodBenefitWeight, DEFAULTS.moodBenefitWeight))
        - (harmValue * number(c.moodPenaltyWeight, DEFAULTS.moodPenaltyWeight))
    return clamp(
        multiplier,
        number(c.moodFloor, DEFAULTS.moodFloor),
        number(c.moodCeiling, DEFAULTS.moodCeiling)
    ), benefitValue, harmValue
end

local function bulkMultiplier(ctx, rationUnits, c)
    local weight = math.max(0, number(ctx.weight, 0) or 0)
    if weight <= 0 or rationUnits <= 0 then return 1.0 end
    local penalty = (weight / math.max(1.0, rationUnits))
        * number(c.weightPenalty, DEFAULTS.weightPenalty)
    return clamp(
        1.0 - penalty,
        number(c.bulkFloor, DEFAULTS.bulkFloor),
        1.0
    )
end

function FoodPricing.calculate(ctx, details)
    ctx = ctx or {}
    details = details or {}
    local c = settings()
    local yieldInfo = details.yieldResolution or YieldResolver.resolve(ctx)
    details.yieldResolution = yieldInfo

    if yieldInfo.status == "resolved" then
        local bundleScore, bundleHeuristic = calculateBundle(ctx, details, yieldInfo, c)
        if bundleScore ~= nil then
            details.priceHeuristic = bundleHeuristic
            return bundleScore
        end
        yieldInfo.evaluation = "fallback"
        yieldInfo.fallbackReason = bundleHeuristic or "bundle evaluation failed"
    end

    local hungerChange = signedValue(ctx, "hungerChange", "hunger")
    local thirstChange = signedValue(ctx, "thirstChange", "thirst")
    local calories = math.max(0, number(ctx.calories, 0) or 0)

    local hungerUnits = diminishingUnits(
        benefit(hungerChange), c.hungerScale, c.maxHungerUnits
    )
    local thirstUnits = diminishingUnits(
        benefit(thirstChange), c.thirstScale, c.maxThirstUnits
    )
    local calorieUnits = diminishingUnits(
        calories, c.caloriesScale, c.maxCaloriesUnits
    )

    local rationUnits = hungerUnits * number(c.hungerWeight, DEFAULTS.hungerWeight)
        + thirstUnits * number(c.thirstWeight, DEFAULTS.thirstWeight)
        + calorieUnits * number(c.caloriesWeight, DEFAULTS.caloriesWeight)
    local roleValue, roleName = roleMultiplier(ctx, details, c)
    if ctx.isCantEat == true then
        local recipes = countEvolvedRecipes(ctx)
        rationUnits = number(c.minimumRationUnits, DEFAULTS.minimumRationUnits)
            + math.min(4, recipes) * 0.05
    else
        rationUnits = math.max(
            number(c.minimumRationUnits, DEFAULTS.minimumRationUnits),
            rationUnits
        )
    end

    local mood, moodBenefit, moodHarm = moodMultiplier(ctx, c)
    local shelfLife, shelfLifeState = shelfLifeMultiplier(ctx, c)
    local freshness, freshnessState = freshnessMultiplier(ctx, c)
    local bulk = bulkMultiplier(ctx, rationUnits, c)
    local preparation = 1.0
    if ctx.isBurnt == true then
        preparation = clamp(number(c.burntMultiplier, DEFAULTS.burntMultiplier), 0.05, 1.0)
    elseif ctx.isCooked == true then
        preparation = clamp(number(c.cookedMultiplier, DEFAULTS.cookedMultiplier), 0.05, 1.50)
    elseif ctx.isDangerousUncooked == true and ctx.hasRuntimeFoodState == true then
        preparation = clamp(number(c.uncookedMultiplier, DEFAULTS.uncookedMultiplier), 0.05, 1.0)
    end

    local harmfulChange = harm(hungerChange) + harm(thirstChange)
    local harmfulChangeMult = clamp(
        1.0 - (harmfulChange * number(c.harmfulChangeMultiplier, DEFAULTS.harmfulChangeMultiplier)),
        number(c.harmfulChangeFloor, DEFAULTS.harmfulChangeFloor),
        1.0
    )
    if ctx.isPoison == true or ctx.isDung == true then
        harmfulChangeMult = math.min(harmfulChangeMult, 0.15)
    end

    local anchor = math.max(0, number(c.anchor, DEFAULTS.anchor) or DEFAULTS.anchor)
    local score = anchor * rationUnits * roleValue * mood * shelfLife * freshness * bulk
        * preparation * harmfulChangeMult
    local floor = math.max(0, number(c.floor, DEFAULTS.floor) or DEFAULTS.floor)
    local ceiling = math.max(floor, number(c.ceiling, DEFAULTS.ceiling) or DEFAULTS.ceiling)
    score = clamp(score, floor, ceiling)

    details.priceHeuristic = {
        model = tostring(c.model or DEFAULTS.model),
        anchor = anchor,
        role = roleName,
        rationUnits = rationUnits,
        hungerChange = hungerChange,
        thirstChange = thirstChange,
        hungerUnits = hungerUnits,
        thirstUnits = thirstUnits,
        calorieUnits = calorieUnits,
        calories = calories,
        moodMultiplier = mood,
        moodBenefit = moodBenefit,
        moodHarm = moodHarm,
        roleMultiplier = roleValue,
        shelfLifeMultiplier = shelfLife,
        shelfLifeState = shelfLifeState,
        freshnessMultiplier = freshness,
        freshnessState = freshnessState,
        bulkMultiplier = bulk,
        preparationMultiplier = preparation,
        harmfulChangeMultiplier = harmfulChangeMult,
        yieldResolution = Core.deepCopy(yieldInfo),
        hasRuntimeFoodAge = ctx.hasRuntimeFoodAge == true,
        foodAge = ctx.foodAge,
        foodDaysFresh = ctx.foodDaysFresh,
        foodDaysRotten = ctx.foodDaysRotten,
        isRotten = ctx.isRotten == true,
        score = score,
    }
    return score
end

return FoodPricing
