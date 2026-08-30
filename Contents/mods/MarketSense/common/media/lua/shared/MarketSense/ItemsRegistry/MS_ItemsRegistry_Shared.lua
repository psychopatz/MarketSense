local Shared = {}

MarketSense = MarketSense or {}
require "MarketSense/MS_Config"
require "MarketSense/MS_Core"
require "MarketSense/MS_TagUtils"
require "MarketSense/MS_Pricing"
require "MarketSense/MS_Stock"
require "MarketSense/signatures/tags/MS_TagMapper"

MarketSense.ItemsRegistry = MarketSense.ItemsRegistry or {}

Shared.Registry = MarketSense.ItemsRegistry

local Registry = Shared.Registry
local Core = MarketSense.Core
local TagUtils = MarketSense.TagUtils
local Pricing = MarketSense.Pricing
local Stock = MarketSense.Stock
local Config = MarketSense.ItemRuntimeConfig
local Mapping = MarketSense.TagMapper

Registry.SCHEMA_VERSION = 4
Registry.FILE_SCHEMA = "MS_ITEMS_V1"
Registry.GENERATOR_VERSION = 2
-- Bump when pricing inputs or runtime resolver semantics change so an old
-- materialized cache cannot hide the corrected bundle values.
Registry.PRICING_HEURISTIC_VERSION = 17
Registry.SIGNATURE_VERSION = "market-sense-v20-food-pricing-v2"
Registry.ROOT_FOLDER = "MS_Items"
-- PZ's getFileWriter only permits data extensions such as .txt/.json. The
-- index is a safe, line-parsed manifest persisted as .txt.
Registry.INDEX_PATH = Registry.ROOT_FOLDER .. "/MS_ItemsIndex.txt"
Registry.REQUEST_PATH = Registry.ROOT_FOLDER .. "/MS_RebuildRequest.json"
Registry.AUDIT_PATH = Registry.ROOT_FOLDER .. "/MS_PrebuildAudit.json"
Registry.OUTPUT_HINT = "Zomboid/Lua/MS_Items/"

Registry.state = Registry.state or {
    loaded = false,
    activeModsHash = nil,
    catalog = nil,
    lastIndex = nil,
    lastRequestKey = nil,
    deferredRebuild = false,
}

Shared.CATEGORY_ORDER = {
    Food = 1,
    Weapon = 2,
    Resource = 3,
    Tool = 4,
    Container = 5,
    Clothing = 6,
    Medical = 7,
    Electronics = 8,
    Literature = 9,
    Building = 10,
    Misc = 11,
}

Shared.DESCRIPTOR_ROOTS = {
    Origin = true,
    Quality = true,
    Rarity = true,
    Theme = true,
}

function Shared.trim(value)
    local text = tostring(value or "")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    return text
end

function Shared.startsWith(text, prefix)
    text = tostring(text or "")
    prefix = tostring(prefix or "")
    return prefix ~= "" and string.sub(text, 1, #prefix) == prefix
end

function Shared.split(text, delimiter)
    local result = {}
    local source = tostring(text or "")
    local token = ""
    delimiter = tostring(delimiter or "|")

    if delimiter == "" then
        if source ~= "" then
            result[1] = source
        end
        return result
    end

    local index = 1
    while index <= #source do
        local chunk = string.sub(source, index, index + #delimiter - 1)
        if chunk == delimiter then
            result[#result + 1] = token
            token = ""
            index = index + #delimiter
        else
            token = token .. string.sub(source, index, index)
            index = index + 1
        end
    end

    result[#result + 1] = token
    return result
end

function Shared.join(list, delimiter)
    return table.concat(list or {}, delimiter or "|")
end

function Shared.copyArray(source)
    local out = {}
    for _, value in ipairs(source or {}) do
        out[#out + 1] = value
    end
    return out
end

function Shared.sanitizeOriginTag(origin)
    local text = Shared.trim(origin)
    if text == "" or text == "Base" or text == "Vanilla" then
        return "Vanilla"
    end

    text = string.gsub(text, "[^%w_%-]", "")
    if text == "" then
        text = "Modded"
    end

    return text
end

function Shared.getTimestamp()
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

function Shared.getGameVersionString()
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

    probe = Shared.trim(probe)
    if probe == "" then
        return nil
    end

    return probe
end

function Shared.stableHash(parts)
    local hash = 5381
    for _, part in ipairs(parts or {}) do
        local text = tostring(part or "")
        for index = 1, #text do
            hash = ((hash * 33) + string.byte(text, index)) % 4294967296
        end
        hash = ((hash * 33) + 124) % 4294967296
    end
    return string.format("%08x", hash)
end

function Shared.quoteString(value)
    local text = tostring(value or "")
    text = string.gsub(text, "\\", "\\\\")
    text = string.gsub(text, "\"", "\\\"")
    return "\"" .. text .. "\""
end

function Shared.jsonString(value)
    local text = tostring(value or "")
    text = string.gsub(text, "\\", "\\\\")
    text = string.gsub(text, "\"", "\\\"")
    text = string.gsub(text, "\r", "\\r")
    text = string.gsub(text, "\n", "\\n")
    return "\"" .. text .. "\""
end

function Shared.buildEmptyCatalog(activeState, source)
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

function Shared.log(level, message)
    if type(MarketSense.Log) == "function" then
        MarketSense.Log(level, "Registry", message)
    end
end

function Shared.debugLog(message)
    if MarketSense.IsItemRuntimeDebugEnabled and MarketSense.IsItemRuntimeDebugEnabled() then
        Shared.log("Debug", tostring(message or ""))
    end
end

function Shared.ensureRuntimeRules()
    local ok = pcall(require, "MarketSense/MS_RuntimeRules")
    if ok and MarketSense.RuntimeRules then
        return MarketSense.RuntimeRules
    end
    return nil
end

function Shared.isOriginActive(origin, activeModSet)
    local normalized = Shared.trim(origin)
    if normalized == "" or normalized == "Base" or normalized == "Vanilla" then
        return true
    end

    return activeModSet[normalized] == true or activeModSet[Shared.sanitizeOriginTag(normalized)] == true
end

function Shared.getActiveModsList()
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

function Shared.buildActiveModState()
    local activeMods = Shared.getActiveModsList()
    local activeSet = {
        Vanilla = true,
        Base = true,
    }

    for _, modId in ipairs(activeMods) do
        activeSet[modId] = true
        activeSet[Shared.sanitizeOriginTag(modId)] = true
    end

    return {
        activeMods = activeMods,
        activeModSet = activeSet,
        activeModsHash = Shared.stableHash(activeMods),
        gameVersion = Shared.getGameVersionString(),
    }
end

function Shared.getOriginFromContext(ctx)
    if not ctx or ctx.moduleName == "Base" then
        return "Vanilla"
    end

    local modId = Shared.trim(ctx.sourceModId)
    if modId == "" or modId == "Base" then
        modId = Shared.trim(ctx.moduleName)
    end

    if modId == "" or modId == "Base" then
        return "Vanilla"
    end

    return modId
end

function Shared.getPrimaryTag(tags)
    for _, tag in ipairs(tags or {}) do
        local root = string.match(tostring(tag), "^([^%.]+)")
        if root and not Shared.DESCRIPTOR_ROOTS[root] then
            return tag
        end
    end
    return tostring(tags and tags[1] or "Misc")
end

function Shared.getBasePrice(ctx, tagInfo)
    local rawScore = Pricing.calculateRawScore(ctx, tagInfo)
    return math.max(Config.pricing.minPrice or 1, Core.round(Core.priceClamp(rawScore)))
end

function Shared.getBaseStock(ctx)
    local maxValue = math.max(0, tonumber(Stock.baseMaxForWeight(ctx and ctx.weight or 0)) or 0)
    local minRatio = tonumber(Config.stock.defaultMinRatio) or 0.2
    local minValue = math.floor(maxValue * minRatio)
    return {
        min = math.max(0, minValue),
        max = maxValue,
    }
end

function Shared.shouldSkipSyntheticContext(ctx)
    if type(ctx) ~= "table" then
        return false, nil
    end

    local fullType = tostring(ctx.fullType or "")
    local itemLower = tostring(ctx.idLower or "")
    local displayCategory = tostring(ctx.displayCategoryLower or "")
    local bodyLocation = tostring(ctx.bodyLocationLower or "")

    if string.sub(fullType, 1, 12) == "Base.ZedDmg_" or string.sub(itemLower, 1, 7) == "zeddmg_" then
        return true, "zeddmg"
    end
    if displayCategory == "zeddmg" then
        return true, "display:zeddmg"
    end
    if bodyLocation == "base:zeddmg" or bodyLocation == "base:wound" or bodyLocation == "base:bandage" then
        return true, "body_location"
    end
    if not ctx.instanceCreated and (ctx.isFoodInstance or ctx.isFluidContainer) then
        return true, "missing_instance"
    end

    return false, nil
end

function Shared.sanitizePathPart(value, fallback)
    local text = Shared.trim(value)
    if text == "" then
        return fallback or "General"
    end
    text = string.gsub(text, "[^%w_%-]", "")
    if text == "" then
        return fallback or "General"
    end
    return text
end

function Shared.toFileEntry(primary, tags)
    local definition = Mapping.getDefinition(primary or Shared.getPrimaryTag(tags))
    return {
        category = definition.root,
        subcategory = definition.subcategory,
        leaf = definition.leaf,
        root = definition.root,
        primaryPrefix = definition.primaryPrefix,
        path = definition.path,
    }
end

function Shared.diffActiveMods(previous, current)
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

function Shared.hasEntries(value)
    if type(value) ~= "table" then
        return false
    end

    for _ in pairs(value) do
        return true
    end

    return false
end

function Shared.buildSourceManifestHash(itemsByFullType, activeState)
    local parts = {}

    for fullType, entry in pairs(itemsByFullType or {}) do
        local stockRange = entry and entry.stockRange or {}
        parts[#parts + 1] = table.concat({
            tostring(fullType or ""),
            tostring(entry and entry.origin or ""),
            tostring(entry and entry.primary or ""),
            tostring(entry and entry.basePrice or ""),
            tostring(stockRange and stockRange.min or ""),
            tostring(stockRange and stockRange.max or ""),
            Shared.join(entry and entry.tags or {}, "|"),
        }, "|")
    end

    table.sort(parts)

    if activeState and activeState.gameVersion then
        parts[#parts + 1] = "game|" .. tostring(activeState.gameVersion)
    end

    if activeState and activeState.activeModsHash then
        parts[#parts + 1] = "mods|" .. tostring(activeState.activeModsHash)
    end

    return Shared.stableHash(parts)
end

Shared.Core = Core
Shared.TagUtils = TagUtils
Shared.Pricing = Pricing
Shared.Stock = Stock
Shared.Config = Config

return Shared
