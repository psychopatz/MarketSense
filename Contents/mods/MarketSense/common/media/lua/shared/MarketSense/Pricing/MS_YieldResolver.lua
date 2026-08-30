require "MarketSense/MS_Core"

MarketSense = MarketSense or {}
MarketSense.YieldResolver = MarketSense.YieldResolver or {}

local Resolver = MarketSense.YieldResolver
local Core = MarketSense.Core

local MAX_RECIPE_INPUTS = 1
local RESOLUTION_PRIORITY = {
    exact = 0,
    probabilistic = 1,
    ambiguous = 2,
    unresolved = 3,
}
local PACKAGING_NAME_MARKERS = {
    "open", "unpack", "unbundle", "unstack", "unbox",
    "slice", "halve", "split", "separate", "smash",
}

Resolver.VERSION = 2
Resolver.state = Resolver.state or {
    version = Resolver.VERSION,
    built = false,
    bySource = {},
    recipeCount = 0,
    sourceCount = 0,
    external = nil,
}

-- A PZ Lua reload can preserve the MarketSense table while replacing this
-- module.  Do not retain a recipe index built by the pre-collection adapter.
if Resolver.state.version ~= Resolver.VERSION then
    Resolver.state.version = Resolver.VERSION
    Resolver.state.built = false
    Resolver.state.bySource = {}
    Resolver.state.recipeCount = 0
    Resolver.state.sourceCount = 0
    Resolver.state.external = nil
end

local function trim(value)
    return Core.trim and Core.trim(value) or tostring(value or "")
end

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function callValue(object, methodName, ...)
    if object == nil or type(methodName) ~= "string" then return nil end
    local method = object[methodName]
    if type(method) ~= "function" then return nil end
    return method(object, ...)
end

local function eachValue(collection, callback)
    if collection == nil or type(callback) ~= "function" then return end
    Core.forEachCollection(collection, callback)
end

local function listValues(collection)
    local result = {}
    eachValue(collection, function(value)
        result[#result + 1] = value
    end)
    return result
end

local function fullTypeOf(item)
    if item == nil then return "" end
    local fullType = trim(callValue(item, "getFullName"))
    if fullType ~= "" then return fullType end

    local moduleName = trim(callValue(item, "getModuleName"))
    local typeName = trim(callValue(item, "getName"))
    if moduleName ~= "" and typeName ~= "" then
        return moduleName .. "." .. typeName
    end
    return ""
end

local function scriptFlags(script)
    local original = trim(callValue(script, "getOriginalLine"))
    local flags = {}
    local flagBlock = string.match(original, "flags%s*%[([^%]]+)%]")
    if flagBlock == nil then return flags end
    for flag in string.gmatch(flagBlock, "[^;,%s]+") do
        flags[#flags + 1] = flag
    end
    return flags
end

local function hasFlag(flags, wanted)
    wanted = lower(wanted)
    for _, flag in ipairs(flags or {}) do
        if lower(flag) == wanted then return true end
    end
    return false
end

local function addUnique(list, value)
    value = trim(value)
    if value == "" then return end
    for _, existing in ipairs(list) do
        if existing == value then return end
    end
    list[#list + 1] = value
end

local function mergeResolution(current, candidate)
    local currentPriority = RESOLUTION_PRIORITY[current] or 0
    local candidatePriority = RESOLUTION_PRIORITY[candidate] or 3
    return candidatePriority > currentPriority and candidate or current
end

local function copyOutputs(outputs)
    local result = {}
    for _, output in ipairs(outputs or {}) do
        result[#result + 1] = {
            fullType = output.fullType,
            quantity = output.quantity,
            chance = output.chance,
            inputFlags = Core.deepCopy(output.inputFlags or {}),
            outputFlags = Core.deepCopy(output.outputFlags or {}),
            possibleOutputs = Core.deepCopy(output.possibleOutputs or {}),
            maxQuantity = output.maxQuantity,
            resolution = output.resolution,
            inheritFoodAge = output.inheritFoodAge == true,
        }
    end
    return result
end

local function recipeName(recipe)
    return trim(callValue(recipe, "getName"))
end

local function recipeLooksLikeYield(name)
    local lowered = lower(name)
    for _, marker in ipairs(PACKAGING_NAME_MARKERS) do
        if string.find(lowered, marker, 1, true) then
            return true
        end
    end
    return false
end

local function collectionContainsFullType(collection, wanted)
    wanted = lower(wanted)
    local found = false
    eachValue(collection, function(item)
        if lower(fullTypeOf(item)) == wanted then found = true end
    end)
    return found
end

local function resultPatternMatchesSource(mapper, resultItem, sourceFullType)
    if mapper == nil then return false, false end
    local pattern = callValue(mapper, "getPatternForResult", resultItem)
    local patternItems = listValues(pattern)
    if #patternItems == 0 then
        return false, false
    end
    return collectionContainsFullType(patternItems, sourceFullType), true
end

local function resolveOutputForSource(output, sourceFullType)
    local possible = listValues(callValue(output, "getPossibleResultItems"))
    local possibleTypes = {}
    for _, item in ipairs(possible) do
        addUnique(possibleTypes, fullTypeOf(item))
    end

    local mapper = callValue(output, "getOutputMapper")
    local mappedTypes = {}
    local hadPatterns = false
    for _, item in ipairs(possible) do
        local matches, hasPattern = resultPatternMatchesSource(mapper, item, sourceFullType)
        hadPatterns = hadPatterns or hasPattern
        if matches then addUnique(mappedTypes, fullTypeOf(item)) end
    end

    local amount = tonumber(callValue(output, "getAmount")) or 0
    local maxAmount = tonumber(callValue(output, "getMaxAmount")) or amount
    local chance = tonumber(callValue(output, "getChance"))
    if chance == nil then chance = 1.0 end
    local base = {
        quantity = amount,
        maxQuantity = maxAmount,
        chance = chance,
        outputFlags = scriptFlags(output),
    }
    base.inheritFoodAge = hasFlag(base.outputFlags, "InheritFoodAge")

    if hadPatterns then
        if #mappedTypes == 1 then
            base.fullType = mappedTypes[1]
            base.resolution = maxAmount ~= amount and "unresolved"
                or chance < 1.0 and "probabilistic" or "exact"
            return base
        end
        base.possibleOutputs = possibleTypes
        base.resolution = #mappedTypes > 1 and "ambiguous" or "unresolved"
        return base
    end

    if #possibleTypes == 1 then
        base.fullType = possibleTypes[1]
        base.resolution = maxAmount ~= amount and "unresolved"
            or chance < 1.0 and "probabilistic" or "exact"
        return base
    end

    base.possibleOutputs = possibleTypes
    base.resolution = #possibleTypes > 1 and "ambiguous" or "unresolved"
    return base
end

local function buildRecipeRecord(recipe, sourceFullType, inputScript, outputs)
    local inputAmount = tonumber(callValue(inputScript, "getAmount", sourceFullType))
    if inputAmount == nil then inputAmount = tonumber(callValue(inputScript, "getAmount")) end
    if inputAmount == nil then inputAmount = 1.0 end
    local inputMaxAmount = tonumber(
        callValue(inputScript, "getMaxAmount", sourceFullType)
    )
    if inputMaxAmount == nil then
        inputMaxAmount = tonumber(callValue(inputScript, "getMaxAmount"))
    end
    if inputMaxAmount == nil then inputMaxAmount = inputAmount end
    local inputFlags = scriptFlags(inputScript)
    local inheritFoodAge = hasFlag(inputFlags, "InheritFoodAge")
    for _, output in ipairs(outputs) do
        output.inputFlags = Core.deepCopy(inputFlags)
        output.inheritFoodAge = output.inheritFoodAge == true or inheritFoodAge
    end

    local record = {
        recipe = recipeName(recipe),
        source = "runtime_craft_recipe",
        sourceFullType = sourceFullType,
        inputAmount = inputAmount,
        inputMaxAmount = inputMaxAmount,
        inputVariable = inputMaxAmount ~= inputAmount,
        inputCount = 1,
        outputs = outputs,
        candidateMethod = recipeLooksLikeYield(recipeName(recipe)) and "recipe_name" or "recipe_graph",
        resolution = "exact",
    }

    for _, output in ipairs(outputs) do
        local outputResolution = output.resolution
            or (output.fullType and "exact" or "unresolved")
        if outputResolution ~= "exact" then
            record.resolution = mergeResolution(record.resolution, outputResolution)
        elseif tonumber(output.maxQuantity) ~= nil
            and tonumber(output.quantity) ~= tonumber(output.maxQuantity) then
            record.resolution = "unresolved"
        elseif tonumber(output.quantity) == nil or tonumber(output.quantity) <= 0 then
            record.resolution = "unresolved"
        end
    end
    if #outputs == 0 then record.resolution = "unresolved" end
    return record
end

local function recipeManager()
    local manager = nil
    if type(getScriptManager) == "function" then
        manager = getScriptManager()
    end
    if manager == nil and ScriptManager and ScriptManager.instance then
        manager = ScriptManager.instance
    end
    return manager
end

local function buildRecordForSource(recipe, sourceFullType)
    local inputs = listValues(callValue(recipe, "getInputs"))
    if #inputs ~= MAX_RECIPE_INPUTS then return nil end

    local inputScript = inputs[1]
    local inputItems = listValues(callValue(inputScript, "getPossibleInputItems"))
    if not collectionContainsFullType(inputItems, sourceFullType) then
        return nil
    end

    local outputScripts = listValues(callValue(recipe, "getOutputs"))
    local outputs = {}
    for _, outputScript in ipairs(outputScripts) do
        local output = resolveOutputForSource(outputScript, sourceFullType)
        if output.fullType ~= nil or output.resolution ~= "unresolved" then
            outputs[#outputs + 1] = output
        end
    end
    return buildRecipeRecord(recipe, sourceFullType, inputScript, outputs)
end

local function buildRuntimeIndex()
    local index = {}
    local manager = recipeManager()
    if manager == nil then return index, 0, 0 end

    local recipes = callValue(manager, "getAllCraftRecipes")
    local recipeCount = 0
    local sourceCount = 0
    eachValue(recipes, function(recipe)
        recipeCount = recipeCount + 1
        local inputs = listValues(callValue(recipe, "getInputs"))
        if #inputs ~= MAX_RECIPE_INPUTS then return end

        local inputItems = listValues(callValue(inputs[1], "getPossibleInputItems"))
        for _, inputItem in ipairs(inputItems) do
            local sourceFullType = fullTypeOf(inputItem)
            if sourceFullType ~= "" then
                local record = buildRecordForSource(recipe, sourceFullType)
                index[sourceFullType] = index[sourceFullType] or {}
                index[sourceFullType][#index[sourceFullType] + 1] = record
                sourceCount = sourceCount + 1
            end
        end
    end)
    return index, recipeCount, sourceCount
end

local function looksLikePackagedSource(fullType)
    local lowered = lower(fullType)
    return string.find(lowered, "box", 1, true) ~= nil
        or string.find(lowered, "carton", 1, true) ~= nil
        or string.find(lowered, "pack", 1, true) ~= nil
        or string.find(lowered, "bundle", 1, true) ~= nil
        or string.find(lowered, "case", 1, true) ~= nil
end

local function discoverSourceRecords(fullType, ctx)
    local manager = recipeManager()
    if manager == nil then return {} end

    local records = {}
    local names = {}
    if ctx and ctx.doubleClickRecipe then
        names[#names + 1] = ctx.doubleClickRecipe
    end
    if ctx and ctx.openingRecipe then
        names[#names + 1] = ctx.openingRecipe
    end
    local seenRecipes = {}
    for _, name in ipairs(names) do
        name = trim(name)
        if name ~= "" and not seenRecipes[lower(name)] then
            seenRecipes[lower(name)] = true
            local recipe = callValue(manager, "getCraftRecipe", name)
            if recipe then
                local record = buildRecordForSource(recipe, fullType)
                if record then records[#records + 1] = record end
            end
        end
    end

    if #records > 0 or not looksLikePackagedSource(fullType) then
        return records
    end

    -- A recipe may be a generic carton/box opener without an item-side
    -- DoubleClickRecipe property (EggCarton is the vanilla example).  Retry
    -- only for packaging-shaped sources so normal food lookups do not scan
    -- the complete recipe list repeatedly after an early empty build.
    local recipes = callValue(manager, "getAllCraftRecipes")
    eachValue(recipes, function(recipe)
        local record = buildRecordForSource(recipe, fullType)
        if record then records[#records + 1] = record end
    end)
    return records
end

local function pointerMatches(ctx, recipe)
    local name = lower(recipe)
    return name ~= "" and (
        lower(ctx.doubleClickRecipe or "") == name
        or lower(ctx.openingRecipe or "") == name
    )
end

local function copyCandidate(record, ctx)
    local candidate = Core.deepCopy(record)
    local explicit = pointerMatches(ctx, record.recipe)
    candidate.candidateMethod = explicit and "explicit_property"
        or (recipeLooksLikeYield(record.recipe) and "recipe_name" or "recipe_graph")
    candidate.explicit = explicit
    candidate.nameHeuristic = recipeLooksLikeYield(record.recipe)
    return candidate
end

local function externalRecords(fullType)
    local records = Resolver.state.external and Resolver.state.external[fullType]
    if records ~= nil then return records end
    if Resolver.state.external then
        for source, entries in pairs(Resolver.state.external) do
            if lower(source) == lower(fullType) then return entries end
        end
    end
    return nil
end

function Resolver.setRecipeIndex(index)
    Resolver.state.external = type(index) == "table" and index or {}
    Resolver.state.bySource = Resolver.state.external
    local indexedRecords = 0
    for _, records in pairs(Resolver.state.external) do
        if type(records) == "table" then
            indexedRecords = indexedRecords + #records
        end
    end
    Resolver.state.recipeCount = indexedRecords
    Resolver.state.sourceCount = indexedRecords
    Resolver.state.built = true
end

function Resolver.clear()
    Resolver.state.built = false
    Resolver.state.bySource = {}
    Resolver.state.recipeCount = 0
    Resolver.state.sourceCount = 0
    Resolver.state.external = nil
end

local function ensureIndex()
    if Resolver.state.built then return end
    local index, recipeCount, sourceCount = buildRuntimeIndex()
    Resolver.state.bySource = index
    Resolver.state.recipeCount = recipeCount
    Resolver.state.sourceCount = sourceCount
    Resolver.state.built = true
end

function Resolver.resolve(ctx)
    ctx = ctx or {}
    local fullType = trim(ctx.fullType)
    if fullType == "" then
        return {
            status = "not_detected",
            resolution = "none",
            sourceFullType = fullType,
            candidates = {},
            candidateCount = 0,
            recipeCount = Resolver.state.recipeCount,
            sourceCount = Resolver.state.sourceCount,
        }
    end

    ensureIndex()
    local records = externalRecords(fullType) or Resolver.state.bySource[fullType] or {}
    if #records == 0 and Resolver.state.external == nil then
        records = discoverSourceRecords(fullType, ctx)
        if #records > 0 then
            Resolver.state.bySource[fullType] = records
            Resolver.state.sourceCount = Resolver.state.sourceCount + 1
        end
    end
    local candidates = {}
    for _, record in ipairs(records) do
        local inputAmount = tonumber(record.inputAmount) or 1.0
        local inputMaxAmount = tonumber(record.inputMaxAmount) or inputAmount
        local inputCount = tonumber(record.inputCount) or MAX_RECIPE_INPUTS
        local inputVariable = record.inputVariable == true
        local explicit = pointerMatches(ctx, record.recipe)
        local named = record.nameHeuristic == true or recipeLooksLikeYield(record.recipe)
        if inputCount <= MAX_RECIPE_INPUTS and inputAmount >= 1.0
            and inputMaxAmount <= 1.0 and not inputVariable
            and (explicit or named) then
            candidates[#candidates + 1] = copyCandidate(record, ctx)
        end
    end

    if #candidates == 0 then
        return {
            status = "not_detected",
            resolution = "none",
            sourceFullType = fullType,
            candidates = {},
            candidateCount = 0,
            recipeCount = Resolver.state.recipeCount,
            sourceCount = Resolver.state.sourceCount,
        }
    end

    local explicitCandidates = {}
    for _, candidate in ipairs(candidates) do
        if candidate.explicit then explicitCandidates[#explicitCandidates + 1] = candidate end
    end
    local selected = #explicitCandidates > 0 and explicitCandidates or candidates
    local chosen = #selected == 1 and selected[1] or nil
    local status = "ambiguous"
    local resolution = "ambiguous"
    local outputs = {}
    if chosen then
        resolution = chosen.resolution or "unresolved"
        status = resolution == "exact" and "resolved" or resolution
        if status == "resolved" then outputs = copyOutputs(chosen.outputs) end
    end

    return {
        status = status,
        resolution = resolution,
        sourceFullType = fullType,
        recipe = chosen and chosen.recipe or nil,
        source = chosen and chosen.source or nil,
        candidateMethod = chosen and chosen.candidateMethod or nil,
        explicit = chosen and chosen.explicit == true or false,
        nameHeuristic = chosen and chosen.nameHeuristic == true or false,
        outputs = outputs,
        candidates = candidates,
        candidateCount = #candidates,
        recipeCount = Resolver.state.recipeCount,
        sourceCount = Resolver.state.sourceCount,
    }
end

function Resolver.getStats()
    ensureIndex()
    return {
        version = Resolver.VERSION,
        recipeCount = Resolver.state.recipeCount,
        sourceCount = Resolver.state.sourceCount,
        external = Resolver.state.external ~= nil,
    }
end

return Resolver
