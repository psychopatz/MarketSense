require "MarketSense/MS_Core"

MarketSense = MarketSense or {}
MarketSense.ToolRecipeDemand = MarketSense.ToolRecipeDemand or {}

local Demand = MarketSense.ToolRecipeDemand
local Core = MarketSense.Core

-- Recipe demand is an independent evidence index.  It is built once from the
-- engine's resolved possible-input lists, then queried by full item type.  A
-- tool accepted by a tag selector (for example base:hammer) therefore gets
-- the same evidence as an explicitly listed item, including Workshop items.
Demand.VERSION = 1
Demand.state = Demand.state or {
    version = Demand.VERSION,
    built = false,
    bySource = {},
    recipeCount = 0,
    sourceCount = 0,
    external = nil,
}

if Demand.state.version ~= Demand.VERSION then
    Demand.state.version = Demand.VERSION
    Demand.state.built = false
    Demand.state.bySource = {}
    Demand.state.recipeCount = 0
    Demand.state.sourceCount = 0
    Demand.state.external = nil
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

local function listValues(collection)
    local result = {}
    Core.forEachCollection(collection, function(value)
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

local function scriptFlags(inputScript)
    local original = trim(callValue(inputScript, "getOriginalLine"))
    local flags = {}
    local flagBlock = string.match(original, "flags%s*%[([^%]]+)%]")
    if flagBlock == nil then return flags end
    for flag in string.gmatch(flagBlock, "[^;,%s]+") do
        flags[#flags + 1] = flag
    end
    return flags
end

local function containsIgnoreCase(values, wanted)
    wanted = lower(wanted)
    for _, value in ipairs(values or {}) do
        if lower(value) == wanted then return true end
    end
    return false
end

local function inputMode(inputScript)
    if callValue(inputScript, "isKeep") == true then return "keep" end
    if callValue(inputScript, "isDestroy") == true then return "destroy" end
    return "use"
end

local function buildRecord(
    recipe, inputScript, inputIndex, inputCount, sourceFullType
)
    local flags = scriptFlags(inputScript)
    local toolFlag = callValue(inputScript, "isTool") == true
        or callValue(inputScript, "isToolLeft") == true
        or callValue(inputScript, "isToolRight") == true
        or containsIgnoreCase(flags, "toolleft")
        or containsIgnoreCase(flags, "toolright")
    local mode = inputMode(inputScript)
    local outputs = listValues(callValue(recipe, "getOutputs"))
    local original = trim(callValue(inputScript, "getOriginalLine"))
    local selectorKind = string.find(lower(original), "tags[", 1, true)
        and "tags" or "items"
    local inputAmount
    local inputMaxAmount
    if selectorKind == "items" and sourceFullType ~= "" then
        -- Item-specific amounts (for example [2:Base.Nails;1:Base.Screw])
        -- are exposed by the String overload. Tag selectors have no concrete
        -- item entry, so use the no-argument base amount for those.
        inputAmount = tonumber(callValue(
            inputScript, "getAmount", sourceFullType
        ))
        inputMaxAmount = tonumber(callValue(
            inputScript, "getMaxAmount", sourceFullType
        ))
    else
        inputAmount = tonumber(callValue(inputScript, "getAmount"))
        inputMaxAmount = tonumber(callValue(inputScript, "getMaxAmount"))
    end
    local record = {
        recipe = trim(callValue(recipe, "getName")),
        module = trim(callValue(recipe, "getModID")),
        source = "runtime_recipe_demand",
        inputIndex = inputIndex,
        inputCount = inputCount,
        inputAmount = inputAmount or 1.0,
        inputMaxAmount = inputMaxAmount or inputAmount or 1.0,
        mode = mode,
        flags = flags,
        toolFlag = toolFlag,
        reusable = mode == "keep" or toolFlag,
        selectorKind = selectorKind,
        outputCount = #outputs,
        recipeCategory = trim(callValue(recipe, "getCategory")),
    }
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

local function appendRecord(index, fullType, record)
    if fullType == "" then return 0 end
    index[fullType] = index[fullType] or {}
    index[fullType][#index[fullType] + 1] = record
    return 1
end

local function buildRuntimeIndex()
    local index = {}
    local manager = recipeManager()
    if manager == nil then return index, 0, 0 end

    local recipes = callValue(manager, "getAllCraftRecipes")
    local recipeCount = 0
    local sourceCount = 0
    Core.forEachCollection(recipes, function(recipe)
        recipeCount = recipeCount + 1
        local inputs = listValues(callValue(recipe, "getInputs"))
        for inputIndex, inputScript in ipairs(inputs) do
            local possibleItems = listValues(
                callValue(inputScript, "getPossibleInputItems")
            )
            if #possibleItems > 0 then
                for _, inputItem in ipairs(possibleItems) do
                    local sourceFullType = fullTypeOf(inputItem)
                    local record = buildRecord(
                        recipe, inputScript, inputIndex, #inputs, sourceFullType
                    )
                    sourceCount = sourceCount + appendRecord(
                        index, sourceFullType, record
                    )
                end
            end
        end
    end)
    return index, recipeCount, sourceCount
end

local function externalRecords(fullType)
    local records = Demand.state.external and Demand.state.external[fullType]
    if records ~= nil then return records end
    if Demand.state.external then
        for source, entries in pairs(Demand.state.external) do
            if lower(source) == lower(fullType) then return entries end
        end
    end
    return nil
end

local function emptyResult(fullType)
    return {
        status = "not_detected",
        sourceFullType = fullType,
        recipeCount = 0,
        reusableRecipeCount = 0,
        consumedRecipeCount = 0,
        matchingInputCount = 0,
        reusableInputCount = 0,
        consumedInputCount = 0,
        totalInputAmount = 0,
        reusableInputAmount = 0,
        toolFlagRecipeCount = 0,
        recipeDemandScore = 0,
        criticality = "none",
        recipes = {},
    }
end

local function boundedLog(value, scale)
    value = math.max(0, tonumber(value) or 0)
    scale = math.max(1, tonumber(scale) or 1)
    return math.min(1, math.log(1 + value) / math.log(1 + scale))
end

local function demandScore(reusableRecipes, reusableInputs, toolFlagRecipes)
    -- Diminishing returns keep a very broad tag from making price grow
    -- linearly forever.  The reusable recipe count carries most of the
    -- signal; input count and explicit engine tool flags break ties.
    local breadth = boundedLog(reusableRecipes, 48)
    local inputBreadth = boundedLog(reusableInputs, 72)
    local toolBreadth = boundedLog(toolFlagRecipes, 24)
    return math.min(1, 0.65 * breadth + 0.25 * inputBreadth + 0.10 * toolBreadth)
end

local function classify(score)
    if score >= 0.75 then return "high" end
    if score >= 0.40 then return "medium" end
    if score > 0 then return "low" end
    return "none"
end

function Demand.setRecipeIndex(index)
    Demand.state.external = type(index) == "table" and index or {}
    Demand.state.bySource = Demand.state.external
    local recipes = {}
    local sourceCount = 0
    for _, records in pairs(Demand.state.external) do
        if type(records) == "table" then
            sourceCount = sourceCount + #records
            for _, record in ipairs(records) do
                local key = lower(record.recipe)
                if key ~= "" then recipes[key] = true end
            end
        end
    end
    local recipeCount = 0
    for _ in pairs(recipes) do recipeCount = recipeCount + 1 end
    Demand.state.recipeCount = recipeCount
    Demand.state.sourceCount = sourceCount
    Demand.state.built = true
end

function Demand.clear()
    Demand.state.built = false
    Demand.state.bySource = {}
    Demand.state.recipeCount = 0
    Demand.state.sourceCount = 0
    Demand.state.external = nil
end

local function ensureIndex()
    if Demand.state.built then return end
    local index, recipeCount, sourceCount = buildRuntimeIndex()
    Demand.state.bySource = index
    Demand.state.recipeCount = recipeCount
    Demand.state.sourceCount = sourceCount
    Demand.state.built = true
end

function Demand.resolve(ctx)
    ctx = ctx or {}
    local fullType = trim(ctx.fullType)
    if fullType == "" then return emptyResult(fullType) end

    ensureIndex()
    local records = externalRecords(fullType) or Demand.state.bySource[fullType]
    if type(records) ~= "table" or #records == 0 then
        return emptyResult(fullType)
    end

    local result = emptyResult(fullType)
    result.status = "resolved"
    local seenRecipes = {}
    local reusableRecipes = {}
    local consumedRecipes = {}
    local toolFlagRecipes = {}
    for _, record in ipairs(records) do
        local recipe = trim(record.recipe)
        local recipeKey = lower(recipe)
        if recipeKey ~= "" and not seenRecipes[recipeKey] then
            seenRecipes[recipeKey] = true
            result.recipeCount = result.recipeCount + 1
        end
        result.matchingInputCount = result.matchingInputCount + 1
        local amount = math.max(0, tonumber(record.inputAmount) or 1)
        result.totalInputAmount = result.totalInputAmount + amount
        if record.reusable == true then
            result.reusableInputCount = result.reusableInputCount + 1
            result.reusableInputAmount = result.reusableInputAmount + amount
            if recipeKey ~= "" then reusableRecipes[recipeKey] = true end
        else
            result.consumedInputCount = result.consumedInputCount + 1
            if recipeKey ~= "" then consumedRecipes[recipeKey] = true end
        end
        if record.toolFlag == true and recipeKey ~= "" then
            toolFlagRecipes[recipeKey] = true
        end
    end
    for _ in pairs(reusableRecipes) do result.reusableRecipeCount = result.reusableRecipeCount + 1 end
    for _ in pairs(consumedRecipes) do result.consumedRecipeCount = result.consumedRecipeCount + 1 end
    for _ in pairs(toolFlagRecipes) do result.toolFlagRecipeCount = result.toolFlagRecipeCount + 1 end
    result.recipeDemandScore = demandScore(
        result.reusableRecipeCount,
        result.reusableInputCount,
        result.toolFlagRecipeCount
    )
    result.criticality = classify(result.recipeDemandScore)
    result.recipes = Core.deepCopy(records)
    return result
end

function Demand.getStats()
    ensureIndex()
    return {
        version = Demand.VERSION,
        recipeCount = Demand.state.recipeCount,
        sourceCount = Demand.state.sourceCount,
        external = Demand.state.external ~= nil,
    }
end

return Demand
