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
    local text = table.concat({
        lower(context.fullType), lower(context.displayName), lower(context.description),
        lower(context.openingRecipe), lower(context.doubleClickRecipe),
        lower(context.replaceOnUse), lower(context.replaceOnUseOn),
        lower(context.replaceOnDeplete), lower(context.replaceOnCooked), lower(context.onCooked),
    }, " ")
    return context.isCannedFood == true
        or context.isPackaged == true
        or string.find(text, "canned", 1, true) ~= nil
        or string.find(text, "pickle", 1, true) ~= nil
        or string.find(text, "preserv", 1, true) ~= nil
        or string.find(text, "jar", 1, true) ~= nil
        or string.find(text, "opencannedfood", 1, true) ~= nil
end

local function isFood(context)
    local itemType = lower(context.itemTypeToken or context.itemType)
    local category = lower(context.displayCategory)
    return context.isFoodInstance == true
        or context.hasFoodNutritionEvidence == true
        or (context.foodTypeToken or "") ~= ""
        or string.find(itemType, "food", 1, true) ~= nil
        or string.find(category, "food", 1, true) ~= nil
        or isPackagedFood(context)
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

local function copyField(context, field, value, copied)
    if value == nil then return end
    context[field] = value
    if type(context.foodFacts) == "table" then
        context.foodFacts[field] = value
    end
    copied[#copied + 1] = field
end

local function mergeNutrition(context, variant, force)
    local copied = {}
    local conflicts = {}
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
                copyField(context, field.key, variantValue, copied)
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
                    copyField(context, field.magnitude, variantMagnitude, copied)
                end
            end
        end
    end

    if force and trim(variant.foodType) ~= "" then
        if trim(context.foodType) == "" or trim(context.foodType) ~= trim(variant.foodType) then
            if trim(context.foodType) ~= "" then
                conflicts[#conflicts + 1] = {
                    field = "foodType", base = context.foodType,
                    variant = variant.foodType,
                }
            end
            copyField(context, "foodType", variant.foodType, copied)
            context.foodTypeLower = lower(variant.foodType)
            context.foodTypeToken = string.gsub(lower(variant.foodType), "[^%w]", "")
        end
    end
    return copied, conflicts
end

local function candidateSummary(spec, context)
    return {
        fullType = spec.fullType,
        relation = spec.relation,
        priority = spec.priority,
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
    if type(existing) == "table"
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

    local force = isPackagedFood(context) or best.spec.relation == "recipe_output"
    local copied, conflicts = mergeNutrition(context, best.context, force)
    local evidence = {
        status = #copied > 0 and "verified" or "corroborated",
        sourceFullType = best.spec.fullType,
        relation = best.spec.relation,
        confidence = best.spec.relation == "recipe_output" and 1.0 or 0.90,
        applied = #copied > 0,
        fields = copied,
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
