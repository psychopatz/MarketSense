require "ISUI/ISTextEntryBox"
require "ISUI/ISComboBox"
require "MarketSense/MS_PublicAPI"
require "PsychopatzCore/UI/PsychopatzUI"
require "PsychopatzCore/UI/PsychopatzDebugHubWindow"
require "MarketSense/MS_ItemCatalogDebug_Presentation"

MarketSense = MarketSense or {}

local UI = PsychopatzCore.UI
local Theme = UI.Theme
local Layout = UI.Layout
local Presentation = require "MarketSense/MS_ItemCatalogDebug_Presentation"
local CATEGORY_ORDER = Presentation.CATEGORY_ORDER
local tr = Presentation.tr
local trFormat = Presentation.trFormat
local lower = Presentation.lower
local timestampMs = Presentation.timestampMs
local categoryPath = Presentation.categoryPath
local buildFilterOptions = Presentation.buildFilterOptions
local matchesFilter = Presentation.matchesFilter
local safeItemDisplayName = Presentation.safeItemDisplayName
local displayTags = Presentation.displayTags
local rowSearchText = Presentation.rowSearchText
local yieldSummary = Presentation.yieldSummary
local baseItemSummary = Presentation.baseItemSummary
local priceHeuristicSummary = Presentation.priceHeuristicSummary
local marketModifierSummary = Presentation.marketModifierSummary
local buildDetailSubtext = Presentation.buildDetailSubtext
local buildDetailLines = Presentation.buildDetailLines
local drawMarketItemRow = Presentation.drawMarketItemRow

local DETAIL_HEIGHT = 210
local DETAIL_GAP = 10

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

    self.filterCombo = ISComboBox:new(0, 0, 100, 28, self,
        MarketSenseItemCatalogDebugWindow.onFilterChanged)
    self.filterCombo:initialise()
    self.filterCombo:instantiate()
    self:addChild(self.filterCombo)

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
    self.filterOptions = {}
    self.filterSelection = nil
    self.selectedItem = nil
    self.selectedDetails = nil
    self.statusText = nil
    self:requestResponsiveLayout(true)
    self:refreshCatalog()
    self:startCatalogWatch()
end

function MarketSenseItemCatalogDebugWindow:startCatalogWatch()
    if self.catalogWatchHandler or not Events or not Events.OnTick
        or type(Events.OnTick.Add) ~= "function" then
        return
    end

    local handler
    handler = function()
        local state = MarketSense and MarketSense.ItemsRegistry
            and MarketSense.ItemsRegistry.state or nil
        if not state or state.rebuildInProgress then return end
        if state.catalog and state.catalog ~= self.catalogReference then
            self:refreshCatalog()
        end
    end
    self.catalogWatchHandler = handler
    Events.OnTick.Add(handler)
end

function MarketSenseItemCatalogDebugWindow:onResponsiveLayout()
    local rect = self:getContentRect({
        top = 110,
        bottom = DETAIL_HEIGHT + DETAIL_GAP,
    })
    local gap = Layout.Pixels(6, self.uiScale)
    local controlHeight = Layout.Pixels(28, self.uiScale)
    local toolbarY = rect.y - Layout.Pixels(78, self.uiScale)
    local compact = Layout.IsCompact(rect.width,
        Layout.Pixels(820, self.uiScale))
    local searchWidth
    local filterWidth
    if compact then
        searchWidth = math.max(Layout.Pixels(180, self.uiScale),
            math.floor((rect.width - gap) * 0.5))
        filterWidth = math.max(Layout.Pixels(180, self.uiScale),
            rect.width - searchWidth - gap)
    else
        searchWidth = math.max(Layout.Pixels(180, self.uiScale),
            math.floor(rect.width * 0.30))
        filterWidth = math.max(Layout.Pixels(210, self.uiScale),
            math.floor(rect.width * 0.30))
    end
    self.search.psychopatzPreferredWidth = searchWidth
    self.filterCombo.psychopatzPreferredWidth = filterWidth
    local controls = {
        self.collapseAllButton, self.expandButton, self.refreshButton,
        self.generateButton,
    }
    local controlsX
    if compact then
        controlsX = rect.x
    else
        controlsX = rect.x + searchWidth + gap + filterWidth + gap
    end
    local controlsY = compact and toolbarY + controlHeight + gap or toolbarY
    Layout.SetBounds(self.search, rect.x, toolbarY, searchWidth, controlHeight)
    Layout.SetBounds(self.filterCombo,
        compact and rect.x + searchWidth + gap or rect.x + searchWidth + gap,
        toolbarY, filterWidth, controlHeight)
    Layout.Flow(controls, {
        x = controlsX,
        y = controlsY,
        width = compact and rect.width or math.max(1,
            rect.width - searchWidth - filterWidth - (gap * 2)),
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
    self:rebuildFilterOptions()
    self:refreshVisibleItems()
    local state = MarketSense and MarketSense.ItemsRegistry
        and MarketSense.ItemsRegistry.state or nil
    self.catalogReference = state and state.catalog or nil
end

function MarketSenseItemCatalogDebugWindow:rebuildFilterOptions()
    local currentKey = self.filterSelection and self.filterSelection.key or "all"
    self.filterOptions = buildFilterOptions(self.allItems or {})

    local selected = self.filterOptions[1]
    for _, option in ipairs(self.filterOptions) do
        if option.key == currentKey then
            selected = option
            break
        end
    end
    self.filterSelection = selected

    if not self.filterCombo then return end
    if self.filterCombo.clear then
        self.filterCombo:clear()
    else
        self.filterCombo.options = {}
        self.filterCombo.optionData = {}
    end
    for _, option in ipairs(self.filterOptions) do
        self.filterCombo:addOptionWithData(option.label, option)
    end
    if self.filterCombo.selectData then
        self.filterCombo:selectData(selected)
    else
        self.filterCombo.selected = 1
    end
end

function MarketSenseItemCatalogDebugWindow:onFilterChanged()
    local selected = nil
    if self.filterCombo and self.filterCombo.getOptionData then
        selected = self.filterCombo:getOptionData(self.filterCombo.selected)
    end
    if type(selected) == "table" then
        self.filterSelection = selected
    else
        self.filterSelection = self.filterOptions[1]
    end
    self:queueVisibleRefresh()
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
        local matchesQuery = query == ""
            or string.find(row._searchText or rowSearchText(row),
                query, 1, true)
        if matchesQuery and matchesFilter(row, self.filterSelection)
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
    local rect = self:getContentRect({
        top = 110,
        bottom = DETAIL_HEIGHT + DETAIL_GAP,
    })
    local count = #(self.visibleItems or {})
    local suffix = string.format("%d / %d", count, #(self.allItems or {}))
    UI.DrawSectionTitle(self,
        tr("UI_MarketSenseCatalog_Heading", "AVAILABLE MARKET ITEMS"),
        rect.x, rect.y - Layout.Pixels(22, self.uiScale), rect.width, suffix)

    local detailHeight = Layout.Pixels(DETAIL_HEIGHT, self.uiScale)
    local detailY = self:getHeight() - detailHeight
    UI.DrawSurface(self, rect.x, detailY, rect.width, detailHeight, true)
    local detailText
    local detailLines
    if self.runtimeGenerationStatus then
        detailText = self.runtimeGenerationStatus
    elseif self.selectedItem then
        local details = self.selectedDetails or {}
        local status = details.marketEligible == false
            and tr("UI_MarketSenseCatalog_NotEligible", "NOT ELIGIBLE")
            or tr("UI_MarketSenseCatalog_Ready", "READY")
        -- The catalog row is authoritative. DebugItem may recalculate a
        -- transient value from live state, but showing that second value
        -- beside the row price makes the catalog look contradictory.
        local catalogPrice = math.floor(tonumber(self.selectedItem.price) or 0)
        detailText = trFormat("UI_MarketSenseCatalog_SelectedHeader",
            "%s  |  Catalog price: $%d  |  %s",
            self.selectedItem.displayName or self.selectedItem.fullType,
            catalogPrice, status)
        detailLines = buildDetailLines(self.selectedItem, details)
    elseif self.statusText then
        detailText = self.statusText
    else
        detailText = tr("UI_MarketSenseCatalog_SelectItem",
            "Select an item to run the MarketSense debug evaluator.")
    end
    local text = Theme.colors.text
    local muted = Theme.colors.textMuted
    local titleFont = UIFont.Medium or UIFont.Small
    local textWidth = math.max(40, rect.width - Layout.Pixels(20, self.uiScale))
    self:drawText(Layout.Ellipsize(detailText, UIFont.Small,
        textWidth), rect.x + Layout.Pixels(10, self.uiScale),
        detailY + Layout.Pixels(9, self.uiScale),
        text.r, text.g, text.b, text.a, titleFont)
    if detailLines then
        local x = rect.x + Layout.Pixels(10, self.uiScale)
        local y = detailY + Layout.Pixels(37, self.uiScale)
        local lineHeight = Layout.Pixels(18, self.uiScale)
        local labelGap = Layout.Pixels(8, self.uiScale)
        local labelColor = Theme.colors.textMuted
        for index, line in ipairs(detailLines) do
            local label = tostring(line.label or "") .. ":"
            local labelWidth = Theme.TextWidth(UIFont.Small, label) + labelGap
            local valueWidth = math.max(40, textWidth - labelWidth)
            self:drawText(label, x, y, labelColor.r, labelColor.g,
                labelColor.b, labelColor.a, UIFont.Small)
            self:drawText(Layout.Ellipsize(tostring(line.value or ""),
                UIFont.Small, valueWidth), x + labelWidth, y,
                text.r, text.g, text.b, text.a, UIFont.Small)
            y = y + lineHeight
            if index >= 8 then break end
        end
    end
end

function MarketSenseItemCatalogDebugWindow:close()
    if self.searchRefreshHandler and Events and Events.OnTick then
        Events.OnTick.Remove(self.searchRefreshHandler)
        self.searchRefreshHandler = nil
    end
    if self.catalogWatchHandler and Events and Events.OnTick then
        Events.OnTick.Remove(self.catalogWatchHandler)
        self.catalogWatchHandler = nil
    end
    self:setVisible(false)
    self:removeFromUIManager()
    MarketSenseItemCatalogDebugWindow.instance = nil
end

-- Kept public for lightweight catalog/UI smoke tests and other debug tools
-- that need to preview the same taxonomy grouping without opening a window.
MarketSenseItemCatalogDebugWindow.BuildCategoryPath = categoryPath
MarketSenseItemCatalogDebugWindow.BuildDisplayTags = displayTags
MarketSenseItemCatalogDebugWindow.BuildFilterOptions = buildFilterOptions
MarketSenseItemCatalogDebugWindow.MatchesFilter = matchesFilter
MarketSenseItemCatalogDebugWindow.BuildYieldSummary = yieldSummary
MarketSenseItemCatalogDebugWindow.BuildBaseItemSummary = baseItemSummary
MarketSenseItemCatalogDebugWindow.BuildPriceHeuristicSummary = priceHeuristicSummary
MarketSenseItemCatalogDebugWindow.BuildMarketModifierSummary = marketModifierSummary
MarketSenseItemCatalogDebugWindow.BuildDetailSubtext = buildDetailSubtext
MarketSenseItemCatalogDebugWindow.BuildDetailLines = buildDetailLines

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
            width = 1080,
            height = 820,
            minWidth = 700,
            minHeight = 560,
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
