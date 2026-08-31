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
    UI_MarketSenseCatalog_Filter = "Filter taxonomy",
    UI_MarketSenseCatalog_FilterAll = "All market items",
    UI_MarketSenseCatalog_FilterCategory = "Category: %s",
    UI_MarketSenseCatalog_FilterSubcategory = "Subcategory: %s",
    UI_MarketSenseCatalog_FilterTheme = "Theme: %s",
    UI_MarketSenseCatalog_FilterOrigin = "Origin: %s",
    UI_MarketSenseCatalog_BaseItemLabel = "Base item",
    UI_MarketSenseCatalog_BasePriceLabel = "base price",
    UI_MarketSenseCatalog_SelectedHeader = "%s  |  Catalog price: $%d  |  %s",
    UI_MarketSenseCatalog_DetailClassification = "Classification",
    UI_MarketSenseCatalog_DetailPricingModel = "Pricing model",
    UI_MarketSenseCatalog_DetailHeuristic = "Heuristic score (not dollars)",
    UI_MarketSenseCatalog_DetailAdjustments = "Price adjustments",
    UI_MarketSenseCatalog_DetailThemeTag = "theme/tag",
    UI_MarketSenseCatalog_DetailEvidence = "Evidence",
    UI_MarketSenseCatalog_DetailVariant = "Nutrition source",
    UI_MarketSenseCatalog_DescriptionCategory = "Category",
    UI_MarketSenseCatalog_DescriptionQuality = "Quality",
    UI_MarketSenseCatalog_DescriptionRarity = "Rarity",
    UI_MarketSenseCatalog_DescriptionTheme = "Theme",
    UI_MarketSenseCatalog_DescriptionOrigin = "Origin",
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
        -- PZ versions differ on whether getText consumes format arguments.
        -- Read the translated template first, then format it here so a
        -- literal "%s" never leaks into the catalog UI.
        local ok, value = pcall(getText, key)
        if ok and value and value ~= key and value ~= "" then
            local formatted, result = pcall(string.format, tostring(value), ...)
            return formatted and result or tostring(value)
        end
    end
    local template = fallback or TEXT_FALLBACKS[key] or key
    local formatted, result = pcall(string.format, template, ...)
    return formatted and result or tostring(template)
end

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function demandText(value)
    if value == nil then return "-" end
    return string.format("%.2f", tonumber(value) or 0)
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

local FILTER_KIND_ORDER = {
    all = 0,
    category = 1,
    subcategory = 2,
    theme = 3,
    origin = 4,
}

local function filterKey(kind, value)
    return lower(kind) .. "\31" .. lower(value)
end

local function addFilterOption(optionsByKey, kind, value, label)
    value = tostring(value or "")
    if value == "" then return end
    local key = filterKey(kind, value)
    if optionsByKey[key] then return end
    optionsByKey[key] = {
        key = key,
        kind = kind,
        value = value,
        label = label,
    }
end

local function subcategoryValue(row)
    local path = row and (row.categoryPath or categoryPath(row)) or {}
    local category = tostring(row.category or path[1] or "Misc")
    local value = tostring(row.subcategory or path[2] or "")
    if value == "" or value == "Root" or value == "General" then
        return nil
    end
    if string.sub(value, 1, #category + 1) == category .. "." then
        return value
    end
    return category .. "." .. value
end

local function descriptorValuesForRow(row, prefix, field)
    local values = {}
    local seen = {}
    local function append(value)
        value = tostring(value or "")
        if value ~= "" and not seen[lower(value)] then
            seen[lower(value)] = true
            values[#values + 1] = value
        end
    end

    local fields = type(field) == "table" and field or { field }
    for _, fieldName in ipairs(fields) do
        if row and fieldName and row[fieldName] ~= nil then
            if type(row[fieldName]) == "table" then
                for _, value in ipairs(row[fieldName]) do append(value) end
            else
                append(row[fieldName])
            end
        end
    end

    local marker = tostring(prefix or "") .. "."
    for _, tag in ipairs(tagList(row)) do
        local text = tostring(tag or "")
        if string.sub(text, 1, #marker) == marker then
            append(string.sub(text, #marker + 1))
        end
    end
    return values
end

local function validTaxonomyPart(value)
    value = tostring(value or "")
    return value ~= "" and value ~= "Root" and value ~= "General"
end

local function normalizeTaxonomyPart(value, category)
    value = tostring(value or "")
    category = tostring(category or "")
    if category ~= "" and string.sub(value, 1, #category + 1)
        == category .. "." then
        value = string.sub(value, #category + 2)
    end
    return value
end

local function prettyTaxonomyPart(value)
    value = tostring(value or "")
    value = string.gsub(value, "([a-z0-9])([A-Z])", "%1 %2")
    value = string.gsub(value, "([A-Z]+)([A-Z][a-z])", "%1 %2")
    value = string.gsub(value, "[_%-]+", " ")
    return value
end

local function categoryDescription(row)
    row = row or {}
    local path = row.categoryPath
    if type(path) ~= "table" then path = categoryPath(row) end

    local values = {}
    for _, value in ipairs(path or {}) do
        if validTaxonomyPart(value) then appendUnique(values, value) end
    end

    local category = tostring(row.category or values[1] or "Misc")
    local subcategory = normalizeTaxonomyPart(row.subcategory, category)
    if validTaxonomyPart(subcategory) then
        appendUnique(values, subcategory)
    end

    local leaf = normalizeTaxonomyPart(row.leaf, category)
    if validTaxonomyPart(leaf) then
        appendUnique(values, leaf)
    end

    -- Runtime-generated rows can omit persisted subcategory/leaf fields.
    -- Derive the readable leaf from the same flat primary token used by the
    -- classifier, without exposing the implementation prefix when possible.
    if #values == 0 then appendUnique(values, category) end
    if #values == 1 then
        local primary = tostring(row.primary or "")
        local candidates = {
            category,
            subcategory,
        }
        for _, prefix in ipairs(candidates) do
            prefix = tostring(prefix or "")
            if prefix ~= "" and #primary > #prefix
                and string.sub(primary, 1, #prefix) == prefix
            then
                appendUnique(values, string.sub(primary, #prefix + 1))
                break
            end
        end
    end

    local displayValues = {}
    for _, value in ipairs(values) do
        displayValues[#displayValues + 1] = prettyTaxonomyPart(value)
    end
    return table.concat(displayValues, " > ")
end

local function labeledDescriptor(row, prefix, field, labelKey, fallback)
    local values = descriptorValuesForRow(row, prefix, field)
    if #values == 0 then return nil end
    local displayValues = {}
    for _, value in ipairs(values) do
        displayValues[#displayValues + 1] = prettyTaxonomyPart(value)
    end
    return tr(labelKey, fallback) .. ": " .. table.concat(displayValues, ", ")
end

local function originValue(row)
    local value = row and row.origin or nil
    if value == nil or tostring(value) == "" then
        value = row and (row.sourceModId or row.sourceModName) or nil
    end
    value = tostring(value or "")
    return value ~= "" and value or nil
end

local function buildFilterOptions(items)
    local optionsByKey = {}

    for _, row in ipairs(items or {}) do
        local path = row.categoryPath or categoryPath(row)
        local category = tostring(row.category or path[1] or "Misc")
        if category ~= "" then
            addFilterOption(optionsByKey, "category", category,
                trFormat("UI_MarketSenseCatalog_FilterCategory",
                    "Category: %s", category))
        end

        local subcategory = subcategoryValue(row)
        if subcategory then
            addFilterOption(optionsByKey, "subcategory", subcategory,
                trFormat("UI_MarketSenseCatalog_FilterSubcategory",
                    "Subcategory: %s", subcategory))
        end

        for _, theme in ipairs(descriptorValuesForRow(row, "Theme", "theme")) do
            addFilterOption(optionsByKey, "theme", theme,
                trFormat("UI_MarketSenseCatalog_FilterTheme",
                    "Theme: %s", theme))
        end

        local origin = originValue(row)
        if origin then
            addFilterOption(optionsByKey, "origin", origin,
                trFormat("UI_MarketSenseCatalog_FilterOrigin",
                    "Origin: %s", origin))
        end
    end

    local options = {
        {
            key = "all",
            kind = "all",
            value = "",
            label = tr("UI_MarketSenseCatalog_FilterAll", "All market items"),
        },
    }
    for _, option in pairs(optionsByKey) do
        options[#options + 1] = option
    end

    table.sort(options, function(left, right)
        if left.kind ~= right.kind then
            return (FILTER_KIND_ORDER[left.kind] or 999)
                < (FILTER_KIND_ORDER[right.kind] or 999)
        end
        if left.kind == "category" and right.kind == "category" then
            local leftOrder = CATEGORY_ORDER[left.value] or 999
            local rightOrder = CATEGORY_ORDER[right.value] or 999
            if leftOrder ~= rightOrder then return leftOrder < rightOrder end
        end
        return lower(left.label) < lower(right.label)
    end)
    return options
end

local function matchesFilter(row, filter)
    if type(filter) ~= "table" or filter.kind == nil
        or filter.kind == "all" then
        return true
    end

    local kind = tostring(filter.kind)
    local value = lower(filter.value)
    if value == "" then return true end

    if kind == "category" then
        return lower(row and row.category) == value
    elseif kind == "subcategory" then
        return lower(subcategoryValue(row)) == value
    elseif kind == "theme" then
        for _, theme in ipairs(descriptorValuesForRow(row, "Theme", "theme")) do
            if lower(theme) == value then return true end
        end
        return false
    elseif kind == "origin" then
        return lower(originValue(row)) == value
    end
    return true
end

local function displayTags(row)
    row = row or {}
    local values = {}
    local category = categoryDescription(row)
    if category ~= "" then
        values[#values + 1] = tr("UI_MarketSenseCatalog_DescriptionCategory",
            "Category") .. ": " .. category
    end

    local quality = labeledDescriptor(row, "Quality", "quality",
        "UI_MarketSenseCatalog_DescriptionQuality", "Quality")
    if quality then values[#values + 1] = quality end

    local rarity = labeledDescriptor(row, "Rarity", "rarity",
        "UI_MarketSenseCatalog_DescriptionRarity", "Rarity")
    if rarity then values[#values + 1] = rarity end

    local theme = labeledDescriptor(row, "Theme", "themes",
        "UI_MarketSenseCatalog_DescriptionTheme", "Theme")
    if theme then values[#values + 1] = theme end

    local origin = labeledDescriptor(row, "Origin", "origin",
        "UI_MarketSenseCatalog_DescriptionOrigin", "Origin")
    if not origin then
        local source = displaySource(row)
        if source ~= "" then
            origin = tr("UI_MarketSenseCatalog_DescriptionOrigin", "Origin")
                .. ": " .. source
        end
    end
    if origin then values[#values + 1] = origin end

    return table.concat(values, " | ")
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

local function formatSigned(value)
    value = tonumber(value)
    if value == nil or value == 0 then return nil end
    return string.format("%+g", value)
end

local function appendDetailLine(lines, labelKey, fallback, value)
    value = tostring(value or "")
    if value == "" then return end
    lines[#lines + 1] = {
        label = tr(labelKey, fallback),
        value = value,
    }
end

local function buildDetailLines(row, details)
    row = row or {}
    details = details or {}
    local heuristic = details.priceHeuristic or {}
    local market = details.marketPricing or {}
    local lines = {}

    local path = row.categoryPath
    if type(path) ~= "table" then path = categoryPath(row) end
    local classification = table.concat(path or {}, " > ")
    local rarity = details.rarity or row.rarity
    if rarity and tostring(rarity) ~= "" then
        classification = classification .. " | rarity=" .. tostring(rarity)
    end
    local themes = details.themes or row.themes
    if type(themes) == "table" and #themes > 0 then
        classification = classification .. " | themes=" .. table.concat(themes, ", ")
    elseif type(row.descriptorEvidence) == "table" then
        local themeNames = {}
        for _, evidence in ipairs(row.descriptorEvidence) do
            local tag = tostring(evidence.tag or "")
            if string.sub(tag, 1, 6) == "Theme." then
                appendUnique(themeNames, string.sub(tag, 7))
            end
        end
        if #themeNames > 0 then
            classification = classification .. " | themes=" .. table.concat(themeNames, ", ")
        end
    end
    appendDetailLine(lines, "UI_MarketSenseCatalog_DetailClassification",
        "Classification", classification)

    local model = tostring(heuristic.model or "")
    local role = tostring(heuristic.role or heuristic.marketRole or "")
    local state = tostring(heuristic.foodCondition or heuristic.freshnessState or "")
    local modelText = model ~= "" and model or "unknown"
    if role ~= "" then modelText = modelText .. " | role=" .. role end
    if state ~= "" then modelText = modelText .. " | state=" .. state end
    appendDetailLine(lines, "UI_MarketSenseCatalog_DetailPricingModel",
        "Pricing model", modelText)

    local heuristicParts = {}
    if heuristic.score ~= nil then
        heuristicParts[#heuristicParts + 1] = string.format("raw=%g", heuristic.score)
    end
    if heuristic.rationUnits ~= nil then
        heuristicParts[#heuristicParts + 1] = string.format("ration=%s",
            demandText(heuristic.rationUnits))
    end
    if heuristic.hungerChange ~= nil then
        heuristicParts[#heuristicParts + 1] = string.format("hunger=%s",
            demandText(heuristic.hungerChange))
    end
    if heuristic.thirstChange ~= nil then
        heuristicParts[#heuristicParts + 1] = string.format("thirst=%s",
            demandText(heuristic.thirstChange))
    end
    appendDetailLine(lines, "UI_MarketSenseCatalog_DetailHeuristic",
        "Heuristic score (not dollars)", table.concat(heuristicParts, " | "))

    local adjustmentParts = {}
    local band = heuristic.categoryBand
    if type(band) == "table" then
        adjustmentParts[#adjustmentParts + 1] = string.format(
            "band=%s $%g-$%g",
            tostring(band.category or row.category or "category"),
            tonumber(band.min) or 0, tonumber(band.max) or 0)
    end
    local additions = {
        { key = "categoryAdd", label = "category" },
        { key = "subcategoryAdd", label = "subcategory" },
        { key = "tagAdd", labelKey = "UI_MarketSenseCatalog_DetailThemeTag" },
        { key = "itemAdd", label = "item" },
    }
    for _, entry in ipairs(additions) do
        local value = formatSigned(market[entry.key])
        if value then
            local label = entry.label or tr(entry.labelKey)
            adjustmentParts[#adjustmentParts + 1] = label .. "=" .. value
        end
    end
    if market.variationMultiplier ~= nil then
        adjustmentParts[#adjustmentParts + 1] = string.format("variation=%.3fx",
            tonumber(market.variationMultiplier) or 1)
    end
    appendDetailLine(lines, "UI_MarketSenseCatalog_DetailAdjustments",
        "Price adjustments", table.concat(adjustmentParts, " | "))

    local evidenceParts = {}
    local yieldText = yieldSummary(details)
    if yieldText then evidenceParts[#evidenceParts + 1] = yieldText end
    local availability = details.availabilityStatus or details.availability
    if type(availability) == "table" then availability = availability.status end
    if availability and tostring(availability) ~= "" then
        evidenceParts[#evidenceParts + 1] = "availability=" .. tostring(availability)
    end
    appendDetailLine(lines, "UI_MarketSenseCatalog_DetailEvidence",
        "Evidence", table.concat(evidenceParts, " | "))

    local variant = heuristic.foodVariantEvidence
    if type(variant) == "table" and variant.sourceFullType then
        appendDetailLine(lines, "UI_MarketSenseCatalog_DetailVariant",
            "Nutrition source", string.format("%s (%s)",
                tostring(variant.sourceFullType),
                tostring(variant.relation or variant.status or "verified")))
    end
    return lines
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
    buildFilterOptions = buildFilterOptions,
    matchesFilter = matchesFilter,
    safeItemDisplayName = safeItemDisplayName,
    displayTags = displayTags,
    categoryDescription = categoryDescription,
    rowSearchText = rowSearchText,
    yieldSummary = yieldSummary,
    baseItemSummary = baseItemSummary,
    priceHeuristicSummary = PriceFormatting.priceHeuristicSummary,
    marketModifierSummary = PriceFormatting.marketModifierSummary,
    descriptorSummary = PriceFormatting.descriptorSummary,
    buildDetailSubtext = buildDetailSubtext,
    buildDetailLines = buildDetailLines,
    drawMarketItemRow = drawMarketItemRow,
}
