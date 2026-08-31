require "MarketSense/MS_PublicAPI"
require "PsychopatzCore/UI/PsychopatzUI"
require "MarketSense/MS_ItemCatalogDebug_PriceFormatting"

MarketSense = MarketSense or {}

local UI = PsychopatzCore.UI
local Theme = UI.Theme
local Layout = UI.Layout
local PriceFormatting = require "MarketSense/MS_ItemCatalogDebug_PriceFormatting"

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

local TEXT_FALLBACKS = {
    UI_MarketSenseCatalog_Title = "MarketSense Item Test Catalog",
    UI_MarketSenseCatalog_ToolTitle = "MarketSense Item Catalog",
    UI_MarketSenseCatalog_Collapse = "Collapse all",
    UI_MarketSenseCatalog_Expand = "Expand all",
    UI_MarketSenseCatalog_Refresh = "Refresh catalog",
    UI_MarketSenseCatalog_Generate = "Generate MarketSense catalog",
    UI_MarketSenseCatalog_BaseItemLabel = "Base item",
    UI_MarketSenseCatalog_BasePriceLabel = "base price",
}

local DISPLAY_NAME_CACHE = {}

local function tr(key, fallback)
    if type(getText) == "function" then
        local ok, value = pcall(getText, key)
        if ok and value and value ~= key and value ~= "" then
            return value
        end
    end
    return fallback or TEXT_FALLBACKS[key] or key
end

local function trFormat(key, fallback, ...)
    if type(getText) == "function" then
        local ok, value = pcall(getText, key, ...)
        if ok and value and value ~= key and value ~= "" then
            return value
        end
    end
    return string.format(fallback or TEXT_FALLBACKS[key] or key, ...)
end

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function timestampMs()
    if type(getTimestampMs) ~= "function" then return nil end
    local ok, value = pcall(getTimestampMs)
    return ok and tonumber(value) or nil
end

local function contains(list, value)
    for _, existing in ipairs(list or {}) do
        if existing == value then return true end
    end
    return false
end

local function appendUnique(list, value)
    value = tostring(value or "")
    if value ~= "" and not contains(list, value) then
        list[#list + 1] = value
    end
end

local function shortToken(token, root)
    token = tostring(token or "")
    root = tostring(root or "")
    if token == root then return root end
    if root ~= "" and string.sub(token, 1, #root) == root then
        token = string.sub(token, #root + 1)
    end
    return token ~= "" and token or root
end

local function tagList(row)
    return row.expandedTags or row.tags or {}
end

local function hasToken(row, token)
    if row.primary == token then return true end
    for _, value in ipairs(tagList(row)) do
        if tostring(value) == token then return true end
    end
    return false
end

local function categoryPath(row)
    local root = tostring(row.category or "Misc")
    local primary = tostring(row.primary or "")
    local path = { root }
    local flat = {}
    local seen = {}

    for _, value in ipairs(tagList(row)) do
        local token = tostring(value or "")
        if token ~= "" and not string.find(token, ".", 1, true)
            and not seen[token]
        then
            seen[token] = true
            flat[#flat + 1] = token
        end
    end

    -- Expanded tags are stored leaf-first. Reverse them to get the visual
    -- path while omitting the leaf item subtype from the group header.
    for index = #flat, 1, -1 do
        local token = flat[index]
        if token ~= root and token ~= primary then
            local label = shortToken(token, root)
            if label ~= root then appendUnique(path, label) end
        end
    end

    if root == "Weapon" then
        local ammo = string.sub(primary, 1, 4) == "Ammo"
            or hasToken(row, "Ammo")
            or hasToken(row, "AmmoBox")
            or hasToken(row, "AmmoCarton")
            or hasToken(row, "AmmoMag")
        local firearm = string.sub(primary, 1, 7) == "Firearm"
            or hasToken(row, "Firearm")
        local ranged = contains(path, "Ranged")

        if ammo then
            if not ranged then table.insert(path, 2, "Ranged") end
            appendUnique(path, "Ammo")
        elseif firearm then
            if not ranged then table.insert(path, 2, "Ranged") end
            appendUnique(path, "Firearm")
        elseif #path == 1 and primary ~= "" then
            appendUnique(path, shortToken(primary, root))
        end
    end

    -- Root-only branches such as ContainerBag still have a useful display
    -- definition even when their expanded tag list has no separate parent.
    if #path == 1 and primary ~= "" and MarketSense.TagMapper
        and type(MarketSense.TagMapper.getDefinition) == "function"
    then
        local ok, definition = pcall(MarketSense.TagMapper.getDefinition, primary)
        local subcategory = ok and definition and definition.subcategory or nil
        if subcategory and subcategory ~= "" and subcategory ~= "Root"
            and subcategory ~= "General"
        then
            appendUnique(path, subcategory)
        end
    end

    return path
end

local function safeItemDisplayName(fullType)
    local cached = DISPLAY_NAME_CACHE[fullType]
    if cached then return cached end
    if type(getItemDisplayName) == "function" then
        local ok, value = pcall(getItemDisplayName, fullType)
        if ok and value and tostring(value) ~= "" then
            local result = tostring(value)
            DISPLAY_NAME_CACHE[fullType] = result
            return result
        end
    end
    local name = string.match(tostring(fullType or ""), "[^%.]+$")
    name = name or tostring(fullType or "-")
    DISPLAY_NAME_CACHE[fullType] = name
    return name
end

local function displaySource(row)
    local source = tostring(row.sourceModId or row.sourceModName or "")
    if source == "Vanilla" or source == "Base"
        or source == "Project Zomboid (Vanilla)"
    then
        return "Vanilla"
    end
    return source
end

local function displayTags(row)
    local values = {}
    local primary = tostring(row.primary or "")
    for _, value in ipairs(row.tags or {}) do
        value = tostring(value or "")
        if value ~= "" and value ~= primary then
            local dot = string.find(value, ".", 1, true)
            if dot then value = string.sub(value, dot + 1) end
            appendUnique(values, value)
        end
    end
    local text = primary ~= "" and primary or tostring(row.category or "Misc")
    if #values > 0 then text = text .. ", " .. table.concat(values, ", ") end
    local source = displaySource(row)
    if source ~= "" then text = text .. ", " .. source end
    return text
end

local function joinText(values, separator)
    local result = {}
    for _, value in ipairs(values or {}) do
        if value ~= nil then result[#result + 1] = tostring(value) end
    end
    return table.concat(result, separator or " ")
end

local function rowSearchText(row)
    local values = {
        row.fullType, row.displayName, row.category, row.primary,
        row.sourceModId, row.sourceModName,
        joinText(row.tags, " "),
        joinText(row.expandedTags, " "),
    }
    return lower(joinText(values, " "))
end

local function yieldSummary(details)
    local yield = details and details.yieldResolution
    if type(yield) ~= "table" then return nil end

    local status = lower(yield.status)
    local label = tr("UI_MarketSenseCatalog_YieldLabel", "Yield")
    if status == "resolved" then
        local outputs = {}
        for _, output in ipairs(yield.outputs or {}) do
            local quantity = tonumber(output.quantity) or 0
            local fullType = tostring(output.fullType or "?")
            outputs[#outputs + 1] = string.format("%g x %s", quantity, fullType)
        end
        if #outputs > 0 then
            local recipe = tostring(yield.recipe or "recipe")
            local suffix = yield.evaluation == "fallback" and " [fallback]" or ""
            return string.format("%s: %s -> %s%s", label, recipe,
                table.concat(outputs, ", "), suffix)
        end
    end

    if status == "ambiguous" or status == "unresolved" then
        local candidateNames = {}
        for _, candidate in ipairs(yield.candidates or {}) do
            local name = tostring(candidate.recipe or "")
            if name ~= "" and #candidateNames < 3 then
                candidateNames[#candidateNames + 1] = name
            end
        end
        local suffix = #candidateNames > 0
            and (": " .. table.concat(candidateNames, ", ")) or ""
        return string.format("%s: %s (%d candidates)%s", label,
            string.upper(status), tonumber(yield.candidateCount) or 0, suffix)
    end

    if status == "not_detected" then
        return string.format("%s: NOT_DETECTED (%d recipes, %d sources indexed)",
            label, tonumber(yield.recipeCount) or 0,
            tonumber(yield.sourceCount) or 0)
    end

    return string.format("%s: %s", label,
        status ~= "" and status or "not detected")
end

local function registryDetails(fullType)
    if fullType == "" or fullType == "?" then return nil end
    if not MarketSense or type(MarketSense.GetRegistryDetails) ~= "function" then
        return nil
    end
    local ok, result = pcall(MarketSense.GetRegistryDetails, fullType)
    return ok and type(result) == "table" and result or nil
end

local function baseItemSummary(details)
    local yield = details and details.yieldResolution
    if type(yield) ~= "table" or lower(yield.status) ~= "resolved" then
        return nil
    end

    local outputs = {}
    local basePriceLabel = tr("UI_MarketSenseCatalog_BasePriceLabel", "base price")
    for _, output in ipairs(yield.outputs or {}) do
        local quantity = tonumber(output.quantity) or 0
        local fullType = tostring(output.fullType or "?")
        local registry = registryDetails(fullType)
        local basePrice = tonumber(output.basePrice)
            or (registry and tonumber(registry.basePrice))
        local priceText = basePrice ~= nil
            and string.format("%s=$%g", basePriceLabel, basePrice)
            or string.format("%s=?", basePriceLabel)
        outputs[#outputs + 1] = string.format("%g x %s [%s] (%s)",
            quantity, safeItemDisplayName(fullType), fullType, priceText)
    end

    if #outputs == 0 then return nil end
    return string.format("%s: %s",
        tr("UI_MarketSenseCatalog_BaseItemLabel", "Base item"),
        table.concat(outputs, ", "))
end

local function buildDetailSubtext(details)
    local baseText = baseItemSummary(details)
    local yieldText = yieldSummary(details)
    local heuristicText = PriceFormatting.priceHeuristicSummary(details)
    local marketText = PriceFormatting.marketModifierSummary(details)
    local descriptorText = PriceFormatting.descriptorSummary(details)
    local diagnostics
    if yieldText and heuristicText then
        local model = details and details.priceHeuristic
            and tostring(details.priceHeuristic.model or "") or ""
        if model == "tool_v2" or model == "weapon_v2" then
            diagnostics = heuristicText .. " | " .. yieldText
        else
            diagnostics = yieldText .. " | " .. heuristicText
        end
    else
        diagnostics = yieldText or heuristicText
    end
    if marketText and diagnostics then
        diagnostics = diagnostics .. " | " .. marketText
    elseif marketText then
        diagnostics = marketText
    end
    if descriptorText and diagnostics then
        diagnostics = diagnostics .. " | " .. descriptorText
    elseif descriptorText then
        diagnostics = descriptorText
    end
    if baseText and diagnostics then return baseText .. " | " .. diagnostics end
    return baseText or diagnostics
end

local function drawMarketItemRow(list, y, entry, alternate)
    local row = entry.item.item
    local height = entry.height or list.itemheight
    UI.DrawListSelection(list, y, height,
        list.selected == entry.index, alternate)

    UI.ImageResolver.DrawItemIcon(list, row.fullType, 8, y + 5, 34, 34, 1)

    local right = list:getWidth() - 12
    local priceText = string.format("$%d", math.floor(tonumber(row.price) or 0))
    local badgeWidth = Theme.TextWidth(UIFont.Small, priceText) + 12
    UI.DrawBadge(list, priceText, right, y + 7, "success")

    local x = 52
    local titleWidth = math.max(40, right - badgeWidth - x - 10)
    local title = Layout.Ellipsize(row.displayName or row.fullType,
        UIFont.Small, titleWidth)
    local subtitle = Layout.Ellipsize(row._displayTags or displayTags(row),
        UIFont.Small, titleWidth)
    local text = Theme.colors.text
    local muted = Theme.colors.textMuted
    list:drawText(title, x, y + 6, text.r, text.g, text.b, text.a, UIFont.Small)
    list:drawText(subtitle, x, y + 24,
        muted.r, muted.g, muted.b, muted.a, UIFont.Small)
    return y + height
end

return {
    CATEGORY_ORDER = CATEGORY_ORDER,
    tr = tr,
    trFormat = trFormat,
    lower = lower,
    timestampMs = timestampMs,
    categoryPath = categoryPath,
    safeItemDisplayName = safeItemDisplayName,
    displayTags = displayTags,
    rowSearchText = rowSearchText,
    yieldSummary = yieldSummary,
    baseItemSummary = baseItemSummary,
    priceHeuristicSummary = PriceFormatting.priceHeuristicSummary,
    marketModifierSummary = PriceFormatting.marketModifierSummary,
    descriptorSummary = PriceFormatting.descriptorSummary,
    buildDetailSubtext = buildDetailSubtext,
    drawMarketItemRow = drawMarketItemRow,
}
