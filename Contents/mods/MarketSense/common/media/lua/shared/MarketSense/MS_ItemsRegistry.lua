require "MarketSense/DT_Config"
require "MarketSense/DT_Core"
require "MarketSense/DT_PropertyReader"
require "MarketSense/DT_AutoTag"
require "MarketSense/DT_Pricing"
require "MarketSense/DT_Stock"
require "MarketSense/DT_TagUtils"

DynamicTrading = DynamicTrading or {}
DynamicTrading.ItemsRegistry = DynamicTrading.ItemsRegistry or {}

local Registry = DynamicTrading.ItemsRegistry
local Core = DynamicTrading.Core
local TagUtils = DynamicTrading.TagUtils
local Pricing = DynamicTrading.Pricing
local Stock = DynamicTrading.Stock
local Config = DynamicTrading.ItemRuntimeConfig
local didLogAddItemFallback = false

Registry.SCHEMA_VERSION = 4
Registry.FILE_SCHEMA = "DT_ITEMS_V2"
Registry.GENERATOR_VERSION = 2
Registry.PRICING_HEURISTIC_VERSION = 2
Registry.SIGNATURE_VERSION = "market-sense-runtime-v2"
Registry.ROOT_FOLDER = "DT_Items"
Registry.INDEX_PATH = Registry.ROOT_FOLDER .. "/DT_ItemsIndex.lua"
Registry.REQUEST_PATH = Registry.ROOT_FOLDER .. "/DT_RebuildRequest.json"
Registry.AUDIT_PATH = Registry.ROOT_FOLDER .. "/DT_PrebuildAudit.json"
Registry.OUTPUT_HINT = "Zomboid/Lua/DT_Items/"

Registry.state = Registry.state or {
    loaded = false,
    activeModsHash = nil,
    catalog = nil,
    lastIndex = nil,
    lastRequestKey = nil,
}

local CATEGORY_ORDER = {
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

local DESCRIPTOR_ROOTS = {
    Origin = true,
    Quality = true,
    Rarity = true,
    Theme = true,
}

local diffActiveMods

local function trim(value)
    local text = tostring(value or "")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    return text
end

local function startsWith(text, prefix)
    text = tostring(text or "")
    prefix = tostring(prefix or "")
    return prefix ~= "" and string.sub(text, 1, #prefix) == prefix
end

local function split(text, delimiter)
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

local function join(list, delimiter)
    return table.concat(list or {}, delimiter or "|")
end

local function copyArray(source)
    local out = {}
    for _, value in ipairs(source or {}) do
        out[#out + 1] = value
    end
    return out
end

local function sanitizeOriginTag(origin)
    local text = trim(origin)
    if text == "" or text == "Base" or text == "Vanilla" then
        return "Vanilla"
    end

    text = string.gsub(text, "[^%w_%-]", "")
    if text == "" then
        text = "Modded"
    end

    return text
end

local function getTimestamp()
    if os and os.date then
        return os.date("!%Y-%m-%dT%H:%M:%SZ")
    end
    return "1970-01-01T00:00:00Z"
end

local function getGameVersionString()
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

    probe = trim(probe)
    if probe == "" then
        return nil
    end

    return probe
end

local function stableHash(parts)
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

local function quoteString(value)
    local text = tostring(value or "")
    text = string.gsub(text, "\\", "\\\\")
    text = string.gsub(text, "\"", "\\\"")
    return "\"" .. text .. "\""
end

local function jsonString(value)
    local text = tostring(value or "")
    text = string.gsub(text, "\\", "\\\\")
    text = string.gsub(text, "\"", "\\\"")
    text = string.gsub(text, "\r", "\\r")
    text = string.gsub(text, "\n", "\\n")
    return "\"" .. text .. "\""
end

local function buildEmptyCatalog(activeState, source)
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

local function log(level, message)
    if not DynamicTrading or not DynamicTrading.Log then
        return
    end
    DynamicTrading.Log("MarketSense", "Registry", tostring(level or "Info"), tostring(message or ""))
end

local function debugLog(message)
    if DynamicTrading and DynamicTrading.IsItemRuntimeDebugEnabled and DynamicTrading.IsItemRuntimeDebugEnabled() then
        log("Info", "[debug] " .. tostring(message or ""))
    end
end

local function ensureRuntimeRules()
    local ok = pcall(require, "MarketSense/MS_RuntimeRules")
    if ok and DynamicTrading.RuntimeRules then
        return DynamicTrading.RuntimeRules
    end
    return nil
end

local function isOriginActive(origin, activeModSet)
    local normalized = trim(origin)
    if normalized == "" or normalized == "Base" or normalized == "Vanilla" then
        return true
    end

    return activeModSet[normalized] == true or activeModSet[sanitizeOriginTag(normalized)] == true
end

local function getActiveModsList()
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

local function buildActiveModState()
    local activeMods = getActiveModsList()
    local activeSet = {
        Vanilla = true,
        Base = true,
    }

    for _, modId in ipairs(activeMods) do
        activeSet[modId] = true
        activeSet[sanitizeOriginTag(modId)] = true
    end

    return {
        activeMods = activeMods,
        activeModSet = activeSet,
        activeModsHash = stableHash(activeMods),
        gameVersion = getGameVersionString(),
    }
end

local function getOriginFromContext(ctx)
    if not ctx or ctx.moduleName == "Base" then
        return "Vanilla"
    end

    local modId = trim(ctx.sourceModId)
    if modId == "" or modId == "Base" then
        modId = trim(ctx.moduleName)
    end

    if modId == "" or modId == "Base" then
        return "Vanilla"
    end

    return modId
end

local function getPrimaryTag(tags)
    for _, tag in ipairs(tags or {}) do
        local root = string.match(tostring(tag), "^([^%.]+)")
        if root and not DESCRIPTOR_ROOTS[root] then
            return tag
        end
    end
    return tostring(tags and tags[1] or "Misc.General")
end

local function getBasePrice(ctx, tagInfo)
    local rawScore = Pricing.calculateRawScore(ctx, tagInfo)
    return math.max(Config.pricing.minPrice or 1, Core.round(Core.priceClamp(rawScore)))
end

local function getBaseStock(ctx)
    local maxValue = math.max(0, tonumber(Stock.baseMaxForWeight(ctx and ctx.weight or 0)) or 0)
    local minRatio = tonumber(Config.stock.defaultMinRatio) or 0.2
    local minValue = math.floor(maxValue * minRatio)
    return {
        min = math.max(0, minValue),
        max = maxValue,
    }
end

local function shouldSkipSyntheticContext(ctx)
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

local function sanitizePathPart(value, fallback)
    local text = trim(value)
    if text == "" then
        return fallback or "General"
    end
    text = string.gsub(text, "[^%w_%-]", "")
    if text == "" then
        return fallback or "General"
    end
    return text
end

local function toFileEntry(primary, tags)
    local main = tostring(primary or getPrimaryTag(tags))
    local parts = split(main, ".")
    local root = parts[1] or "Misc"
    local sub1 = parts[2] or ""
    local sub2 = parts[3] or ""

    local category = "Misc"
    local subcategory = "General"
    local leaf = "General"

    if root == "Food" then
        category = "Food"
        if sub1 == "Perishable" or sub1 == "NonPerishable" or sub1 == "Drink" or sub1 == "Cooking" then
            subcategory = sub1
            leaf = sub2 ~= "" and sub2 or "General"
        elseif sub1 == "Fruit" or sub1 == "Vegetable" or sub1 == "Meat" or sub1 == "Fish" or sub1 == "Grain" or sub1 == "Sweets" then
            subcategory = "Perishable"
            leaf = sub1
        elseif sub1 == "Spice" then
            subcategory = "Cooking"
            leaf = "Spice"
        elseif sub1 == "Alcohol" or sub1 == "NonAlcoholic" then
            subcategory = "Drink"
            leaf = sub1
        else
            subcategory = "NonPerishable"
            leaf = sub1 ~= "" and sub1 or "General"
        end
    elseif root == "Weapon" then
        category = "Weapon"
        if sub1 == "Ranged" and sub2 == "Ammo" then
            subcategory = "Ranged"
            leaf = "Ammo"
        elseif sub1 == "Ammo" then
            subcategory = "Ammo"
            leaf = sub2 ~= "" and sub2 or "General"
        elseif sub1 == "Melee" then
            subcategory = "Melee"
            leaf = sub2 ~= "" and sub2 or "General"
        elseif sub1 == "Ranged" then
            subcategory = "Ranged"
            leaf = sub2 ~= "" and sub2 or "General"
        elseif sub1 == "Explosive" then
            subcategory = "Explosive"
            leaf = sub2 ~= "" and sub2 or "General"
        elseif sub1 == "Part" then
            subcategory = "Part"
            leaf = sub2 ~= "" and sub2 or "General"
        else
            subcategory = "Melee"
            leaf = sub1 ~= "" and sub1 or "General"
        end
    elseif root == "Resource" then
        category = "Resource"
        if sub1 == "Fuel" then
            subcategory = "Fuel"
            leaf = sub2 ~= "" and sub2 or "General"
        elseif sub1 == "Parts" or sub1 == "Part" then
            subcategory = "Parts"
            leaf = sub2 ~= "" and sub2 or "General"
        elseif sub1 == "Fishing" then
            subcategory = "Fishing"
            leaf = sub2 ~= "" and sub2 or "General"
        else
            subcategory = "Material"
            leaf = sub2 ~= "" and sub2 or (sub1 ~= "" and sub1 or "General")
        end
    elseif root == "Tool" then
        category = "Tool"
        if sub1 == "Cooking" or sub1 == "Cookware" then
            subcategory = "Cookware"
            leaf = sub2 ~= "" and sub2 or "General"
        elseif sub1 == "Crafting" or sub1 == "Carpentry" or sub1 == "Masonry" or sub1 == "Mechanics"
            or sub1 == "Blacksmith" or sub1 == "Tailoring" or sub1 == "Welding" or sub1 == "Maintenance"
            or sub1 == "Pottery" or sub1 == "FlintKnapping" or sub1 == "Butchering" then
            subcategory = "Crafting"
            leaf = sub1
        elseif sub1 == "Gardening" or sub1 == "Farming" then
            subcategory = "Farming"
            leaf = sub1
        elseif sub1 == "Fishing" then
            subcategory = sub1
            leaf = sub2 ~= "" and sub2 or "General"
        else
            subcategory = "General"
            leaf = sub1 ~= "" and sub1 or "General"
        end
    elseif root == "Container" then
        category = "Container"
        if sub1 == "Bag" or sub1 == "Liquid" or sub1 == "Stash" or sub1 == "Utility" then
            subcategory = sub1
            leaf = sub2 ~= "" and sub2 or "General"
        else
            subcategory = "Utility"
            leaf = sub1 ~= "" and sub1 or "General"
        end
    elseif root == "Clothing" then
        category = "Clothing"
        if sub1 == "Armor" or sub1 == "Accessory" or sub1 == "Top" or sub1 == "Bottom" then
            subcategory = sub1
            leaf = sub2 ~= "" and sub2 or "General"
        else
            subcategory = "General"
            leaf = sub1 ~= "" and sub1 or "General"
        end
    elseif root == "Medical" then
        category = "Medical"
        if sub1 == "Drug" or sub2 == "Drug" then
            subcategory = "Drug"
            leaf = sub2 ~= "" and sub2 or (sub1 ~= "" and sub1 or "General")
        elseif sub1 == "Consumable" then
            subcategory = "Consumable"
            leaf = sub2 ~= "" and sub2 or "General"
        else
            subcategory = "Healthcare"
            leaf = sub2 ~= "" and sub2 or (sub1 ~= "" and sub1 or "General")
        end
    elseif root == "Electronics" then
        category = "Electronics"
        if sub1 == "Radio" or sub1 == "Light" or sub1 == "Battery" or sub1 == "Generator" or sub1 == "Gadget" or sub1 == "Television" then
            subcategory = sub1
            leaf = sub2 ~= "" and sub2 or "General"
        elseif sub1 == "PowerGenerator" then
            subcategory = "Generator"
            leaf = sub2 ~= "" and sub2 or "General"
        else
            subcategory = "Gadget"
            leaf = sub1 ~= "" and sub1 or "General"
        end
    elseif root == "Literature" then
        category = "Literature"
        if sub1 == "Book" or sub1 == "SkillBook" or sub1 == "Recipe" or sub1 == "Media" or sub1 == "Cards" then
            subcategory = sub1
            leaf = sub2 ~= "" and sub2 or "General"
        else
            subcategory = "Book"
            leaf = sub1 ~= "" and sub1 or "General"
        end
    elseif root == "Building" then
        category = "Building"
        if sub1 == "Furniture" or sub1 == "Fixture" or sub1 == "Garden" or sub1 == "Survival" or sub1 == "Vehicle" or sub1 == "Moveable" then
            subcategory = sub1
            leaf = sub2 ~= "" and sub2 or "General"
        else
            subcategory = "Moveable"
            leaf = sub1 ~= "" and sub1 or "General"
        end
    else
        category = "Misc"
        subcategory = "General"
        leaf = sub1 ~= "" and sub1 or "General"
    end

    subcategory = sanitizePathPart(subcategory, "General")
    leaf = sanitizePathPart(leaf, "General")

    return {
        category = category,
        subcategory = subcategory,
        leaf = leaf,
        root = category,
        primaryPrefix = category .. "." .. subcategory .. "." .. leaf,
        path = category .. "/DT_" .. subcategory .. (leaf ~= "General" and ("_" .. leaf) or "") .. ".txt",
    }
end

local function parseLuaTableFile(path)
    local reader = getFileReader(path, false)
    if not reader then
        return nil
    end

    local chunks = {}
    local line = reader:readLine()
    while line do
        chunks[#chunks + 1] = line
        line = reader:readLine()
    end
    reader:close()

    local source = table.concat(chunks, "\n")
    if source == "" then
        return nil
    end

    local loader = loadstring or load
    if type(loader) ~= "function" then
        log("Warn", "No compatible Lua chunk loader is available for " .. tostring(path))
        return nil
    end

    local okLoad, chunkOrErr, loadErr = pcall(loader, source)
    local chunk = okLoad and chunkOrErr or nil
    local err = okLoad and loadErr or chunkOrErr
    if not chunk then
        log("Warn", "Failed to parse " .. tostring(path) .. ": " .. tostring(err))
        return nil
    end

    local ok, data = pcall(chunk)
    if ok and type(data) == "table" then
        return data
    end

    log("Warn", "Failed to execute parsed registry file " .. tostring(path))
    return nil
end

local function serializeIndex(indexData)
    local lines = {
        "return {",
        "    schemaVersion = " .. tostring(indexData.schemaVersion or Registry.SCHEMA_VERSION) .. ",",
        "    generatedAt = " .. quoteString(indexData.generatedAt or "") .. ",",
        "    activeModsHash = " .. quoteString(indexData.activeModsHash or "") .. ",",
        "    generatorVersion = " .. tostring(indexData.generatorVersion or Registry.GENERATOR_VERSION) .. ",",
        "    signatureVersion = " .. quoteString(indexData.signatureVersion or Registry.SIGNATURE_VERSION) .. ",",
        "    pricingHeuristicVersion = " .. tostring(indexData.pricingHeuristicVersion or Registry.PRICING_HEURISTIC_VERSION) .. ",",
    }

    if indexData.gameVersion ~= nil then
        lines[#lines + 1] = "    gameVersion = " .. quoteString(indexData.gameVersion or "") .. ","
    end
    if indexData.sourceManifestHash ~= nil then
        lines[#lines + 1] = "    sourceManifestHash = " .. quoteString(indexData.sourceManifestHash or "") .. ","
    end

    lines[#lines + 1] = "    activeMods = {"
    for _, modId in ipairs(indexData.activeMods or {}) do
        lines[#lines + 1] = "        " .. quoteString(modId) .. ","
    end
    lines[#lines + 1] = "    },"

    lines[#lines + 1] = ""
    lines[#lines + 1] = "    files = {"

    for _, fileEntry in ipairs(indexData.files or {}) do
        lines[#lines + 1] = "        { root = " .. quoteString(fileEntry.root or fileEntry.category) ..
            ", category = " .. quoteString(fileEntry.category) ..
            ", subcategory = " .. quoteString(fileEntry.subcategory) ..
            ", leaf = " .. quoteString(fileEntry.leaf or "General") ..
            ", primaryPrefix = " .. quoteString(fileEntry.primaryPrefix or "") ..
            ", path = " .. quoteString(fileEntry.path) .. " },"
    end

    lines[#lines + 1] = "    }"
    lines[#lines + 1] = "}"
    return table.concat(lines, "\r\n") .. "\r\n"
end

local function writeFile(path, content)
    local writer = getFileWriter(path, true, false)
    if not writer then
        log("Warn", "Failed to open cache file for writing: " .. tostring(path) .. " (expected under " .. Registry.OUTPUT_HINT .. ")")
        return false
    end
    writer:write(content or "")
    writer:close()
    debugLog("Wrote cache file: " .. tostring(path))
    return true
end

local function writeRebuildRequest(reason, activeState, previousIndex, extra)
    local activeHash = tostring(activeState and activeState.activeModsHash or "")
    local requestKey = tostring(reason or "unknown") .. "|" .. activeHash
    if Registry.state.lastRequestKey == requestKey then
        return false
    end

    local addedMods = {}
    local removedMods = {}
    if previousIndex and type(previousIndex.activeMods) == "table" and activeState then
        addedMods, removedMods = diffActiveMods(previousIndex.activeMods, activeState.activeMods)
    end

    local lines = {
        "{",
        "  \"requestedAt\": " .. jsonString(getTimestamp()) .. ",",
        "  \"reason\": " .. jsonString(reason or "unknown") .. ",",
        "  \"expected\": {",
        "    \"schemaVersion\": " .. tostring(Registry.SCHEMA_VERSION) .. ",",
        "    \"generatorVersion\": " .. tostring(Registry.GENERATOR_VERSION) .. ",",
        "    \"signatureVersion\": " .. jsonString(Registry.SIGNATURE_VERSION) .. ",",
        "    \"pricingHeuristicVersion\": " .. tostring(Registry.PRICING_HEURISTIC_VERSION),
        "  },",
        "  \"activeModsHash\": " .. jsonString(activeHash) .. ",",
        "  \"activeMods\": [",
    }

    for index, modId in ipairs(activeState and activeState.activeMods or {}) do
        local suffix = index < #(activeState.activeMods or {}) and "," or ""
        lines[#lines + 1] = "    " .. jsonString(modId) .. suffix
    end

    lines[#lines + 1] = "  ],"
    lines[#lines + 1] = "  \"addedMods\": ["
    for index, modId in ipairs(addedMods) do
        local suffix = index < #addedMods and "," or ""
        lines[#lines + 1] = "    " .. jsonString(modId) .. suffix
    end
    lines[#lines + 1] = "  ],"
    lines[#lines + 1] = "  \"removedMods\": ["
    for index, modId in ipairs(removedMods) do
        local suffix = index < #removedMods and "," or ""
        lines[#lines + 1] = "    " .. jsonString(modId) .. suffix
    end
    lines[#lines + 1] = "  ]"

    if extra and extra ~= "" then
        lines[#lines] = lines[#lines] .. ","
        lines[#lines + 1] = "  \"message\": " .. jsonString(extra)
    end

    lines[#lines + 1] = "}"

    if writeFile(Registry.REQUEST_PATH, table.concat(lines, "\n")) then
        Registry.state.lastRequestKey = requestKey
        return true
    end

    return false
end

local function loadIndex()
    local indexData = parseLuaTableFile(Registry.INDEX_PATH)
    if type(indexData) ~= "table" then
        return nil
    end

    if type(indexData.files) ~= "table" then
        indexData.files = {}
    end
    if type(indexData.activeMods) ~= "table" then
        indexData.activeMods = {}
    end

    return indexData
end

local function sortFileEntries(files)
    table.sort(files, function(left, right)
        local leftOrder = CATEGORY_ORDER[left.root or left.category] or 999
        local rightOrder = CATEGORY_ORDER[right.root or right.category] or 999
        if leftOrder ~= rightOrder then
            return leftOrder < rightOrder
        end
        if (left.root or left.category) ~= (right.root or right.category) then
            return tostring(left.root or left.category) < tostring(right.root or right.category)
        end
        if left.subcategory ~= right.subcategory then
            return tostring(left.subcategory) < tostring(right.subcategory)
        end
        if tostring(left.leaf or "") ~= tostring(right.leaf or "") then
            return tostring(left.leaf or "") < tostring(right.leaf or "")
        end
        return tostring(left.path) < tostring(right.path)
    end)
end

local function parseLeanFile(path)
    local reader = getFileReader(Registry.ROOT_FOLDER .. "/" .. path, false)
    if not reader then
        return nil
    end

    local data = {
        path = path,
        root = nil,
        category = nil,
        subcategory = nil,
        leaf = nil,
        primaryPrefix = nil,
        generatedAt = nil,
        groups = {},
    }

    local current = nil

    local function flushCurrent()
        if current and current.origin and current.tags and #current.items > 0 then
            data.groups[#data.groups + 1] = current
        end
        current = nil
    end

    local line = reader:readLine()
    while line do
        local text = trim(line)

        if text == "" then
            flushCurrent()
        elseif startsWith(text, "#") then
            local meta = trim(string.sub(text, 2))
            local key, value = string.match(meta, "^([^=]+)=(.*)$")
            key = trim(key)
            value = trim(value)
            if key == "category" then
                data.category = value
            elseif key == "root" then
                data.root = value
            elseif key == "subcategory" then
                data.subcategory = value
            elseif key == "leaf" then
                data.leaf = value
            elseif key == "primaryPrefix" then
                data.primaryPrefix = value
            elseif key == "generatedAt" then
                data.generatedAt = value
            end
        elseif startsWith(text, "@origin=") then
            if current and #current.items > 0 then
                flushCurrent()
            end
            current = current or { items = {} }
            current.origin = trim(string.sub(text, 9))
        elseif startsWith(text, "@tags=") then
            if current and #current.items > 0 then
                flushCurrent()
            end
            current = current or { items = {} }
            current.tags = {}
            for _, tag in ipairs(split(string.sub(text, 7), "|")) do
                local cleaned = trim(tag)
                if cleaned ~= "" then
                    current.tags[#current.tags + 1] = cleaned
                end
            end
            current.tags = TagUtils.unique(current.tags)
        else
            local parts = split(text, "|")
            local fullType = trim(parts[1])
            local basePrice = tonumber(parts[2])
            local stockMin = tonumber(parts[3])
            local stockMax = tonumber(parts[4])

            if fullType ~= "" and basePrice ~= nil and stockMin ~= nil and stockMax ~= nil then
                current = current or { items = {} }
                current.items[#current.items + 1] = {
                    fullType,
                    math.max(Config.pricing.minPrice or 1, Core.round(basePrice)),
                    math.max(0, math.floor(stockMin)),
                    math.max(0, math.floor(stockMax)),
                }
            end
        end

        line = reader:readLine()
    end

    flushCurrent()
    reader:close()
    return data
end

local function loadStoredItems(indexData)
    local items = {}
    for _, fileEntry in ipairs(indexData and indexData.files or {}) do
        local parsed = parseLeanFile(fileEntry.path)
        if parsed then
            for _, group in ipairs(parsed.groups or {}) do
                local tags = TagUtils.unique(group.tags or {})
                local primary = getPrimaryTag(tags)
                for _, row in ipairs(group.items or {}) do
                    local fullType = tostring(row[1] or "")
                    if fullType ~= "" then
                        items[fullType] = {
                            item = fullType,
                            basePrice = tonumber(row[2]) or (Config.pricing.minPrice or 1),
                            tags = copyArray(tags),
                            stockRange = {
                                min = math.max(0, tonumber(row[3]) or 0),
                                max = math.max(0, tonumber(row[4]) or 0),
                            },
                            origin = group.origin or "Vanilla",
                            root = parsed.root or fileEntry.root or parsed.category or fileEntry.category,
                            category = parsed.category or fileEntry.category,
                            subcategory = parsed.subcategory or fileEntry.subcategory,
                            leaf = parsed.leaf or fileEntry.leaf,
                            primary = primary,
                            primaryPrefix = parsed.primaryPrefix or fileEntry.primaryPrefix,
                            path = fileEntry.path,
                        }
                    end
                end
            end
        end
    end
    return items
end

local function validateIndex(indexData, activeState)
    if type(indexData) ~= "table" then
        return false, "missing"
    end
    if tonumber(indexData.schemaVersion) ~= Registry.SCHEMA_VERSION then
        return false, "schema"
    end
    if tonumber(indexData.generatorVersion) ~= Registry.GENERATOR_VERSION then
        return false, "generator"
    end
    if tostring(indexData.activeModsHash or "") ~= tostring(activeState.activeModsHash or "") then
        return false, "mods"
    end
    if tostring(indexData.signatureVersion or "") ~= Registry.SIGNATURE_VERSION then
        return false, "signatures"
    end
    if tonumber(indexData.pricingHeuristicVersion) ~= Registry.PRICING_HEURISTIC_VERSION then
        return false, "pricing"
    end
    if activeState.gameVersion and trim(indexData.gameVersion or "") ~= "" and tostring(indexData.gameVersion) ~= tostring(activeState.gameVersion) then
        return false, "game"
    end
    if trim(indexData.sourceManifestHash or "") == "" then
        return false, "manifest"
    end
    if type(indexData.files) ~= "table" or #indexData.files == 0 then
        return false, "files"
    end
    return true, "ok"
end

diffActiveMods = function(previous, current)
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

local function hasEntries(value)
    if type(value) ~= "table" then
        return false
    end

    for _ in pairs(value) do
        return true
    end

    return false
end

local function buildSourceManifestHash(itemsByFullType, activeState)
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
            join(entry and entry.tags or {}, "|"),
        }, "|")
    end

    table.sort(parts)

    if activeState and activeState.gameVersion then
        parts[#parts + 1] = "game|" .. tostring(activeState.gameVersion)
    end

    if activeState and activeState.activeModsHash then
        parts[#parts + 1] = "mods|" .. tostring(activeState.activeModsHash)
    end

    return stableHash(parts)
end

local function buildLiveEntry(fullType, itemData, sourceOrigin, category, primary)
    local moduleName, typeName = Core.splitFullType(fullType)
    local effectiveBasePrice = tonumber(itemData.basePrice) or (Config.pricing.minPrice or 1)
    if DynamicTrading.PriceConfig and DynamicTrading.PriceConfig.GetEffectiveBasePrice then
        effectiveBasePrice = DynamicTrading.PriceConfig.GetEffectiveBasePrice(fullType, itemData)
    end

    local expandedTags = TagUtils.expandHierarchy(itemData.tags or {})
    return {
        fullType = fullType,
        moduleName = moduleName,
        typeName = typeName,
        sourceModId = sourceOrigin or moduleName,
        sourceModName = sourceOrigin == "Vanilla" and "Project Zomboid (Vanilla)" or tostring(sourceOrigin or moduleName),
        category = category or TagUtils.categoryFromPrimary(primary or getPrimaryTag(itemData.tags)),
        primary = primary or getPrimaryTag(itemData.tags),
        tags = copyArray(itemData.tags or {}),
        expandedTags = expandedTags,
        basePrice = tonumber(itemData.basePrice) or 0,
        price = tonumber(effectiveBasePrice) or 0,
        rawScore = tonumber(itemData.basePrice) or 0,
        confidence = 1,
        stock = {
            min = math.max(0, tonumber(itemData.stockRange and itemData.stockRange.min) or 0),
            max = math.max(0, tonumber(itemData.stockRange and itemData.stockRange.max) or 0),
        },
        source = "lean-cache",
    }
end

local applyRuntimeOverride

local function collectGeneratedItems()
    local runtimeRules = ensureRuntimeRules()
    if runtimeRules and runtimeRules.loadFromFile then
        runtimeRules.loadFromFile(false)
    end

    local ok, allItems = pcall(function()
        return getAllItems and getAllItems() or nil
    end)

    if not ok or allItems == nil then
        return {}
    end

    local generated = {}
    for index = 0, allItems:size() - 1 do
        local scriptItem = allItems:get(index)
        local ctx = DynamicTrading.PropertyReader.buildContext(scriptItem)
        if ctx and ctx.fullType and ctx.fullType ~= "" then
            local syntheticSkip = false
            local syntheticReason = nil
            syntheticSkip, syntheticReason = shouldSkipSyntheticContext(ctx)
            local skip = syntheticSkip or (runtimeRules and runtimeRules.shouldSkip and runtimeRules.shouldSkip(ctx.fullType) or false)
            if not skip then
                local tagInfo = DynamicTrading.AutoTag.generate(ctx)
                local baseData = {
                    item = ctx.fullType,
                    basePrice = getBasePrice(ctx, tagInfo),
                    tags = TagUtils.unique(tagInfo.tags or { tagInfo.primary }),
                    stockRange = getBaseStock(ctx),
                }
                local liveData = applyRuntimeOverride(ctx.fullType, baseData, runtimeRules)
                local primary = getPrimaryTag(liveData.tags)
                local fileEntry = toFileEntry(primary, liveData.tags)
                local origin = getOriginFromContext(ctx)

                generated[ctx.fullType] = {
                    item = ctx.fullType,
                    basePrice = tonumber(liveData.basePrice) or getBasePrice(ctx, tagInfo),
                    tags = TagUtils.unique(liveData.tags or { primary }),
                    stockRange = {
                        min = math.max(0, tonumber(liveData.stockRange and liveData.stockRange.min) or 0),
                        max = math.max(0, tonumber(liveData.stockRange and liveData.stockRange.max) or 0),
                    },
                    origin = origin,
                    root = fileEntry.root,
                    category = fileEntry.category,
                    subcategory = fileEntry.subcategory,
                    leaf = fileEntry.leaf,
                    primary = primary,
                    primaryPrefix = fileEntry.primaryPrefix,
                    path = fileEntry.path,
                }
            elseif syntheticSkip then
                debugLog("Skipped synthetic/invalid item during DT_Items generation: " .. tostring(ctx.fullType) .. " (" .. tostring(syntheticReason or "synthetic") .. ")")
            end
        end
    end

    return generated
end

local function mergeStoredAndGenerated(storedItems, generatedItems, activeState)
    local merged = {}

    for fullType, entry in pairs(storedItems or {}) do
        if not isOriginActive(entry.origin, activeState.activeModSet) then
            merged[fullType] = entry
        end
    end

    for fullType, entry in pairs(generatedItems or {}) do
        merged[fullType] = entry
    end

    return merged
end

local function groupForWrite(itemsByFullType)
    local grouped = {}

    for fullType, entry in pairs(itemsByFullType or {}) do
        local fileEntry = toFileEntry(entry.primary, entry.tags)
        local path = entry.path or fileEntry.path
        local root = entry.root or fileEntry.root or fileEntry.category
        local category = entry.category or fileEntry.category
        local subcategory = entry.subcategory or fileEntry.subcategory
        local leaf = entry.leaf or fileEntry.leaf or "General"
        local primaryPrefix = entry.primaryPrefix or fileEntry.primaryPrefix or entry.primary

        grouped[path] = grouped[path] or {
            root = root,
            category = category,
            subcategory = subcategory,
            leaf = leaf,
            primaryPrefix = primaryPrefix,
            groups = {},
        }

        local groupKey = tostring(entry.origin or "Vanilla") .. "\31" .. join(entry.tags or {}, "|")
        local bucket = grouped[path].groups[groupKey]
        if not bucket then
            bucket = {
                origin = entry.origin or "Vanilla",
                tags = TagUtils.unique(entry.tags or {}),
                items = {},
            }
            grouped[path].groups[groupKey] = bucket
        end

        bucket.items[#bucket.items + 1] = {
            item = fullType,
            basePrice = tonumber(entry.basePrice) or (Config.pricing.minPrice or 1),
            stockMin = tonumber(entry.stockRange and entry.stockRange.min) or 0,
            stockMax = tonumber(entry.stockRange and entry.stockRange.max) or 0,
        }
    end

    return grouped
end

local function writeGroupedFiles(grouped, activeState, sourceManifestHash)
    local timestamp = getTimestamp()
    local files = {}

    for path, payload in pairs(grouped or {}) do
        local content = {
            "# schema=" .. Registry.FILE_SCHEMA,
            "# root=" .. tostring(payload.root or payload.category or "Misc"),
            "# category=" .. tostring(payload.category or "Misc"),
            "# subcategory=" .. tostring(payload.subcategory or "General"),
            "# leaf=" .. tostring(payload.leaf or "General"),
            "# primaryPrefix=" .. tostring(payload.primaryPrefix or ((payload.category or "Misc") .. "." .. (payload.subcategory or "General") .. "." .. (payload.leaf or "General"))),
            "# generatedAt=" .. timestamp,
            "",
        }

        local keys = {}
        for groupKey in pairs(payload.groups or {}) do
            keys[#keys + 1] = groupKey
        end
        table.sort(keys)

        for _, groupKey in ipairs(keys) do
            local group = payload.groups[groupKey]
            table.sort(group.items, function(left, right)
                return tostring(left.item) < tostring(right.item)
            end)

            content[#content + 1] = "@origin=" .. tostring(group.origin or "Vanilla")
            content[#content + 1] = "@tags=" .. join(group.tags or {}, "|")
            for _, row in ipairs(group.items) do
                content[#content + 1] = tostring(row.item) ..
                    "|" .. tostring(Core.round(row.basePrice or 0)) ..
                    "|" .. tostring(math.max(0, math.floor(row.stockMin or 0))) ..
                    "|" .. tostring(math.max(0, math.floor(row.stockMax or 0)))
            end
            content[#content + 1] = ""
        end

    local ok = writeFile(Registry.ROOT_FOLDER .. "/" .. path, table.concat(content, "\r\n"))
    if ok then
        files[#files + 1] = {
                root = payload.root or payload.category,
                category = payload.category,
                subcategory = payload.subcategory,
                leaf = payload.leaf,
                primaryPrefix = payload.primaryPrefix,
                path = path,
            }
        end
    end

    sortFileEntries(files)

    local indexData = {
        schemaVersion = Registry.SCHEMA_VERSION,
        generatedAt = timestamp,
        activeModsHash = activeState.activeModsHash,
        generatorVersion = Registry.GENERATOR_VERSION,
        signatureVersion = Registry.SIGNATURE_VERSION,
        pricingHeuristicVersion = Registry.PRICING_HEURISTIC_VERSION,
        gameVersion = activeState.gameVersion,
        sourceManifestHash = tostring(sourceManifestHash or stableHash({
            tostring(activeState and activeState.activeModsHash or ""),
            tostring(timestamp),
        })),
        activeMods = copyArray(activeState.activeMods),
        files = files,
    }

    writeFile(Registry.INDEX_PATH, serializeIndex(indexData))
    return indexData
end

applyRuntimeOverride = function(fullType, data, runtimeRules)
    local liveData = {
        item = fullType,
        basePrice = tonumber(data.basePrice) or (Config.pricing.minPrice or 1),
        tags = copyArray(data.tags or {}),
        stockRange = {
            min = math.max(0, tonumber(data.stockRange and data.stockRange.min) or 0),
            max = math.max(0, tonumber(data.stockRange and data.stockRange.max) or 0),
        },
    }

    if not runtimeRules or type(runtimeRules.getOverride) ~= "function" then
        return liveData
    end

    local override = runtimeRules.getOverride(fullType)
    if type(override) ~= "table" then
        return liveData
    end

    if type(override.tags) == "table" and #override.tags > 0 then
        liveData.tags = TagUtils.unique(override.tags)
    end

    if type(override.price) == "number" then
        liveData.basePrice = math.max(Config.pricing.minPrice or 1, Core.round(override.price))
    end

    if type(override.stock) == "table" then
        if override.stock.min ~= nil then
            liveData.stockRange.min = math.max(0, math.floor(tonumber(override.stock.min) or 0))
        end
        if override.stock.max ~= nil then
            liveData.stockRange.max = math.max(0, math.floor(tonumber(override.stock.max) or 0))
        end
        if liveData.stockRange.min > liveData.stockRange.max then
            liveData.stockRange.min = liveData.stockRange.max
        end
    end

    return liveData
end

local function ensureAddItemApi()
    if type(DynamicTrading.AddItem) == "function" then
        return DynamicTrading.AddItem
    end

    pcall(require, "DT/Common/Config/DT_Config_ItemRegistry")
    if type(DynamicTrading.AddItem) == "function" then
        debugLog("Loaded DT item registry API on demand before cache registration.")
        return DynamicTrading.AddItem
    end

    return nil
end

local function registerLiveItem(fullType, data)
    DynamicTrading.Config = DynamicTrading.Config or {}
    DynamicTrading.Config.MasterList = DynamicTrading.Config.MasterList or {}

    local addItem = ensureAddItemApi()
    if addItem then
        addItem(fullType, data)
        return true
    end

    DynamicTrading.Config.MasterList[fullType] = data
    DynamicTrading.Config.ItemRegistryRevision = (tonumber(DynamicTrading.Config.ItemRegistryRevision) or 0) + 1

    if not didLogAddItemFallback then
        log("Warn", "DynamicTrading.AddItem was unavailable during registry load; using direct MasterList fallback for Project Zomboid compatibility.")
        didLogAddItemFallback = true
    end
    debugLog("Registered item through direct MasterList fallback: " .. tostring(fullType))
    return true
end

local function populateMasterList(indexData, activeState)
    local runtimeRules = ensureRuntimeRules()
    if runtimeRules and runtimeRules.loadFromFile then
        runtimeRules.loadFromFile(false)
    end

    DynamicTrading.Config = DynamicTrading.Config or {}
    DynamicTrading.Config.MasterList = {}
    DynamicTrading.Config.ItemRegistryRevision = tonumber(DynamicTrading.Config.ItemRegistryRevision) or 0

    local catalog = {
        total = 0,
        modules = {},
        categories = {},
        tags = {},
        files = copyArray(indexData and indexData.files or {}),
        activeModsHash = activeState.activeModsHash,
        generatedAt = indexData and indexData.generatedAt or nil,
        source = "lean-cache",
    }

    for _, fileEntry in ipairs(indexData and indexData.files or {}) do
        local parsed = parseLeanFile(fileEntry.path)
        if parsed then
            local category = parsed.category or fileEntry.category
            for _, group in ipairs(parsed.groups or {}) do
                if isOriginActive(group.origin, activeState.activeModSet) then
                    local baseTags = TagUtils.unique(group.tags or {})

                    for _, row in ipairs(group.items or {}) do
                        local fullType = tostring(row[1] or "")
                        if fullType ~= "" then
                            local skip = runtimeRules and runtimeRules.shouldSkip and runtimeRules.shouldSkip(fullType) or false
                            if not skip then
                                local baseData = {
                                    item = fullType,
                                    basePrice = tonumber(row[2]) or (Config.pricing.minPrice or 1),
                                    tags = copyArray(baseTags),
                                    stockRange = {
                                        min = math.max(0, tonumber(row[3]) or 0),
                                        max = math.max(0, tonumber(row[4]) or 0),
                                    },
                                }

                                local liveData = applyRuntimeOverride(fullType, baseData, runtimeRules)
                                registerLiveItem(fullType, liveData)

                                local liveEntry = buildLiveEntry(fullType, liveData, group.origin, nil, nil)
                                catalog.total = catalog.total + 1
                                catalog.modules[liveEntry.moduleName] = (catalog.modules[liveEntry.moduleName] or 0) + 1
                                catalog.categories[liveEntry.category] = (catalog.categories[liveEntry.category] or 0) + 1
                                for _, tag in ipairs(liveEntry.tags or {}) do
                                    catalog.tags[tag] = (catalog.tags[tag] or 0) + 1
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    Registry.state.loaded = true
    Registry.state.activeModsHash = activeState.activeModsHash
    Registry.state.catalog = catalog
    Registry.state.lastIndex = indexData

    return catalog
end

function Registry.loadCatalogFromCache()
    local activeState = buildActiveModState()
    local indexData = loadIndex()
    local valid, reason = validateIndex(indexData, activeState)
    if not valid then
        debugLog("Cache load skipped because index validation failed: " .. tostring(reason))
        return nil
    end
    debugLog("Loading DT_Items cache from " .. Registry.OUTPUT_HINT .. " using hash " .. tostring(activeState.activeModsHash))
    return populateMasterList(indexData, activeState)
end

function Registry.rebuildCache(reason)
    local runtimeRules = ensureRuntimeRules()
    if runtimeRules and runtimeRules.reset then
        runtimeRules.reset()
        runtimeRules.loaded = false
    end

    local activeState = buildActiveModState()
    local previousIndex = loadIndex()
    local rebuildReason = tostring(reason or "rebuild")
    log("Info", "Rebuilding DT_Items runtime cache (" .. rebuildReason .. ") from live item data.")
    debugLog("Active mods hash: " .. tostring(activeState.activeModsHash))

    local generatedItems = collectGeneratedItems()
    if not hasEntries(generatedItems) then
        log("Warn", "Runtime cache rebuild produced no live items. Falling back to the previous cache if available.")
        writeRebuildRequest(rebuildReason, activeState, previousIndex, "Runtime rebuild produced no items and kept the previous DT_Items cache if one was available.")
        if previousIndex and type(previousIndex.files) == "table" and #previousIndex.files > 0 then
            return populateMasterList(previousIndex, activeState)
        end
        return buildEmptyCatalog(activeState, "runtime-rebuild-empty")
    end

    local mergedItems = generatedItems
    if previousIndex and type(previousIndex.files) == "table" and #previousIndex.files > 0 then
        mergedItems = mergeStoredAndGenerated(loadStoredItems(previousIndex), generatedItems, activeState)
    end

    local grouped = groupForWrite(mergedItems)
    if not hasEntries(grouped) then
        log("Warn", "Runtime cache rebuild failed to group generated items for DT_Items persistence.")
        writeRebuildRequest(rebuildReason, activeState, previousIndex, "Runtime rebuild failed while grouping generated DT_Items.")
        if previousIndex and type(previousIndex.files) == "table" and #previousIndex.files > 0 then
            return populateMasterList(previousIndex, activeState)
        end
        return buildEmptyCatalog(activeState, "runtime-rebuild-grouping-failed")
    end

    local sourceManifestHash = buildSourceManifestHash(mergedItems, activeState)
    local indexData = writeGroupedFiles(grouped, activeState, sourceManifestHash)
    if type(indexData) ~= "table" or type(indexData.files) ~= "table" or #indexData.files == 0 then
        log("Warn", "Runtime cache rebuild could not persist DT_Items files. Falling back to the previous cache if available.")
        writeRebuildRequest(rebuildReason, activeState, previousIndex, "Runtime rebuild failed while writing DT_Items files.")
        if previousIndex and type(previousIndex.files) == "table" and #previousIndex.files > 0 then
            return populateMasterList(previousIndex, activeState)
        end
        return buildEmptyCatalog(activeState, "runtime-rebuild-write-failed")
    end

    Registry.state.lastRequestKey = nil
    log("Info", "Rebuilt DT_Items runtime cache with " .. tostring(#indexData.files) .. " files for " .. tostring(activeState.activeModsHash) .. ".")
    return populateMasterList(indexData, activeState)
end

function Registry.ensureLoaded(forceRebuild)
    local activeState = buildActiveModState()
    if not forceRebuild
        and Registry.state.loaded
        and Registry.state.activeModsHash == activeState.activeModsHash
        and type(Registry.state.catalog) == "table" then
        return Registry.state.catalog
    end

    local indexData = loadIndex()
    local valid, reason = validateIndex(indexData, activeState)
    if forceRebuild or not valid then
        if forceRebuild then
            log("Info", "Forced DT_Items runtime rebuild requested.")
        else
            if reason == "mods" then
                local addedMods, removedMods = diffActiveMods(indexData and indexData.activeMods or {}, activeState.activeMods)
                local parts = {}
                if #addedMods > 0 then
                    parts[#parts + 1] = "new mods found: " .. table.concat(addedMods, ", ")
                end
                if #removedMods > 0 then
                    parts[#parts + 1] = "removed mods: " .. table.concat(removedMods, ", ")
                end
                local extra = #parts > 0 and (" | " .. table.concat(parts, " | ")) or ""
                log("Warn", "DT_Items cache invalidated by active mod change; regenerating runtime cache." .. extra)
            else
                log("Warn", "DT_Items cache invalidated (" .. tostring(reason) .. "); regenerating " .. Registry.OUTPUT_HINT)
            end
        end
        return Registry.rebuildCache(forceRebuild and "forced" or reason)
    end

    debugLog("DT_Items cache already valid; loading from " .. Registry.OUTPUT_HINT)
    return populateMasterList(indexData, activeState)
end

return Registry
