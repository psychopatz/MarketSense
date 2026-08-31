-- MS_filter_Theme.lua
-- Applies independent, evidence-backed Theme descriptor tags.
--
-- Theme is deliberately multi-valued. A padded camouflage jacket can be
-- winter clothing, camouflage, and militia/survival gear at the same time.
-- These descriptors are overlays; they never replace the primary taxonomy.

require "MarketSense/MS_Config"
require "MarketSense/MS_TagEvidence"

MarketSense = MarketSense or {}
MarketSense.Filters = MarketSense.Filters or {}
MarketSense.Filters.Theme = MarketSense.Filters.Theme or {}

local Filter = MarketSense.Filters.Theme
local Config = MarketSense.ItemRuntimeConfig
local TagEvidence = MarketSense.TagEvidence

local TEXT_FIELDS = {
    { name = "fullType", key = "fullLower" },
    { name = "itemId", key = "idLower" },
    { name = "displayName", key = "displayNameLower" },
    { name = "description", key = "descriptionLower" },
    { name = "displayCategory", key = "displayCategoryLower" },
    { name = "itemType", key = "itemTypeLower" },
    { name = "bodyLocation", key = "bodyLocationLower" },
    { name = "worldStaticModel", key = "worldStaticModelLower" },
    { name = "worldObjectSprite", key = "worldObjectSpriteLower" },
}

local MATERIAL_FIELDS = {
    { name = "fullType", key = "fullLower" },
    { name = "itemId", key = "idLower" },
    { name = "displayName", key = "displayNameLower" },
    { name = "itemType", key = "itemTypeLower" },
    { name = "worldStaticModel", key = "worldStaticModelLower" },
    { name = "worldObjectSprite", key = "worldObjectSpriteLower" },
}

local TEXT_RULES = {
    { tag = "Theme.Combat", terms = { "tactical", "military", "combat", "assault", "swat", "riot" } },
    { tag = "Theme.Police", terms = { "police", "officer", "sheriff", "deputy" } },
    { tag = "Theme.Militia", terms = { "militia", "hunter", "ranger" } },
    { tag = "Theme.Survival", terms = { "survival", "backpack", "camping", "hiking", "wilderness" } },
    { tag = "Theme.Winter", terms = { "winter", "snow", "cold", "insulated", "thermal" } },
    { tag = "Theme.Industrial", terms = { "industrial", "construction", "worker", "hardhat", "workwear" } },
    { tag = "Theme.Primitive", terms = { "primitive", "stone", "flint", "crude", "improvised" } },
    { tag = "Theme.Camouflage", terms = { "camo", "camouflage" } },
}

-- Seasonal tags describe suitability, not spoilage. They are deliberately
-- conservative: explicit garment names are accepted broadly, while numeric
-- rules require a clothing context and a measured property.
local SUMMER_TERMS = {
    "summer", "tank top", "tanktop", "t-shirt", "t shirt", "tshirt",
    "shorts", "short sleeve", "short-sleeve", "sundress", "swimsuit",
    "swim suit", "bikini", "sandals", "flip flops", "flip-flops",
    "straw hat",
}

local RAIN_TERMS = {
    "raincoat", "rain coat", "rain poncho", "poncho", "umbrella",
    "waterproof", "water proof", "gore-tex", "goretex", "rain boots",
    "rubber boots",
}

local SWIMWEAR_TERMS = {
    "swimsuit", "swim suit", "swimming", "swim trunks", "swim fins",
    "bikini", "goggles", "diving", "dive mask", "diving mask", "snorkel",
    "wetsuit", "wet suit", "flippers", "swimwear",
}

local SWIMWEAR_TOKENS = {
    "Swimwear", "Swimming", "Diving", "Swimsuit", "Wetsuit",
}

local GROWING_TERMS = {
    "seed", "seed packet", "seed bag", "fertilizer", "fertiliser", "compost",
    "garden", "gardening", "garden tool", "planter", "watering can", "wateringcan",
    "pest control", "insecticide", "molluscide", "farming supply",
}

local HUNTING_TERMS = {
    "hunting", "hunter", "hunting rifle", "hunting shotgun", "hunting bow",
    "deer hunting", "duck hunting", "birdshot", "buckshot", "varmint",
    "game load", "animal trap", "trap cage", "trapcrate", "trapsnare",
}

local FISHING_TERMS = {
    "fishing rod", "fishingrod", "fishing hook", "fishinghook",
    "fishing line", "fishingline", "fishing net", "fishingnet",
    "fishing lure", "fishinglure", "jig lure", "jiglure", "minnow lure",
    "minnowlure", "fish bait", "fishbait", "bobber", "chum",
}

local HOLIDAY_TERMS = {
    "holiday", "christmas", "xmas", "halloween", "thanksgiving", "easter",
    "valentine", "valentines", "new year", "newyear", "ornament", "stocking",
    "jack-o-lantern", "jackolantern",
}

local HOLIDAY_TOKENS = {
    "Holiday", "Christmas", "Xmas", "Halloween", "Thanksgiving", "Easter",
    "Valentine", "Valentines", "NewYear", "Ornament", "Stocking",
    "JackOLantern",
}

local GROWING_TOKENS = {
    "Gardening", "GardeningSeed", "GardeningSeedPacket", "GardeningCompostable",
    "GardeningCompost", "GardeningFertilizer", "GardeningPestControl",
    "GardeningHarvest", "ToolFarming", "ToolGardening", "ContainerSeedBag",
    "BuildingGarden", "BuildingGardenPlanter", "BuildingAgriculture",
    "BuildingAgricultureHay", "BuildingAgricultureLivestock",
    "BuildingAgricultureScarecrow",
}

local HUNTING_TOKENS = {
    "MiscTrapping", "BuildingSurvivalTrap", "Trapping", "Hunting", "HuntingClothing",
    "HuntingWeapon", "HuntingAmmo",
}

local FISHING_TOKENS = {
    "MiscFishing", "ToolFishing", "Fishing", "FishingRod", "FishingLure",
    "FishingBait", "FishingHook", "FishingLine", "FishingNet",
}

-- Strong names are only a fallback for definitions where the runtime device
-- API is unavailable. `ham` is intentionally omitted because it also occurs
-- in food names (ham, ham sandwich, and so on).
local COMMUNICATION_TERMS = {
    "walkie-talkie", "walkie talkie", "walkietalkie", "walkie",
    "two-way radio", "two way radio", "twowayradio", "ham radio", "hamradio",
}

local MATERIAL_RULES = {
    { tag = "Theme.Leather", terms = { "leather", "buckskin", "suede", "rawhide" } },
    { tag = "Theme.Denim", terms = { "denim", "jean", "jeans" } },
    { tag = "Theme.Wool", terms = { "wool", "woolen", "cashmere" } },
    { tag = "Theme.Silk", terms = { "silk" } },
    { tag = "Theme.Cotton", terms = { "cotton" } },
    { tag = "Theme.Rubber", terms = { "rubber", "latex" } },
    { tag = "Theme.Canvas", terms = { "canvas", "tarpaulin" } },
    { tag = "Theme.Fur", terms = { "fur" } },
}

local function isLetter(value)
    return value ~= "" and string.match(value, "^[a-z]$") ~= nil
end

local function matchTerm(text, term)
    text = string.lower(tostring(text or ""))
    term = string.lower(tostring(term or ""))
    if text == "" or term == "" then return nil end

    local start = string.find(text, term, 1, true)
    while start do
        local before = string.sub(text, start - 1, start - 1)
        local after = string.sub(text, start + #term, start + #term)
        local beforeBoundary = start == 1 or not isLetter(before)
        local afterBoundary = after == "" or not isLetter(after)

        -- `camo` needs a component boundary on the left; this accepts
        -- CamoPants but rejects Guacamole. `fur` requires both boundaries so
        -- Furniture cannot become fur-themed by substring accident.
        if term == "camo" then
            if beforeBoundary then return start end
        elseif term == "fur" then
            if beforeBoundary and afterBoundary then return start end
        elseif beforeBoundary or #term >= 5 then
            return start
        end
        start = string.find(text, term, start + 1, true)
    end
    return nil
end

local function findTerm(ctx, terms, fields)
    for _, field in ipairs(fields or TEXT_FIELDS) do
        local value = ctx and ctx[field.key]
        local text = tostring(value or "")
        for _, term in ipairs(terms or {}) do
            if matchTerm(text, term) then
                return field.name, term
            end
        end
    end
    return nil, nil
end

local function hasTerm(ctx, terms, fields)
    local field, term = findTerm(ctx, terms, fields)
    return field ~= nil, field, term
end

local function hasTag(tags, wanted)
    for _, tag in ipairs(tags or {}) do
        if tostring(tag) == wanted then return true end
    end
    return false
end

local function findResultToken(result, tokens)
    local candidates = {}
    if result and result.primary then candidates[#candidates + 1] = result.primary end
    for _, tag in ipairs(result and result.tags or {}) do
        candidates[#candidates + 1] = tag
    end
    for _, tag in ipairs(result and result.expandedTags or {}) do
        candidates[#candidates + 1] = tag
    end
    for _, wanted in ipairs(tokens or {}) do
        for _, candidate in ipairs(candidates) do
            if tostring(candidate) == wanted then return wanted end
        end
    end
    return nil
end

local function findContextToken(ctx, tokens)
    for _, token in ipairs(tokens or {}) do
        if TagEvidence.has(ctx, token) then return token end
    end
    return nil
end

local function addEvidence(result, tag, field, term, confidence, metadata)
    result.details = result.details or {}
    result.details.descriptorEvidence = result.details.descriptorEvidence or {}
    local evidence = {
        tag = tag,
        source = "theme_heuristic",
        field = field,
        token = term,
        confidence = confidence,
    }
    for key, value in pairs(metadata or {}) do evidence[key] = value end
    result.details.descriptorEvidence[#result.details.descriptorEvidence + 1] = evidence
end

local function addSignalTheme(result, tags, tag, field, token, confidence)
    if hasTag(tags, tag) then return end
    tags[#tags + 1] = tag
    addEvidence(result, tag, field, token, confidence)
end

local function addRejected(result, tag, field, term, reason)
    result.details = result.details or {}
    result.details.descriptorRejected = result.details.descriptorRejected or {}
    result.details.descriptorRejected[#result.details.descriptorRejected + 1] = {
        tag = tag,
        source = "theme_heuristic",
        field = field,
        token = term,
        reason = reason,
    }
end

local function number(value, fallback)
    value = tonumber(value)
    return value ~= nil and value or fallback
end

local function configuredThreshold(sandboxKey, configKey, fallback)
    local vars = Config and Config.sandboxVars or nil
    local value = vars and vars[sandboxKey] or nil
    if value == nil then
        local foodPricing = Config and Config.foodPricing or nil
        value = foodPricing and foodPricing[configKey] or nil
    end
    return math.max(0, number(value, fallback))
end

local function configuredPricingValue(sandboxKey, sectionName, configKey, fallback)
    local vars = Config and Config.sandboxVars or nil
    local value = vars and vars[sandboxKey] or nil
    if value == nil then
        local pricing = Config and Config[sectionName] or nil
        value = pricing and pricing[configKey] or nil
    end
    return math.max(0, number(value, fallback))
end

local function foodValue(ctx, key)
    local value = ctx and ctx[key]
    if value == nil and type(ctx and ctx.foodFacts) == "table" then
        value = ctx.foodFacts[key]
    end
    return number(value, nil)
end

local function isFoodContext(ctx)
    if not ctx then return false end
    if ctx.isFoodInstance == true or ctx.hasFoodNutritionEvidence == true then
        return true
    end

    local category = string.lower(tostring(ctx.displayCategoryLower or ""))
    local itemType = string.lower(tostring(ctx.itemTypeLower or ""))
    local foodType = string.lower(tostring(ctx.foodTypeLower or ctx.foodType or ""))
    local lootType = string.lower(tostring(ctx.lootTypeLower or ctx.lootType or ""))
    return string.find(category, "food", 1, true) ~= nil
        or string.find(category, "beverage", 1, true) ~= nil
        or string.find(itemType, "food", 1, true) ~= nil
        or foodType ~= ""
        or string.find(lootType, "food", 1, true) ~= nil
end

local function addNumericTheme(ctx, result, tags, tag, field, threshold, confidence)
    local value = foodValue(ctx, field)
    if value == nil or value < threshold or hasTag(tags, tag) then return end

    tags[#tags + 1] = tag
    addEvidence(result, tag, field, ">= " .. tostring(threshold), confidence, {
        value = value, threshold = threshold, operator = ">=",
    })
end

local function isClothingContext(ctx)
    if not ctx then return false end
    return string.find(tostring(ctx.displayCategoryLower or ""),
        "clothing", 1, true) ~= nil
        or string.find(tostring(ctx.itemTypeLower or ""),
            "clothing", 1, true) ~= nil
        or tostring(ctx.bodyLocationLower or "") ~= ""
end

local function measuredValue(ctx, valueKey, availableKey)
    local value = number(ctx and ctx[valueKey], nil)
    if value == nil then return nil, false end
    -- Contexts created by older integrations have no availability flag. A
    -- present numeric value in those contexts remains usable for backward
    -- compatibility; an explicit false always means "not measured".
    if ctx and ctx[availableKey] == false then return value, false end
    return value, true
end

-- apply(ctx, result) — mutates result.tags in-place, returns result.
function Filter.apply(ctx, result)
    result = result or {}
    local tags = result.tags or {}
    local hasExplicitTheme = false
    for _, tag in ipairs(tags) do
        if string.sub(tostring(tag), 1, 6) == "Theme." then
            hasExplicitTheme = true
            break
        end
    end
    if hasExplicitTheme and result.details and result.details.source == "item_override" then
        for _, tag in ipairs(tags) do
            if string.sub(tostring(tag), 1, 6) == "Theme." then
                addEvidence(result, tostring(tag), "item_override", tostring(tag), 1.0)
            end
        end
    end

    for _, rule in ipairs(TEXT_RULES) do
        local matched, field, term = hasTerm(ctx, rule.terms, TEXT_FIELDS)
        if matched and rule.tag == "Theme.Survival" and term == "backpack" then
            local negativeField, negativeTerm = findTerm(ctx,
                { "nobackpack", "scba_nobackpack" }, TEXT_FIELDS)
            if negativeField then
                addRejected(result, rule.tag, negativeField, negativeTerm,
                    "explicit no-backpack variant")
                matched = false
            end
        end
        if matched and not hasTag(tags, rule.tag) then
            tags[#tags + 1] = rule.tag
            addEvidence(result, rule.tag, field, term, 0.84)
        end
    end

    for _, rule in ipairs(MATERIAL_RULES) do
        local matched, field, term = hasTerm(ctx, rule.terms, MATERIAL_FIELDS)
        if matched and not hasTag(tags, rule.tag) then
            tags[#tags + 1] = rule.tag
            addEvidence(result, rule.tag, field, term, 0.88)
        end
    end

    local insulation, insulationMeasured = measuredValue(ctx, "insulation", "insulationAvailable")
    local windResistance, windMeasured = measuredValue(ctx, "windResistance", "windResistanceAvailable")
    local waterResistance = number(ctx and ctx.waterResistance, nil)
    local clothingContext = isClothingContext(ctx)
    local winterInsulationThreshold = configuredPricingValue(
        "PriceThemeWinterMinInsulation", "clothingPricing",
        "winterMinInsulation", 0.75)
    local winterWindThreshold = configuredPricingValue(
        "PriceThemeWinterMinWindResistance", "clothingPricing",
        "winterMinWindResistance", 0.75)
    local winterByInsulation = insulationMeasured and insulation >= winterInsulationThreshold
    local winterByWind = windMeasured and windResistance >= winterWindThreshold
    if clothingContext and (winterByInsulation or winterByWind)
        and not hasTag(tags, "Theme.Winter")
    then
        local winterField = winterByInsulation and "insulation" or "windResistance"
        local winterValue = winterByInsulation and insulation or windResistance
        local winterThreshold = winterByInsulation
            and winterInsulationThreshold or winterWindThreshold
        tags[#tags + 1] = "Theme.Winter"
        addEvidence(result, "Theme.Winter", winterField,
            ">= " .. tostring(winterThreshold), 0.92, {
                value = winterValue,
                threshold = winterThreshold,
                operator = ">=",
                insulation = insulation,
                windResistance = windResistance,
                insulationThreshold = winterInsulationThreshold,
                windResistanceThreshold = winterWindThreshold,
            })
    end
    if clothingContext and (winterByInsulation or winterByWind)
        and not hasTag(tags, "Theme.Thermal")
    then
        tags[#tags + 1] = "Theme.Thermal"
        addEvidence(result, "Theme.Thermal", "numeric_clothing_protection",
            winterByInsulation
                and "insulation" or "windResistance", 0.92, {
                value = winterByInsulation and insulation or windResistance,
                threshold = winterByInsulation
                    and winterInsulationThreshold or winterWindThreshold,
                operator = ">=",
                insulation = insulation,
                windResistance = windResistance,
                insulationThreshold = winterInsulationThreshold,
                windResistanceThreshold = winterWindThreshold,
            })
    end

    local summerField, summerTerm = findTerm(ctx, SUMMER_TERMS, TEXT_FIELDS)
    local summerInsulationThreshold = configuredPricingValue(
        "PriceThemeSummerMaxInsulation", "clothingPricing",
        "summerMaxInsulation", 0.25)
    local summerWindThreshold = configuredPricingValue(
        "PriceThemeSummerMaxWindResistance", "clothingPricing",
        "summerMaxWindResistance", 0.25)
    local lowInsulation = insulationMeasured and insulation <= summerInsulationThreshold
    local lowWind = not windMeasured or windResistance <= summerWindThreshold
    local summerNumeric = clothingContext and lowInsulation and lowWind
    if clothingContext and (summerField ~= nil or summerNumeric)
        and not hasTag(tags, "Theme.Summer")
        and not hasTag(tags, "Theme.Winter")
        and not hasTag(tags, "Theme.Thermal")
    then
        tags[#tags + 1] = "Theme.Summer"
        if summerField ~= nil then
            addEvidence(result, "Theme.Summer", summerField, summerTerm, 0.91)
        else
            addEvidence(result, "Theme.Summer", "insulation", "<= " .. tostring(summerInsulationThreshold),
                0.90, {
                    value = insulation,
                    threshold = summerInsulationThreshold,
                    operator = "<=",
                    windResistance = windResistance,
                    windResistanceThreshold = summerWindThreshold,
                })
        end
    end

    local rainField, rainTerm = findTerm(ctx, RAIN_TERMS, TEXT_FIELDS)
    local rainThreshold = configuredPricingValue(
        "PriceThemeRainMinWaterResistance", "clothingPricing",
        "rainMinWaterResistance", 0.50)
    local rainNumeric = clothingContext and waterResistance ~= nil
        and waterResistance >= rainThreshold
    if rainField ~= nil or rainNumeric then
        if not hasTag(tags, "Theme.Rain") then
            tags[#tags + 1] = "Theme.Rain"
            if rainField ~= nil then
                addEvidence(result, "Theme.Rain", rainField, rainTerm, 0.91)
            else
                addEvidence(result, "Theme.Rain", "waterResistance",
                    ">= " .. tostring(rainThreshold), 0.92, {
                        value = waterResistance,
                        threshold = rainThreshold,
                        operator = ">=",
                    })
            end
        end
    end

    -- These seasonal overlays are based on the item's resolved taxonomy when
    -- available, then fall back to names/tags for workshop definitions that
    -- do not reach a specialized classifier. Generic weapons, ammo, or food
    -- are not treated as hunting/fishing goods without that evidence.
    local swimwearResultToken = findResultToken(result, SWIMWEAR_TOKENS)
    local swimwearContextToken = findContextToken(ctx, SWIMWEAR_TOKENS)
    local swimwearField, swimwearTerm = findTerm(ctx, SWIMWEAR_TERMS, TEXT_FIELDS)
    if swimwearResultToken ~= nil then
        addSignalTheme(result, tags, "Theme.Swimwear", "classification",
            swimwearResultToken, 0.96)
    elseif swimwearContextToken ~= nil then
        addSignalTheme(result, tags, "Theme.Swimwear", "script_tags",
            swimwearContextToken, 0.94)
    elseif swimwearField ~= nil then
        addSignalTheme(result, tags, "Theme.Swimwear", swimwearField,
            swimwearTerm, 0.91)
    end

    local growingResultToken = findResultToken(result, GROWING_TOKENS)
    local growingContextToken = findContextToken(ctx, GROWING_TOKENS)
    local growingCategory = tostring(ctx and ctx.displayCategoryToken or "")
    local growingItemType = tostring(ctx and ctx.itemTypeToken or "")
    local growingField, growingTerm = findTerm(ctx, GROWING_TERMS, TEXT_FIELDS)
    if growingResultToken ~= nil then
        addSignalTheme(result, tags, "Theme.GrowingSeason", "classification",
            growingResultToken, 0.97)
    elseif growingContextToken ~= nil then
        addSignalTheme(result, tags, "Theme.GrowingSeason", "script_tags",
            growingContextToken, 0.95)
    elseif growingCategory == "gardening" or growingCategory == "farming"
        or growingCategory == "agriculture" or growingItemType == "gardening"
        or growingItemType == "farming"
    then
        addSignalTheme(result, tags, "Theme.GrowingSeason", "displayCategory",
            growingCategory ~= "" and growingCategory or growingItemType, 0.93)
    elseif growingField ~= nil then
        addSignalTheme(result, tags, "Theme.GrowingSeason", growingField,
            growingTerm, 0.89)
    end

    local huntingResultToken = findResultToken(result, HUNTING_TOKENS)
    local huntingContextToken = findContextToken(ctx, HUNTING_TOKENS)
    local huntingCategory = tostring(ctx and ctx.displayCategoryToken or "")
    local huntingField, huntingTerm = findTerm(ctx, HUNTING_TERMS, TEXT_FIELDS)
    if huntingResultToken ~= nil then
        addSignalTheme(result, tags, "Theme.HuntingSeason", "classification",
            huntingResultToken, 0.97)
    elseif huntingContextToken ~= nil then
        addSignalTheme(result, tags, "Theme.HuntingSeason", "script_tags",
            huntingContextToken, 0.95)
    elseif huntingCategory == "hunting" or huntingCategory == "trapping"
    then
        addSignalTheme(result, tags, "Theme.HuntingSeason", "displayCategory",
            huntingCategory, 0.94)
    elseif huntingField ~= nil then
        addSignalTheme(result, tags, "Theme.HuntingSeason", huntingField,
            huntingTerm, 0.90)
    end

    local fishingResultToken = findResultToken(result, FISHING_TOKENS)
    local fishingContextToken = findContextToken(ctx, FISHING_TOKENS)
    local fishingCategory = tostring(ctx and ctx.displayCategoryToken or "")
    local fishingField, fishingTerm = findTerm(ctx, FISHING_TERMS, TEXT_FIELDS)
    if fishingResultToken ~= nil then
        addSignalTheme(result, tags, "Theme.FishingSeason", "classification",
            fishingResultToken, 0.97)
    elseif fishingContextToken ~= nil then
        addSignalTheme(result, tags, "Theme.FishingSeason", "script_tags",
            fishingContextToken, 0.95)
    elseif ctx and ctx.isFishingLure == true then
        addSignalTheme(result, tags, "Theme.FishingSeason", "isFishingLure",
            "true", 0.99)
    elseif fishingCategory == "fishing" then
        addSignalTheme(result, tags, "Theme.FishingSeason", "displayCategory",
            fishingCategory, 0.94)
    elseif fishingField ~= nil then
        addSignalTheme(result, tags, "Theme.FishingSeason", fishingField,
            fishingTerm, 0.90)
    end

    local holidayResultToken = findResultToken(result, HOLIDAY_TOKENS)
    local holidayContextToken = findContextToken(ctx, HOLIDAY_TOKENS)
    local holidayField, holidayTerm = findTerm(ctx, HOLIDAY_TERMS, TEXT_FIELDS)
    if holidayResultToken ~= nil then
        addSignalTheme(result, tags, "Theme.Holiday", "classification",
            holidayResultToken, 0.96)
    elseif holidayContextToken ~= nil then
        addSignalTheme(result, tags, "Theme.Holiday", "script_tags",
            holidayContextToken, 0.95)
    elseif holidayField ~= nil then
        addSignalTheme(result, tags, "Theme.Holiday", holidayField,
            holidayTerm, 0.90)
    end

    if isFoodContext(ctx) then
        -- These are intentionally total-per-item thresholds. The food price
        -- model already accounts for hunger/thirst/calorie magnitude; these
        -- facets provide small, configurable market distinctions and remain
        -- useful to other mods that do not use the full food model.
        addNumericTheme(ctx, result, tags, "Theme.HighCalorie", "calories",
            configuredThreshold("PriceThemeHighCalorieThreshold",
                "highCalorieThreshold", 300), 0.96)
        addNumericTheme(ctx, result, tags, "Theme.HighFat", "lipids",
            configuredThreshold("PriceThemeHighFatThreshold", "highFatThreshold", 20), 0.95)
        addNumericTheme(ctx, result, tags, "Theme.HighProtein", "proteins",
            configuredThreshold("PriceThemeHighProteinThreshold",
                "highProteinThreshold", 20), 0.95)
        addNumericTheme(ctx, result, tags, "Theme.HighCarbohydrate", "carbohydrates",
            configuredThreshold("PriceThemeHighCarbohydrateThreshold",
                "highCarbohydrateThreshold", 30), 0.95)

        local thirstChange = foodValue(ctx, "thirstChange")
        local hydrationThreshold = configuredThreshold("PriceThemeHydrationThreshold",
            "hydrationThreshold", 0.10)
        local thirstThreshold = configuredThreshold("PriceThemeThirstThreshold",
            "thirstThreshold", 0.10)
        if thirstChange ~= nil and thirstChange <= -hydrationThreshold
            and not hasTag(tags, "Theme.Hydrating")
        then
            tags[#tags + 1] = "Theme.Hydrating"
            addEvidence(result, "Theme.Hydrating", "thirstChange",
                "<= -" .. tostring(hydrationThreshold), 0.97, {
                    value = thirstChange, threshold = hydrationThreshold, operator = "<=",
                })
        elseif thirstChange ~= nil and thirstChange >= thirstThreshold
            and not hasTag(tags, "Theme.ThirstInducing")
        then
            tags[#tags + 1] = "Theme.ThirstInducing"
            addEvidence(result, "Theme.ThirstInducing", "thirstChange",
                ">= " .. tostring(thirstThreshold), 0.97, {
                    value = thirstChange, threshold = thirstThreshold, operator = ">=",
                })
        end
    end

    local communicationField, communicationTerm = nil, nil
    local deviceData = type(ctx and ctx.deviceData) == "table" and ctx.deviceData or nil
    local deviceAvailable = ctx and ctx.deviceDataAvailable == true or deviceData ~= nil
    if deviceAvailable then
        if deviceData and deviceData.isTwoWay == true then
            communicationField, communicationTerm = "deviceData.isTwoWay", "true"
        end
    else
        communicationField, communicationTerm = findTerm(ctx, COMMUNICATION_TERMS, TEXT_FIELDS)
    end
    if communicationField and not hasTag(tags, "Theme.Communication") then
        tags[#tags + 1] = "Theme.Communication"
        addEvidence(result, "Theme.Communication", communicationField,
            communicationTerm, deviceAvailable and 0.99 or 0.82)
    end

    result.tags = tags
    return result
end

return Filter
