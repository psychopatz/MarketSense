require "MarketSense/MS_Core"

MarketSense = MarketSense or {}
MarketSense.FoodVariantEvidence = MarketSense.FoodVariantEvidence or {}

local Evidence = MarketSense.FoodVariantEvidence
local Core = MarketSense.Core

local OPEN_SUFFIXES = { "Open", "_Open", "Opened", "_Opened" }
local REFERENCE_FIELDS = {
    "replaceOnCooked", "onCooked", "replaceOnUse", "replaceOnUseOn", "replaceOnDeplete",
}
local VALUE_FIELDS = {
    { key = "hungerChange", magnitude = "hunger" },
    { key = "thirstChange", magnitude = "thirst" },
    { key = "unhappyChange", magnitude = "unhappy" },
    { key = "boredomChange", magnitude = "boredom" },
    { key = "stressChange", magnitude = "stress" },
    { key = "calories" },
    { key = "carbohydrates" },
    { key = "lipids" },
    { key = "proteins" },
}

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function trim(value)
    return Core.trim and Core.trim(value) or tostring(value or "")
end

local function isFoodItem(context)
    local itemType = lower(context.itemTypeToken or context.itemType)
    local category = lower(context.displayCategory)
    return context.isFoodInstance == true
        or context.hasFoodNutritionEvidence == true
        or trim(context.foodTypeToken or context.foodType) ~= ""
        or string.find(itemType, "food", 1, true) ~= nil
        or string.find(category, "food", 1, true) ~= nil
end

local function hasTag(context, marker)
    marker = lower(marker)
    for _, tag in ipairs(context.normalizedTagList or {}) do
        if lower(tag) == marker then return true end
    end
    for _, tag in ipairs(context.tags or {}) do
        local normalized = string.gsub(lower(tag), "[^%w]", "")
        if normalized == marker then return true end
    end
    return false
end

local function endsWith(value, suffix)
    return string.sub(value, -#suffix) == suffix
end

local function isOpenVariant(fullType)
    local _, typeName = Core.splitFullType(fullType)
    local lowered = lower(typeName)
    return endsWith(lowered, "open") or endsWith(lowered, "opened")
end

local function hasNutrition(context)
    for _, field in ipairs(VALUE_FIELDS) do
        if math.abs(tonumber(context[field.key]) or 0) > 0 then
            return true
        end
    end
    return false
end

local function isPackagedFood(context)
    local hasDefinitionRelation = trim(context.openingRecipe) ~= ""
        or trim(context.doubleClickRecipe) ~= ""
        or trim(context.replaceOnUse) ~= ""
        or trim(context.replaceOnUseOn) ~= ""
        or trim(context.replaceOnDeplete) ~= ""
        or trim(context.replaceOnCooked) ~= ""
        or trim(context.onCooked) ~= ""
    local canonicalPreservedTag = hasTag(context, "preservedfood")
        or hasTag(context, "pickledfood")
        or hasTag(context, "foodpreserved")
    local foodName = table.concat({
        lower(context.fullType), lower(context.displayName),
    }, " ")
    local namedFoodPackage = isFoodItem(context)
        and (string.find(foodName, "canned", 1, true) ~= nil
            or string.find(foodName, "pickle", 1, true) ~= nil
            or string.find(foodName, "preserv", 1, true) ~= nil)
    return context.isCannedFood == true
        or context.isPackaged == true
        or canonicalPreservedTag
        or hasDefinitionRelation
        or namedFoodPackage
end

local function isFood(context)
    return isFoodItem(context)
end

local function addCandidate(candidates, seen, fullType, relation, priority)
    fullType = trim(fullType)
    if fullType == "" or lower(fullType) == lower(candidates.sourceFullType)
        or seen[lower(fullType)] then
        return
    end
    seen[lower(fullType)] = true
    candidates[#candidates + 1] = {
        fullType = fullType,
        relation = relation,
        priority = priority,
    }
end

local function candidateSpecs(context, yieldInfo)
    local result = { sourceFullType = context.fullType }
    local seen = {}
    for _, output in ipairs(yieldInfo and yieldInfo.outputs or {}) do
        local fullType = output and output.fullType
        if fullType and isOpenVariant(fullType) then
            addCandidate(result, seen, fullType, "recipe_output", 100)
        end
    end

    for _, fieldName in ipairs(REFERENCE_FIELDS) do
        local value = tostring(context[fieldName] or "")
        for fullType in string.gmatch(value, "[%w_]+%.[%w_]+") do
            if isOpenVariant(fullType) then
                addCandidate(result, seen, fullType, "definition_reference", 95)
            end
        end
        if string.match(value, "^[%w_]+$") and isOpenVariant(value) then
            local moduleName = select(1, Core.splitFullType(context.fullType))
            addCandidate(result, seen, moduleName .. "." .. value,
                "definition_reference", 95)
        end
    end

    local moduleName, typeName = Core.splitFullType(context.fullType)
    if not isOpenVariant(context.fullType) then
        for _, suffix in ipairs(OPEN_SUFFIXES) do
            addCandidate(result, seen, moduleName .. "." .. typeName .. suffix,
                "name_open_suffix", 80)
        end
    end
    return result
end

local function nutritionStrength(context)
    local count = 0
    for _, field in ipairs(VALUE_FIELDS) do
        if math.abs(tonumber(context[field.key]) or 0) > 0 then
            count = count + 1
        end
    end
    return count
end

local function different(left, right)
    return math.abs((tonumber(left) or 0) - (tonumber(right) or 0)) > 0.0001
end

local function copyField(context, field, value, copied, sources, sourceFullType)
    if value == nil then return end
    context[field] = value
    if type(context.foodFacts) == "table" then
        context.foodFacts[field] = value
    end
    copied[#copied + 1] = field
    sources[field] = sourceFullType
end

local function mergeNutrition(context, variant, force)
    local copied = {}
    local conflicts = {}
    local sources = {}
    for _, field in ipairs(VALUE_FIELDS) do
        local variantValue = tonumber(variant[field.key])
        local baseValue = tonumber(context[field.key])
        if variantValue ~= nil and variantValue ~= 0 then
            if baseValue ~= nil and baseValue ~= 0 and different(baseValue, variantValue) then
                conflicts[#conflicts + 1] = {
                    field = field.key, base = baseValue, variant = variantValue,
                }
            end
            if force or baseValue == nil or baseValue == 0 then
                copyField(context, field.key, variantValue, copied, sources,
                    variant.fullType)
            end
        end

        if field.magnitude then
            local variantMagnitude = tonumber(variant[field.magnitude])
            if variantMagnitude == nil and variantValue ~= nil then
                variantMagnitude = math.abs(variantValue)
            end
            local baseMagnitude = tonumber(context[field.magnitude])
            if variantMagnitude ~= nil and variantMagnitude ~= 0 then
                if baseMagnitude ~= nil and baseMagnitude ~= 0
                    and different(baseMagnitude, variantMagnitude)
                then
                    conflicts[#conflicts + 1] = {
                        field = field.magnitude, base = baseMagnitude,
                        variant = variantMagnitude,
                    }
                end
                if force or baseMagnitude == nil or baseMagnitude == 0 then
                    copyField(context, field.magnitude, variantMagnitude, copied,
                        sources, variant.fullType)
                end
            end
        end
    end

    if trim(variant.foodType) ~= ""
        and (force or trim(context.foodType) == "")
    then
        if force and trim(context.foodType) ~= ""
            and trim(context.foodType) ~= trim(variant.foodType)
        then
            conflicts[#conflicts + 1] = {
                field = "foodType", base = context.foodType,
                variant = variant.foodType,
            }
        end
        copyField(context, "foodType", variant.foodType, copied, sources,
            variant.fullType)
        context.foodTypeLower = lower(variant.foodType)
        context.foodTypeToken = string.gsub(lower(variant.foodType), "[^%w]", "")
    end
    return copied, conflicts, sources
end

local function candidateSummary(spec, context)
    return {
        fullType = spec.fullType,
        relation = spec.relation,
        priority = spec.priority,
        authority = spec.relation == "recipe_output" and "recipe_output"
            or spec.relation == "definition_reference" and "definition_reference"
            or "name_hint",
        nutritionFields = nutritionStrength(context),
        hidden = context.isHidden == true,
        obsolete = context.isObsolete == true,
    }
end

local function hasOpenYieldOutput(yieldInfo)
    for _, output in ipairs(yieldInfo and yieldInfo.outputs or {}) do
        if output and isOpenVariant(output.fullType) then
            return true
        end
    end
    return false
end

function Evidence.apply(context, buildContext, yieldInfo)
    if type(context) ~= "table" then return context end
    if isOpenVariant(context.fullType) then
        -- The opened definition is the edible source of truth, but its
        -- condition is worse than the sealed package. Keep this state on the
        -- context so pricing can apply the opened-food penalty even when the
        -- item has no live inventory age yet.
        context.isOpenedFood = true
        context.foodConditionState = "opened"
        context.foodVariantEvidence = { status = "not_applicable" }
        return context
    end
    if not isFood(context) or not isPackagedFood(context) then
        return context
    end
    if type(buildContext) ~= "function" then return context end

    -- Context construction runs before recipe resolution. Revisit only when
    -- pricing later gives us an exact open-output candidate; otherwise a
    -- cached not-detected/heuristic result is already complete.
    local existing = context.foodVariantEvidence
    local hasRecipeOutput = hasOpenYieldOutput(yieldInfo)
    if type(existing) == "table" and existing.status ~= "not_detected"
        and (existing.relation == "recipe_output" or not hasRecipeOutput)
    then
        return context
    end

    local specs = candidateSpecs(context, yieldInfo)
    local best = nil
    local summaries = {}
    for _, spec in ipairs(specs) do
        local candidate = buildContext(spec.fullType, nil, true)
        if type(candidate) == "table" and isFood(candidate)
            and hasNutrition(candidate)
            and (spec.relation ~= "name_open_suffix" or candidate.isObsolete ~= true)
        then
            local strength = nutritionStrength(candidate)
            local score = (spec.priority * 100) + strength
            summaries[#summaries + 1] = candidateSummary(spec, candidate)
            if best == nil or score > best.score then
                best = { spec = spec, context = candidate, score = score }
            end
        end
    end

    if best == nil then
        if existing == nil then
            context.foodVariantEvidence = {
                status = "not_detected",
                candidates = summaries,
            }
        end
        return context
    end

    -- Explicit recipe/replacement metadata is authoritative for a sealed
    -- package's edible form. A name-only suffix is only a fill-in hint and
    -- never overwrites non-zero parent metadata.
    local force = best.spec.relation == "recipe_output"
        or best.spec.relation == "definition_reference"
    local copied, conflicts, fieldSources = mergeNutrition(context, best.context, force)
    local evidence = {
        status = #copied > 0 and "verified" or "corroborated",
        sourceFullType = best.spec.fullType,
        relation = best.spec.relation,
        authority = best.spec.relation == "recipe_output" and "recipe_output"
            or best.spec.relation == "definition_reference" and "definition_reference"
            or "name_hint",
        confidence = best.spec.relation == "recipe_output" and 1.0
            or best.spec.relation == "definition_reference" and 0.95 or 0.75,
        applied = #copied > 0,
        fields = copied,
        fieldSources = fieldSources,
        conflicts = conflicts,
        candidates = summaries,
    }
    context.foodVariantEvidence = evidence
    if #copied > 0 then
        context.hasFoodNutritionEvidence = true
        if type(context.foodFactTrace) == "table" then
            context.foodFactTrace.hasFoodNutritionEvidence = true
            context.foodFactTrace.foodVariantSource = best.spec.fullType
            context.foodFactTrace.foodVariantFields = Core.deepCopy(copied)
        end
    end
    return context
end

return Evidence
