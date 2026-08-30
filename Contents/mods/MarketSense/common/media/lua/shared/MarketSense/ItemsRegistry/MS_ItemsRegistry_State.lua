require "MarketSense/MS_Core"
require "MarketSense/ItemsRegistry/MS_ItemsRegistry_Text"

MarketSense = MarketSense or {}
local State = {}
local Text = require "MarketSense/ItemsRegistry/MS_ItemsRegistry_Text"
local Core = MarketSense.Core

function State.getTimestamp()
    if type(getGameTime) == "function" then
        local ok, gameTime = pcall(getGameTime)
        if ok and gameTime then
            local year = Core.safeNumber(gameTime, "getYear", 0)
            local month = Core.safeNumber(gameTime, "getMonth", -1) + 1
            local day = Core.safeNumber(gameTime, "getDay", 0)
            local hour = math.floor(Core.safeNumber(gameTime, "getTimeOfDay", 0))
            local minutes = Core.safeNumber(gameTime, "getMinutes", 0)
            if year > 0 and month > 0 and day > 0 then
                return string.format("PZ-%04d-%02d-%02dT%02d:%02d:00", year, month, day, hour, minutes)
            end
        end
    end
    return "unknown"
end

function State.getGameVersionString()
    local core = getCore and getCore() or nil
    if not core then
        return nil
    end

    local probe = Core.safeString(core, {
        "getGameVersionString",
        "getVersionNumber",
        "getVersion",
        "getVersionName",
    }, "")

    probe = Text.trim(probe)
    if probe == "" then
        return nil
    end

    return probe
end

function State.buildEmptyCatalog(activeState, source)
    return {
        items = {},
        total = 0,
        modules = {},
        categories = {},
        tags = {},
        files = {},
        activeModsHash = activeState and activeState.activeModsHash or nil,
        source = source or "empty",
    }
end

function State.log(level, message)
    if type(MarketSense.Log) == "function" then
        MarketSense.Log(level, "Registry", message)
    end
end

function State.debugLog(message)
    if MarketSense.IsItemRuntimeDebugEnabled and MarketSense.IsItemRuntimeDebugEnabled() then
        State.log("Debug", tostring(message or ""))
    end
end

function State.ensureRuntimeRules()
    local ok = pcall(require, "MarketSense/MS_RuntimeRules")
    if ok and MarketSense.RuntimeRules then
        return MarketSense.RuntimeRules
    end
    return nil
end

function State.isOriginActive(origin, activeModSet)
    local normalized = Text.trim(origin)
    if normalized == "" or normalized == "Base" or normalized == "Vanilla" then
        return true
    end

    return activeModSet[normalized] == true or activeModSet[Text.sanitizeOriginTag(normalized)] == true
end

function State.getActiveModsList()
    local active = {}
    local activated = getActivatedMods and getActivatedMods() or nil

    if activated and activated.size and activated.get then
        for index = 0, activated:size() - 1 do
            local ok, value = pcall(activated.get, activated, index)
            if ok and value ~= nil then
                active[#active + 1] = tostring(value)
            end
        end
    elseif type(activated) == "table" then
        for _, value in ipairs(activated) do
            active[#active + 1] = tostring(value)
        end
    end

    table.sort(active)
    return active
end

function State.buildActiveModState()
    local activeMods = State.getActiveModsList()
    local activeSet = {
        Vanilla = true,
        Base = true,
    }

    for _, modId in ipairs(activeMods) do
        activeSet[modId] = true
        activeSet[Text.sanitizeOriginTag(modId)] = true
    end

    return {
        activeMods = activeMods,
        activeModSet = activeSet,
        activeModsHash = Text.stableHash(activeMods),
        gameVersion = State.getGameVersionString(),
    }
end

function State.getOriginFromContext(ctx)
    if not ctx or ctx.moduleName == "Base" then
        return "Vanilla"
    end

    local modId = Text.trim(ctx.sourceModId)
    if modId == "" or modId == "Base" then
        modId = Text.trim(ctx.moduleName)
    end

    if modId == "" or modId == "Base" then
        return "Vanilla"
    end

    return modId
end

function State.diffActiveMods(previous, current)
    local previousSet = {}
    local currentSet = {}
    local added = {}
    local removed = {}

    for _, modId in ipairs(previous or {}) do
        previousSet[tostring(modId)] = true
    end
    for _, modId in ipairs(current or {}) do
        currentSet[tostring(modId)] = true
    end

    for _, modId in ipairs(current or {}) do
        local text = tostring(modId)
        if not previousSet[text] then
            added[#added + 1] = text
        end
    end

    for _, modId in ipairs(previous or {}) do
        local text = tostring(modId)
        if not currentSet[text] then
            removed[#removed + 1] = text
        end
    end

    table.sort(added)
    table.sort(removed)
    return added, removed
end

function State.hasEntries(value)
    if type(value) ~= "table" then
        return false
    end

    for _ in pairs(value) do
        return true
    end

    return false
end

return State
