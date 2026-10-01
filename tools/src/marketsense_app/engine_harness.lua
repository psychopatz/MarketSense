-- This file is rendered into an ephemeral PZ server mod by engine_runner.py.
-- It deliberately asks PZ for ScriptManager and InventoryItem objects instead
-- of recreating them in Lua tables.

local cases = __MARKETSENSE_CASES__
local instanceMode = __MARKETSENSE_INSTANCE__
local ran = false
local outputName = "MarketSenseHarnessOutput.json"

local function jsonString(value)
    local text = tostring(value or "")
    text = string.gsub(text, "\\", "\\\\")
    text = string.gsub(text, '"', '\\"')
    text = string.gsub(text, "\r", "\\r")
    text = string.gsub(text, "\n", "\\n")
    return '"' .. text .. '"'
end

local function jsonValue(value, seen)
    local valueType = type(value)
    if value == nil then return "null" end
    if valueType == "string" then return jsonString(value) end
    if valueType == "boolean" then return value and "true" or "false" end
    if valueType == "number" then return tostring(value) end
    if valueType ~= "table" then return jsonString(value) end
    seen = seen or {}
    if seen[value] then return "null" end
    seen[value] = true
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(left, right) return tostring(left) < tostring(right) end)
    local fields = {}
    for _, key in ipairs(keys) do
        fields[#fields + 1] = jsonString(key) .. ":" .. jsonValue(value[key], seen)
    end
    seen[value] = nil
    return "{" .. table.concat(fields, ",") .. "}"
end

local function safe(method, object)
    if object == nil or type(method) ~= "string" then return nil end
    local ok, value = pcall(function() return object[method](object) end)
    return ok and value or nil
end

local function className(object)
    if object == nil then return nil end
    local ok, value = pcall(function() return object:getClass():getName() end)
    return ok and tostring(value) or nil
end

local function timestampMs()
    if type(getTimestampMs) ~= "function" then return nil end
    return tonumber(getTimestampMs())
end

local function detailSnapshot(details)
    if type(details) ~= "table" then return nil end
    return {
        price = details.price,
        rawScore = details.rawScore,
        confidence = details.confidence,
        category = details.category,
        primary = details.primary,
        source = details.source,
        stock = details.stock,
    }
end

local function inspectCase(case)
    local fullType = tostring(case.fullType or "")
    local startedAt = timestampMs()
    local row = {
        fullType = fullType,
        mode = instanceMode and "instance" or "definition",
    }
    local manager = getScriptManager and getScriptManager() or nil
    local scriptItem = manager and manager:FindItem(fullType) or nil
    row.scriptFound = scriptItem ~= nil
    if scriptItem ~= nil then
        row.scriptClass = className(scriptItem)
        row.scriptFullType = safe("getFullName", scriptItem)
        row.scriptModule = safe("getModuleName", scriptItem)
        row.scriptName = safe("getName", scriptItem)
        row.scriptType = safe("getType", scriptItem)
    else
        row.error = "PZ ScriptManager could not find item definition"
        local finishedAt = timestampMs()
        if startedAt and finishedAt then row.elapsedMs = finishedAt - startedAt end
        return row
    end

    local ok, details = pcall(MarketSense.GetPriceDetails, fullType, true)
    if ok then
        row.definition = detailSnapshot(details)
    else
        row.definitionError = tostring(details)
    end

    if instanceMode then
        local itemOk, item = pcall(instanceItem, fullType)
        row.instanceCreated = itemOk and item ~= nil
        if row.instanceCreated then
            row.instanceClass = className(item)
            row.instanceFullType = safe("getFullType", item)
            if case.condition ~= nil then
                pcall(function() item:setCondition(tonumber(case.condition)) end)
                row.condition = safe("getCondition", item)
            end
            local instanceOk, instanceDetails = pcall(
                MarketSense.GetPriceDetailsForInstance,
                fullType,
                item,
                true
            )
            if instanceOk then
                row.instance = detailSnapshot(instanceDetails)
            else
                row.instanceError = tostring(instanceDetails)
            end
        else
            row.instanceError = tostring(item)
        end
    end
    local finishedAt = timestampMs()
    if startedAt and finishedAt then row.elapsedMs = finishedAt - startedAt end
    return row
end

local function run()
    if ran then return end
    ran = true
    local output = getFileWriter and getFileWriter(outputName, true, false) or nil
    local function emit(line)
        if output then output:writeln(line) end
    end
    local loaded, loadError = pcall(require, "MarketSense/MS_PublicAPI")
    if not loaded then
        emit("MSENGINE\t" .. jsonValue({error = tostring(loadError)}))
        emit("MSENGINE_DONE\t" .. jsonValue({runtime = "pz-engine", error = "MarketSense API failed to load"}))
        if output then output:close() end
        return
    end
    for _, case in ipairs(cases) do
        local ok, row = pcall(inspectCase, case)
        if ok then
            emit("MSENGINE\t" .. jsonValue(row))
        else
            emit("MSENGINE\t" .. jsonValue({
                fullType = tostring(case.fullType or ""),
                error = tostring(row),
            }))
        end
    end
    emit("MSENGINE_DONE\t" .. jsonValue({
        runtime = "pz-engine",
        mod = "MarketSense",
        instance = instanceMode,
        itemCount = #cases,
        cacheStats = MarketSense.DebugTools
            and type(MarketSense.DebugTools.cacheStats) == "function"
            and MarketSense.DebugTools.cacheStats()
            or nil,
    }))
    if output then output:close() end
end

if Events and Events.OnTick and Events.OnTick.Add then
    Events.OnTick.Add(run)
else
    run()
end

-- Run immediately as well as registering the event so the harness can emit
-- results during the server's scripted startup phase.
run()
