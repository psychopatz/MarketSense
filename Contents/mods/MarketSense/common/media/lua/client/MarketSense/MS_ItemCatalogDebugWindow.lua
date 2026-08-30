require "ISUI/ISTextEntryBox"
require "MarketSense/MS_PublicAPI"
require "PsychopatzCore/UI/PsychopatzUI"
require "PsychopatzCore/UI/PsychopatzDebugHubWindow"

MarketSense = MarketSense or {}

local UI = PsychopatzCore.UI
local Theme = UI.Theme
local Layout = UI.Layout

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

local function priceHeuristicSummary(details)
    local heuristic = details and details.priceHeuristic
    if type(heuristic) ~= "table" then return nil end

    local model = tostring(heuristic.model or "")
    local function demandText(value)
        if value == nil then return "-" end
        return string.format("%.2f", tonumber(value) or 0)
    end
    if model == "literature_v2_pending" then
        return string.format(
            "Pricing: %s | subtype=%s | skill=%s | level=%s | recipes=%s | read=%s",
            tostring(heuristic.status or "pending"),
            tostring(heuristic.subtype or "Literature"),
            tostring(heuristic.skill or "-"),
            tostring(heuristic.skillLevel ~= nil and heuristic.skillLevel or "-"),
            tostring(heuristic.learnedRecipeCount ~= nil
                and heuristic.learnedRecipeCount or "-"),
            tostring(heuristic.readType or "-"))
    end

    if model == "liquid_v2_pending" then
        local fluid = heuristic.fluidTypeString or heuristic.fluidType or "-"
        local mixture = heuristic.fluidIsMixture and "yes" or "no"
        return string.format(
            "Pricing: %s | subtype=%s | fluid=%s | amount=%s | primary=%s | ratio=%s | mixture=%s | yield=%s",
            tostring(heuristic.status or "pending"),
            tostring(heuristic.subtype or "LiquidUnknown"),
            tostring(fluid),
            tostring(heuristic.fluidAmount ~= nil and heuristic.fluidAmount or "-"),
            tostring(heuristic.fluidPrimaryAmount ~= nil
                and heuristic.fluidPrimaryAmount or "-"),
            demandText(heuristic.fluidFilledRatio),
            mixture,
            tostring(heuristic.yieldStatus or "not_detected"))
    end

    if model == "resource_v2_pending" then
        local yield = tostring(heuristic.yieldStatus or "not_detected")
        local outputs = tostring(heuristic.yieldOutputCount ~= nil
            and heuristic.yieldOutputCount or 0)
        local stack = heuristic.canStack
        if stack == nil or stack == "" then stack = "-" end
        return string.format(
            "Pricing: %s | subtype=%s | family=%s | form=%s | stack=%s | yield=%s (%s outputs, qty=%s)",
            tostring(heuristic.status or "pending"),
            tostring(heuristic.subtype or "ResourceUnknown"),
            tostring(heuristic.materialFamily or "-"),
            tostring(heuristic.materialForm or "unknown"),
            tostring(stack),
            yield,
            outputs,
            tostring(heuristic.yieldOutputQuantity ~= nil
                and heuristic.yieldOutputQuantity or 0))
    end

    if model == "misc_v2_pending" then
        local signals = heuristic.signals or {}
        local signalText = signals[1] or "-"
        if signals[2] then signalText = signalText .. "," .. tostring(signals[2]) end
        local uses = heuristic.remainingUsesRatio
        if uses == nil then uses = heuristic.maxUses end
        return string.format(
            "Pricing: %s | subtype=%s | signals=%s | uses=%s | weight=%s | yield=%s (%s outputs, qty=%s)",
            tostring(heuristic.status or "pending"),
            tostring(heuristic.subtype or "Misc"),
            tostring(signalText),
            tostring(uses ~= nil and uses or "-"),
            tostring(heuristic.weight ~= nil and heuristic.weight or "-"),
            tostring(heuristic.yieldStatus or "not_detected"),
            tostring(heuristic.yieldOutputCount ~= nil
                and heuristic.yieldOutputCount or 0),
            tostring(heuristic.yieldOutputQuantity ~= nil
                and heuristic.yieldOutputQuantity or 0))
    end

    if model == "weapon_v2_pending" then
        local demand = heuristic.recipeDemand or {}
        return string.format(
            "Pricing: %s | class=%s | recipes=%s | reusable=%s | demand=%s | role=%s",
            tostring(heuristic.status or "pending"),
            tostring(heuristic.mechanicalClass or "-"),
            tostring(demand.recipeCount ~= nil and demand.recipeCount or "-"),
            tostring(demand.reusableRecipeCount ~= nil
                and demand.reusableRecipeCount or "-"),
            demandText(heuristic.recipeDemandScore),
            tostring(heuristic.marketRole or heuristic.role or "-"))
    end

    if model == "clothing_v2_pending" then
        return string.format(
            "Pricing: %s | subtype=%s | slot=%s | bite=%s | scratch=%s | bullet=%s",
            tostring(heuristic.status or "pending"),
            tostring(heuristic.subtype or "Clothing"),
            tostring(heuristic.bodyLocationToken or heuristic.bodyLocation or "-"),
            tostring(heuristic.biteDefense ~= nil and heuristic.biteDefense or "-"),
            tostring(heuristic.scratchDefense ~= nil and heuristic.scratchDefense or "-"),
            tostring(heuristic.bulletDefense ~= nil and heuristic.bulletDefense or "-"))
    end

    if model == "container_v2_pending" then
        return string.format(
            "Pricing: %s | subtype=%s | capacity=%s | reduction=%s | weight=%s | yield=%s",
            tostring(heuristic.status or "pending"),
            tostring(heuristic.subtype or "Container"),
            tostring(heuristic.capacity ~= nil and heuristic.capacity or "-"),
            tostring(heuristic.weightReduction ~= nil and heuristic.weightReduction or "-"),
            tostring(heuristic.weight ~= nil and heuristic.weight or "-"),
            tostring(heuristic.contentYieldStatus or "not_detected"))
    end

    if model == "electronics_v2_pending" then
        local capabilities = heuristic.capabilities or {}
        local capability = capabilities[1] or "-"
        local device = heuristic.deviceDataAvailable and "device" or "no-device"
        local light = heuristic.lightStrength ~= nil
            and tostring(heuristic.lightStrength) or "-"
        return string.format(
            "Pricing: %s | subtype=%s | capability=%s | light=%s | %s",
            tostring(heuristic.status or "pending"),
            tostring(heuristic.subtype or "Electronics"),
            tostring(capability), light, device)
    end

    if model == "medical_v2_pending" then
        local treatment = heuristic.bandagePower
            or heuristic.reduceInfectionPower
            or heuristic.painReduction
            or heuristic.fluReduction
            or heuristic.foodSicknessChange
        local effect = treatment ~= nil and tostring(treatment) or "-"
        return string.format(
            "Pricing: %s | subtype=%s | bandage=%s | infection=%s | effect=%s | yield=%s",
            tostring(heuristic.status or "pending"),
            tostring(heuristic.subtype or "Medical"),
            tostring(heuristic.bandagePower ~= nil and heuristic.bandagePower or "-"),
            tostring(heuristic.reduceInfectionPower ~= nil
                and heuristic.reduceInfectionPower or "-"),
            effect,
            tostring(heuristic.yieldStatus or "not_detected"))
    end

    if model == "building_v2_pending" then
        local capabilities = heuristic.capabilities or {}
        local capability = capabilities[1] or "-"
        local evidence = heuristic.capabilityEvidence or {}
        local evidenceSource = evidence[1] or "-"
        local requirements = heuristic.requirements or {}
        local requirement = requirements[1] or "-"
        local capacity = heuristic.worldContainerCapacity
        if capacity == nil or capacity <= 0 then
            capacity = heuristic.capacity
        end
        local world = heuristic.worldEvidenceAvailable and "available" or "unavailable"
        return string.format(
            "Pricing: %s | subtype=%s | capability=%s | evidence=%s | requirement=%s | capacity=%s | world=%s | yield=%s",
            tostring(heuristic.status or "pending"),
            tostring(heuristic.subtype or "Building"),
            tostring(capability),
            tostring(evidenceSource),
            tostring(requirement),
            tostring(capacity ~= nil and capacity or "-"),
            world,
            tostring(heuristic.yieldStatus or "not_detected"))
    end

    if model == "tool_v2" then
        local demand = heuristic.recipeDemand or {}
        return string.format(
            "Pricing: %s | subtype=%s | recipes=%s | reusable=%s | criticality=%s | demand=%s",
            tostring(heuristic.status or "ready"),
            tostring(heuristic.subtype or "Tool"),
            tostring(demand.recipeCount ~= nil and demand.recipeCount or "-"),
            tostring(demand.reusableRecipeCount ~= nil
                and demand.reusableRecipeCount or "-"),
            tostring(heuristic.recipeCriticality or "none"),
            demandText(heuristic.recipeDemandScore))
    end

    return nil
end

local function buildDetailSubtext(details)
    local yieldText = yieldSummary(details)
    local heuristicText = priceHeuristicSummary(details)
    if yieldText and heuristicText then
        local model = details and details.priceHeuristic
            and tostring(details.priceHeuristic.model or "") or ""
        if model == "tool_v2" or model == "weapon_v2_pending" then
            return heuristicText .. " | " .. yieldText
        end
        return yieldText .. " | " .. heuristicText
    end
    return yieldText or heuristicText
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

MarketSenseItemCatalogDebugWindow = PsychopatzWindow:derive(
    "MarketSenseItemCatalogDebugWindow"
)

function MarketSenseItemCatalogDebugWindow:initialise()
    PsychopatzWindow.initialise(self)
end

function MarketSenseItemCatalogDebugWindow:createChildren()
    PsychopatzWindow.createChildren(self)

    self.search = ISTextEntryBox:new("", 0, 0, 100, 28)
    self.search:initialise()
    self.search:instantiate()
    if self.search.setClearButton then self.search:setClearButton(true) end
    self.search.onTextChange = function() self:queueVisibleRefresh() end
    self:addChild(self.search)

    self.collapseAllButton = UI.CreateButton(self, {
        id = "collapse",
        title = getText("UI_MarketSenseCatalog_Collapse"),
        target = self,
        onclick = MarketSenseItemCatalogDebugWindow.onCollapseAll,
        variant = "quiet",
    })
    self.expandButton = UI.CreateButton(self, {
        id = "expand",
        title = getText("UI_MarketSenseCatalog_Expand"),
        target = self,
        onclick = MarketSenseItemCatalogDebugWindow.onExpandAll,
        variant = "quiet",
    })
    self.refreshButton = UI.CreateButton(self, {
        id = "refresh",
        title = getText("UI_MarketSenseCatalog_Refresh"),
        target = self,
        onclick = MarketSenseItemCatalogDebugWindow.onRefreshCatalog,
        variant = "primary",
    })
    self.generateButton = UI.CreateButton(self, {
        id = "generate",
        title = getText("UI_MarketSenseCatalog_Generate"),
        target = self,
        onclick = MarketSenseItemCatalogDebugWindow.onGenerateRuntimeItems,
        variant = "success",
    })

    self.itemList = UI.CreateCategorizedList(self, {
        itemHeight = 44,
        categoryHeight = 38,
        categoryOrder = CATEGORY_ORDER,
        expandedByDefault = true,
        itemsAlreadySorted = true,
        virtualized = true,
        getCategoryPath = function(row) return row.categoryPath end,
        getItemKey = function(row) return row.fullType end,
        getItemText = function(row) return row.displayName or row.fullType end,
        drawItem = drawMarketItemRow,
        onItemSelected = function(_, row) self:onItemSelected(row) end,
        onItemActivated = function(_, row) self:onItemActivated(row) end,
    })

    self.allItems = {}
    self.visibleItems = {}
    self.selectedItem = nil
    self.selectedDetails = nil
    self.statusText = nil
    self:requestResponsiveLayout(true)
    self:refreshCatalog()
end

function MarketSenseItemCatalogDebugWindow:onResponsiveLayout()
    local rect = self:getContentRect({ top = 110, bottom = 76 })
    local gap = Layout.Pixels(6, self.uiScale)
    local controlHeight = Layout.Pixels(28, self.uiScale)
    local toolbarY = rect.y - Layout.Pixels(78, self.uiScale)
    local compact = Layout.IsCompact(rect.width,
        Layout.Pixels(820, self.uiScale))
    local searchWidth = compact and rect.width
        or math.max(Layout.Pixels(180, self.uiScale),
            math.floor(rect.width * 0.42))
    self.search.psychopatzPreferredWidth = searchWidth
    local controls = {
        self.collapseAllButton, self.expandButton, self.refreshButton,
        self.generateButton,
    }
    local controlsX = compact and rect.x or rect.x + searchWidth + gap
    local controlsY = compact and toolbarY + controlHeight + gap or toolbarY
    Layout.SetBounds(self.search, rect.x, toolbarY, searchWidth, controlHeight)
    Layout.Flow(controls, {
        x = controlsX,
        y = controlsY,
        width = compact and rect.width
            or math.max(1, rect.width - searchWidth - gap),
    }, { scale = self.uiScale, gap = 5, minWidth = 86 })
    Layout.SetBounds(self.itemList, rect.x, rect.y, rect.width, rect.height)
end

function MarketSenseItemCatalogDebugWindow:refreshCatalog()
    self.statusText = nil
    local loaded = true
    if MarketSense and type(MarketSense.EnsureRuntimeRegistryLoaded) == "function" then
        local ok, result = pcall(MarketSense.EnsureRuntimeRegistryLoaded, false)
        loaded = ok and result ~= false
        if not ok then self.statusText = tostring(result) end
    end

    local known = {}
    if loaded and MarketSense
        and type(MarketSense.GetAllKnownItems) == "function"
    then
        local ok, result = pcall(MarketSense.GetAllKnownItems)
        if ok and type(result) == "table" then known = result end
        if not ok then self.statusText = tostring(result) end
    end

    self.allItems = {}
    for fullType, entry in pairs(known) do
        if type(entry) == "table" then
            local row = entry
            row.fullType = tostring(row.fullType or fullType or "")
            if row.fullType ~= "" then
                row.displayName = safeItemDisplayName(row.fullType)
                row.categoryPath = categoryPath(row)
                row._displayTags = displayTags(row)
                row._searchText = rowSearchText(row)
                self.allItems[#self.allItems + 1] = row
            end
        end
    end

    -- The reusable categorized list can skip its per-refresh item sort when
    -- the source is kept in display order.  This matters while typing into
    -- the search box: filtering remains O(n), but does not sort thousands of
    -- rows on every keystroke.
    table.sort(self.allItems, function(left, right)
        local leftPath = left.categoryPath or {}
        local rightPath = right.categoryPath or {}
        for index = 1, math.max(#leftPath, #rightPath) do
            local leftPart = tostring(leftPath[index] or "")
            local rightPart = tostring(rightPath[index] or "")
            if index == 1 then
                local leftOrder = CATEGORY_ORDER[leftPart] or 999
                local rightOrder = CATEGORY_ORDER[rightPart] or 999
                if leftOrder ~= rightOrder then
                    return leftOrder < rightOrder
                end
            end
            if lower(leftPart) ~= lower(rightPart) then
                return lower(leftPart) < lower(rightPart)
            end
        end
        local leftName = lower(left.displayName or left.fullType)
        local rightName = lower(right.displayName or right.fullType)
        if leftName == rightName then
            return tostring(left.fullType) < tostring(right.fullType)
        end
        return leftName < rightName
    end)
    self:refreshVisibleItems()
end

function MarketSenseItemCatalogDebugWindow:queueVisibleRefresh()
    self.searchRefreshQueued = true
    self.searchRefreshTicks = 2
    if self.searchRefreshHandler then return end

    if not Events or not Events.OnTick then
        self:refreshVisibleItems()
        return
    end

    local handler
    handler = function()
        if not self.searchRefreshQueued then
            Events.OnTick.Remove(handler)
            self.searchRefreshHandler = nil
            return
        end
        self.searchRefreshTicks = (self.searchRefreshTicks or 1) - 1
        if self.searchRefreshTicks > 0 then return end
        Events.OnTick.Remove(handler)
        self.searchRefreshHandler = nil
        self.searchRefreshQueued = false
        self:refreshVisibleItems()
    end
    self.searchRefreshHandler = handler
    Events.OnTick.Add(handler)
end

function MarketSenseItemCatalogDebugWindow:refreshVisibleItems()
    if not self.itemList then return end
    self.searchRefreshQueued = false
    local query = lower(self.search and self.search:getText() or "")
    self.visibleItems = {}
    for _, row in ipairs(self.allItems or {}) do
        if query == "" or string.find(row._searchText or rowSearchText(row),
            query, 1, true)
        then
            self.visibleItems[#self.visibleItems + 1] = row
        end
    end
    self.itemList:setItems(self.visibleItems)
end

function MarketSenseItemCatalogDebugWindow:onCollapseAll()
    self.itemList:collapseAll()
end

function MarketSenseItemCatalogDebugWindow:onExpandAll()
    self.itemList:expandAll()
end

function MarketSenseItemCatalogDebugWindow:onRefreshCatalog()
    self.runtimeGenerationStatus = nil
    self:refreshCatalog()
end

function MarketSenseItemCatalogDebugWindow:onGenerateRuntimeItems()
    if self.runtimeGenerationBusy then return end
    self.runtimeGenerationBusy = true
    self.runtimeGenerationStatus = tr("UI_MarketSenseCatalog_RuntimeGenerating",
        "Generating MarketSense runtime catalog...")

    local startedAt = timestampMs()
    local ok, result
    if MarketSense and type(MarketSense.RegenerateItemRegistry) == "function" then
        ok, result = pcall(MarketSense.RegenerateItemRegistry)
    elseif MarketSense
        and type(MarketSense.EnsureRuntimeRegistryLoaded) == "function"
    then
        ok, result = pcall(MarketSense.EnsureRuntimeRegistryLoaded, true)
    else
        ok, result = false, "MarketSense runtime catalog generation is unavailable."
    end
    local finishedAt = timestampMs()
    self.runtimeGenerationBusy = false

    if not ok then
        self.runtimeGenerationStatus = trFormat(
            "UI_MarketSenseCatalog_RuntimeGenerationFailed",
            "MarketSense runtime catalog generation failed: %s", tostring(result))
        return
    end

    if MarketSense and type(MarketSense.ClearRuntimeCache) == "function" then
        pcall(MarketSense.ClearRuntimeCache)
    end
    self.selectedItem = nil
    self.selectedDetails = nil
    self:refreshCatalog()

    local itemCount = result and tonumber(result.total)
        or #(self.allItems or {})
    local fileCount = result and type(result.files) == "table"
        and #result.files or 0
    if startedAt and finishedAt then
        local elapsed = math.max(0, math.floor(finishedAt - startedAt))
        self.runtimeGenerationStatus = trFormat(
            "UI_MarketSenseCatalog_RuntimeGeneration",
            "Generated %s MarketSense items across %s files in %s ms. Output: Zomboid/Lua/MS_Items",
            tostring(itemCount), tostring(fileCount), tostring(elapsed))
    else
        self.runtimeGenerationStatus = trFormat(
            "UI_MarketSenseCatalog_RuntimeGenerationNoTiming",
            "Generated %s MarketSense items across %s files. Output: Zomboid/Lua/MS_Items",
            tostring(itemCount), tostring(fileCount))
    end
end

function MarketSenseItemCatalogDebugWindow:inspectItem(row)
    self.runtimeGenerationStatus = nil
    self.selectedItem = row
    self.selectedDetails = nil
    if not row or not MarketSense then return end
    if type(MarketSense.DebugItem) == "function" then
        local ok, details = pcall(MarketSense.DebugItem, row.fullType, true)
        if ok then self.selectedDetails = details
        else self.statusText = tostring(details) end
    elseif type(MarketSense.GetPriceDetails) == "function" then
        local ok, details = pcall(MarketSense.GetPriceDetails,
            row.fullType, true)
        if ok then self.selectedDetails = details
        else self.statusText = tostring(details) end
    end
end

function MarketSenseItemCatalogDebugWindow:onItemSelected(row)
    self:inspectItem(row)
end

function MarketSenseItemCatalogDebugWindow:onItemActivated(row)
    self:inspectItem(row)
end

function MarketSenseItemCatalogDebugWindow:render()
    PsychopatzWindow.render(self)
    local rect = self:getContentRect({ top = 110, bottom = 76 })
    local count = #(self.visibleItems or {})
    local suffix = string.format("%d / %d", count, #(self.allItems or {}))
    UI.DrawSectionTitle(self,
        tr("UI_MarketSenseCatalog_Heading", "AVAILABLE MARKET ITEMS"),
        rect.x, rect.y - Layout.Pixels(22, self.uiScale), rect.width, suffix)

    local detailHeight = Layout.Pixels(64, self.uiScale)
    local detailY = self:getHeight() - detailHeight - Layout.Pixels(10, self.uiScale)
    UI.DrawSurface(self, rect.x, detailY, rect.width, detailHeight, true)
    local detailText
    local detailSubtext
    if self.runtimeGenerationStatus then
        detailText = self.runtimeGenerationStatus
    elseif self.selectedItem then
        local details = self.selectedDetails or {}
        local status = details.marketEligible == false
            and tr("UI_MarketSenseCatalog_NotEligible", "NOT ELIGIBLE")
            or tr("UI_MarketSenseCatalog_Ready", "READY")
        local price = tonumber(details.price or self.selectedItem.price) or 0
        detailText = string.format("%s  |  %s  |  $%d  |  %s",
            self.selectedItem.displayName or self.selectedItem.fullType,
            self.selectedItem.category or "Misc", math.floor(price), status)
        detailSubtext = buildDetailSubtext(details)
    elseif self.statusText then
        detailText = self.statusText
    else
        detailText = tr("UI_MarketSenseCatalog_SelectItem",
            "Select an item to run the MarketSense debug evaluator.")
    end
    local muted = Theme.colors.textMuted
    self:drawText(Layout.Ellipsize(detailText, UIFont.Small,
        math.max(40, rect.width - Layout.Pixels(20, self.uiScale))),
        rect.x + Layout.Pixels(10, self.uiScale), detailY + Layout.Pixels(10, self.uiScale),
        muted.r, muted.g, muted.b, muted.a, UIFont.Small)
    if detailSubtext then
        self:drawText(Layout.Ellipsize(detailSubtext, UIFont.Small,
            math.max(40, rect.width - Layout.Pixels(20, self.uiScale))),
            rect.x + Layout.Pixels(10, self.uiScale), detailY + Layout.Pixels(34, self.uiScale),
            muted.r, muted.g, muted.b, muted.a, UIFont.Small)
    end
end

function MarketSenseItemCatalogDebugWindow:close()
    if self.searchRefreshHandler and Events and Events.OnTick then
        Events.OnTick.Remove(self.searchRefreshHandler)
        self.searchRefreshHandler = nil
    end
    self:setVisible(false)
    self:removeFromUIManager()
    MarketSenseItemCatalogDebugWindow.instance = nil
end

-- Kept public for lightweight catalog/UI smoke tests and other debug tools
-- that need to preview the same taxonomy grouping without opening a window.
MarketSenseItemCatalogDebugWindow.BuildCategoryPath = categoryPath
MarketSenseItemCatalogDebugWindow.BuildYieldSummary = yieldSummary
MarketSenseItemCatalogDebugWindow.BuildPriceHeuristicSummary = priceHeuristicSummary
MarketSenseItemCatalogDebugWindow.BuildDetailSubtext = buildDetailSubtext

function MarketSenseItemCatalogDebugWindow.Open()
    if MarketSenseItemCatalogDebugWindow.instance then
        local window = MarketSenseItemCatalogDebugWindow.instance
        window:setVisible(true)
        window:bringToTop()
        window:refreshCatalog()
        return window
    end

    local window = UI.NewWindow(MarketSenseItemCatalogDebugWindow, {
        title = getText("UI_MarketSenseCatalog_Title"),
        persistenceKey = "MarketSense.ItemCatalogDebug",
        resizable = true,
        responsiveSpec = {
            width = 980,
            height = 720,
            minWidth = 640,
            minHeight = 460,
            maxWidth = 1440,
            maxHeight = 980,
        },
    })
    window:initialise()
    window:instantiate()
    window:addToUIManager()
    MarketSenseItemCatalogDebugWindow.instance = window
    return window
end

if PsychopatzCore.DebugHub and PsychopatzCore.DebugHub.RegisterTool then
    PsychopatzCore.DebugHub.RegisterTool({
        id = "marketsense.itemCatalog",
        source = "MarketSense",
        order = 20,
        title = getText("UI_MarketSenseCatalog_ToolTitle"),
        description = tr("UI_MarketSenseCatalog_ToolDescription",
            "Display every available MarketSense item by taxonomy and test its runtime evaluator."),
        available = function()
            return MarketSense
                and type(MarketSense.GetAllKnownItems) == "function"
        end,
        action = function() return MarketSenseItemCatalogDebugWindow.Open() end,
    })
end

MarketSense.ItemCatalogDebugWindow = MarketSenseItemCatalogDebugWindow
return MarketSenseItemCatalogDebugWindow
