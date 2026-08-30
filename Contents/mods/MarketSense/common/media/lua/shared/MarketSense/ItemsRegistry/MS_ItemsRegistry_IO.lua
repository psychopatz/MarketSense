local Shared = require "MarketSense/ItemsRegistry/MS_ItemsRegistry_Shared"

local IO = {}
local Registry = Shared.Registry
local Core = Shared.Core
local TagUtils = Shared.TagUtils
local Config = Shared.Config

local function skipWhitespace(text, position)
    while position <= #text do
        local character = string.sub(text, position, position)
        if character ~= " " and character ~= "\t" then break end
        position = position + 1
    end
    return position
end

local function readQuoted(text, position)
    position = skipWhitespace(text, position)
    if string.sub(text, position, position) ~= '"' then
        return nil, position
    end

    position = position + 1
    local result = {}
    while position <= #text do
        local character = string.sub(text, position, position)
        if character == '"' then
            return table.concat(result), position + 1
        end
        if character == "\\" then
            local escaped = string.sub(text, position + 1, position + 1)
            if escaped == "n" then
                result[#result + 1] = "\n"
            elseif escaped == "r" then
                result[#result + 1] = "\r"
            elseif escaped == "t" then
                result[#result + 1] = "\t"
            else
                result[#result + 1] = escaped
            end
            position = position + 2
        else
            result[#result + 1] = character
            position = position + 1
        end
    end
    return nil, position
end

local function readStringField(line, key)
    local position = skipWhitespace(line, 1)
    if string.sub(line, position, position + #key - 1) ~= key then
        return nil
    end
    position = skipWhitespace(line, position + #key)
    if string.sub(line, position, position) ~= "=" then
        return nil
    end
    local value = readQuoted(line, position + 1)
    return value
end

local function readFileEntry(line)
    local position = skipWhitespace(line, 1)
    if string.sub(line, position, position) ~= "{" then
        return nil
    end
    position = position + 1

    local entry = {}
    local fields = { "root", "category", "subcategory", "leaf", "primaryPrefix", "path" }
    for index, key in ipairs(fields) do
        position = skipWhitespace(line, position)
        if string.sub(line, position, position + #key - 1) ~= key then
            return nil
        end
        position = skipWhitespace(line, position + #key)
        if string.sub(line, position, position) ~= "=" then
            return nil
        end
        local value
        value, position = readQuoted(line, position + 1)
        if value == nil then return nil end
        entry[key] = value
        position = skipWhitespace(line, position)
        if index < #fields then
            if string.sub(line, position, position) ~= "," then
                return nil
            end
            position = position + 1
        end
    end
    return entry
end

-- The runtime cache is written under Zomboid/Lua, where PZ deliberately does
-- not expose load/loadstring.  Keep the existing .txt manifest shape for
-- tooling compatibility, but parse only the fields emitted by serializeIndex
-- instead of executing arbitrary file contents.
function IO.parseLuaTableFile(path)
    local reader = getFileReader(path, false)
    if not reader then
        return nil
    end

    local data = {
        activeMods = {},
        files = {},
    }
    local section = nil
    local line = reader:readLine()
    while line do
        local text = Shared.trim(line)
        if text == "activeMods = {" then
            section = "activeMods"
        elseif text == "files = {" then
            section = "files"
        elseif section == "activeMods" then
            if string.sub(text, 1, 1) == "}" then
                section = nil
            else
                local value = readQuoted(text, 1)
                if value ~= nil and value ~= "" then
                    data.activeMods[#data.activeMods + 1] = value
                end
            end
        elseif section == "files" then
            if string.sub(text, 1, 1) == "}" then
                section = nil
            else
                local entry = readFileEntry(text)
                if entry ~= nil then
                    data.files[#data.files + 1] = entry
                end
            end
        else
            local numericFields = {
                "schemaVersion", "generatorVersion", "pricingHeuristicVersion",
            }
            for _, key in ipairs(numericFields) do
                local value = string.match(text,
                    "^" .. key .. "%s*=%s*([%d%.%-]+)")
                if value ~= nil then data[key] = tonumber(value) end
            end
            local stringFields = {
                "generatedAt", "activeModsHash", "signatureVersion",
                "gameVersion", "sourceManifestHash",
            }
            for _, key in ipairs(stringFields) do
                local value = readStringField(text, key)
                if value ~= nil then data[key] = value end
            end
        end
        line = reader:readLine()
    end
    reader:close()

    if data.schemaVersion == nil and #data.files == 0
        and #data.activeMods == 0 then
        return nil
    end
    return data
end

function IO.serializeIndex(indexData)
    local lines = {
        "return {",
        "    schemaVersion = " .. tostring(indexData.schemaVersion or Registry.SCHEMA_VERSION) .. ",",
        "    generatedAt = " .. Shared.quoteString(indexData.generatedAt or "") .. ",",
        "    activeModsHash = " .. Shared.quoteString(indexData.activeModsHash or "") .. ",",
        "    generatorVersion = " .. tostring(indexData.generatorVersion or Registry.GENERATOR_VERSION) .. ",",
        "    signatureVersion = " .. Shared.quoteString(indexData.signatureVersion or Registry.SIGNATURE_VERSION) .. ",",
        "    pricingHeuristicVersion = " .. tostring(indexData.pricingHeuristicVersion or Registry.PRICING_HEURISTIC_VERSION) .. ",",
    }

    if indexData.gameVersion ~= nil then
        lines[#lines + 1] = "    gameVersion = " .. Shared.quoteString(indexData.gameVersion or "") .. ","
    end
    if indexData.sourceManifestHash ~= nil then
        lines[#lines + 1] = "    sourceManifestHash = " .. Shared.quoteString(indexData.sourceManifestHash or "") .. ","
    end

    lines[#lines + 1] = "    activeMods = {"
    for _, modId in ipairs(indexData.activeMods or {}) do
        lines[#lines + 1] = "        " .. Shared.quoteString(modId) .. ","
    end
    lines[#lines + 1] = "    },"

    lines[#lines + 1] = ""
    lines[#lines + 1] = "    files = {"

    for _, fileEntry in ipairs(indexData.files or {}) do
        lines[#lines + 1] = "        { root = " .. Shared.quoteString(fileEntry.root or fileEntry.category) ..
            ", category = " .. Shared.quoteString(fileEntry.category) ..
            ", subcategory = " .. Shared.quoteString(fileEntry.subcategory) ..
            ", leaf = " .. Shared.quoteString(fileEntry.leaf or "General") ..
            ", primaryPrefix = " .. Shared.quoteString(fileEntry.primaryPrefix or "") ..
            ", path = " .. Shared.quoteString(fileEntry.path) .. " },"
    end

    lines[#lines + 1] = "    }"
    lines[#lines + 1] = "}"
    return table.concat(lines, "\r\n") .. "\r\n"
end

function IO.writeFile(path, content)
    local writer = getFileWriter(path, true, false)
    if not writer then
        Shared.log("Warn", "Failed to open cache file for writing: " .. tostring(path) .. " (expected under " .. Registry.OUTPUT_HINT .. ")")
        return false
    end
    writer:write(content or "")
    writer:close()
    Shared.debugLog("Wrote cache file: " .. tostring(path))
    return true
end

function IO.writeRebuildRequest(reason, activeState, previousIndex, extra)
    local activeHash = tostring(activeState and activeState.activeModsHash or "")
    local requestKey = tostring(reason or "unknown") .. "|" .. activeHash
    if Registry.state.lastRequestKey == requestKey then
        return false
    end

    local addedMods = {}
    local removedMods = {}
    if previousIndex and type(previousIndex.activeMods) == "table" and activeState then
        addedMods, removedMods = Shared.diffActiveMods(previousIndex.activeMods, activeState.activeMods)
    end

    local lines = {
        "{",
        "  \"requestedAt\": " .. Shared.jsonString(Shared.getTimestamp()) .. ",",
        "  \"reason\": " .. Shared.jsonString(reason or "unknown") .. ",",
        "  \"expected\": {",
        "    \"schemaVersion\": " .. tostring(Registry.SCHEMA_VERSION) .. ",",
        "    \"generatorVersion\": " .. tostring(Registry.GENERATOR_VERSION) .. ",",
        "    \"signatureVersion\": " .. Shared.jsonString(Registry.SIGNATURE_VERSION) .. ",",
        "    \"pricingHeuristicVersion\": " .. tostring(Registry.PRICING_HEURISTIC_VERSION),
        "  },",
        "  \"activeModsHash\": " .. Shared.jsonString(activeHash) .. ",",
        "  \"activeMods\": [",
    }

    for index, modId in ipairs(activeState and activeState.activeMods or {}) do
        local suffix = index < #(activeState.activeMods or {}) and "," or ""
        lines[#lines + 1] = "    " .. Shared.jsonString(modId) .. suffix
    end

    lines[#lines + 1] = "  ],"
    lines[#lines + 1] = "  \"addedMods\": ["
    for index, modId in ipairs(addedMods) do
        local suffix = index < #addedMods and "," or ""
        lines[#lines + 1] = "    " .. Shared.jsonString(modId) .. suffix
    end
    lines[#lines + 1] = "  ],"
    lines[#lines + 1] = "  \"removedMods\": ["
    for index, modId in ipairs(removedMods) do
        local suffix = index < #removedMods and "," or ""
        lines[#lines + 1] = "    " .. Shared.jsonString(modId) .. suffix
    end
    lines[#lines + 1] = "  ]"

    if extra and extra ~= "" then
        lines[#lines] = lines[#lines] .. ","
        lines[#lines + 1] = "  \"message\": " .. Shared.jsonString(extra)
    end

    lines[#lines + 1] = "}"

    if IO.writeFile(Registry.REQUEST_PATH, table.concat(lines, "\n")) then
        Registry.state.lastRequestKey = requestKey
        return true
    end

    return false
end

function IO.loadIndex()
    local indexData = IO.parseLuaTableFile(Registry.INDEX_PATH)
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

function IO.sortFileEntries(files)
    table.sort(files, function(left, right)
        local leftOrder = Shared.CATEGORY_ORDER[left.root or left.category] or 999
        local rightOrder = Shared.CATEGORY_ORDER[right.root or right.category] or 999
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

function IO.parseLeanFile(path)
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
        local text = Shared.trim(line)

        if text == "" then
            flushCurrent()
        elseif Shared.startsWith(text, "#") then
            local meta = Shared.trim(string.sub(text, 2))
            local key, value = string.match(meta, "^([^=]+)=(.*)$")
            key = Shared.trim(key)
            value = Shared.trim(value)
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
        elseif Shared.startsWith(text, "@origin=") then
            if current and #current.items > 0 then
                flushCurrent()
            end
            current = current or { items = {} }
            current.origin = Shared.trim(string.sub(text, 9))
        elseif Shared.startsWith(text, "@tags=") then
            if current and #current.items > 0 then
                flushCurrent()
            end
            current = current or { items = {} }
            current.tags = {}
            for _, tag in ipairs(Shared.split(string.sub(text, 7), "|")) do
                local cleaned = Shared.trim(tag)
                if cleaned ~= "" then
                    current.tags[#current.tags + 1] = cleaned
                end
            end
            current.tags = TagUtils.unique(current.tags)
        else
            local parts = Shared.split(text, "|")
            local fullType = Shared.trim(parts[1])
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

function IO.loadStoredItems(indexData)
    local items = {}
    for _, fileEntry in ipairs(indexData and indexData.files or {}) do
        local parsed = IO.parseLeanFile(fileEntry.path)
        if parsed then
            for _, group in ipairs(parsed.groups or {}) do
                local tags = TagUtils.unique(group.tags or {})
                local primary = Shared.getPrimaryTag(tags)
                for _, row in ipairs(group.items or {}) do
                    local fullType = tostring(row[1] or "")
                    if fullType ~= "" then
                        items[fullType] = {
                            item = fullType,
                            basePrice = tonumber(row[2]) or (Config.pricing.minPrice or 1),
                            tags = Shared.copyArray(tags),
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

function IO.validateIndex(indexData, activeState)
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
    if activeState.gameVersion and Shared.trim(indexData.gameVersion or "") ~= "" and tostring(indexData.gameVersion) ~= tostring(activeState.gameVersion) then
        return false, "game"
    end
    if Shared.trim(indexData.sourceManifestHash or "") == "" then
        return false, "manifest"
    end
    if type(indexData.files) ~= "table" or #indexData.files == 0 then
        return false, "files"
    end
    return true, "ok"
end

return IO
