local UI = {}

function UI.attach(windowClass, deps)
    local constants = deps.constants
    local renderCatalogRow = deps.renderCatalogRow
    local renderTagRow = deps.renderTagRow
    local renderSignatureRow = deps.renderSignatureRow
    local attachPanelClipping = deps.attachPanelClipping
    local relayoutWidgetScrollbars = deps.relayoutWidgetScrollbars

    local PAD = constants.PAD
    local GAP = constants.GAP
    local STATUS_HEIGHT = constants.STATUS_HEIGHT
    local HEADER_LINE = constants.HEADER_LINE
    local BROWSER_MIN_WIDTH = constants.BROWSER_MIN_WIDTH
    local BROWSER_MAX_WIDTH = constants.BROWSER_MAX_WIDTH
    local CONTROL_ROW_HEIGHT = constants.CONTROL_ROW_HEIGHT
    local CONTROL_ROW_GAP = constants.CONTROL_ROW_GAP
    local CONTROL_MIN_ENTRY_WIDTH = constants.CONTROL_MIN_ENTRY_WIDTH
    local CONTROL_BUTTON_MIN_WIDTH = constants.CONTROL_BUTTON_MIN_WIDTH
    local CONTROL_BUTTON_MAX_WIDTH = constants.CONTROL_BUTTON_MAX_WIDTH

    function windowClass:createRootPanel()
        local panel = ISPanel:new(0, 0, 100, 100)
        panel:initialise()
        panel.backgroundColor = { r = 0.03, g = 0.03, b = 0.03, a = 0.94 }
        panel.borderColor = { r = 0.28, g = 0.28, b = 0.28, a = 1 }
        self:addChild(panel)
        return panel
    end

    function windowClass:createSectionContainer(panelField, titleField, bodyField, titleText)
        local panel = self:createRootPanel()
        attachPanelClipping(panel)

        local title = ISLabel:new(0, 0, HEADER_LINE, titleText, 0.94, 0.94, 0.94, 1, UIFont.Small, true)
        title:initialise()
        panel:addChild(title)

        local body = ISPanel:new(0, 0, 100, 100)
        body:initialise()
        body.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
        body.borderColor = { r = 0, g = 0, b = 0, a = 0 }
        panel:addChild(body)
        attachPanelClipping(body)

        self[panelField] = panel
        self[titleField] = title
        self[bodyField] = body
    end

    function windowClass:layoutBodyContent(panel, title, body, content, bodyY)
        local contentY = bodyY or (PAD + 22)
        title:setX(PAD)
        title:setY(PAD)
        body:setX(PAD)
        body:setY(contentY)
        body:setWidth(panel:getWidth() - (PAD * 2))
        body:setHeight(panel:getHeight() - contentY - PAD)

        content:setX(0)
        content:setY(0)
        content:setWidth(body:getWidth())
        content:setHeight(body:getHeight())
    end

    function windowClass:relayoutScrollWidgets()
        local widgets = {
            self.catalogList,
            self.summaryText,
            self.tagList,
            self.pricingText,
            self.signatureList,
        }
        for _, widget in ipairs(widgets) do
            relayoutWidgetScrollbars(widget)
        end
    end

    function windowClass:createChildren()
        ISCollapsableWindow.createChildren(self)
        if self._dtChildrenCreated then
            return
        end
        self._dtChildrenCreated = true

        self.controlsPanel = self:createRootPanel()
        self:createSectionContainer("browserPanel", "browserTitle", "browserBody", "CATALOG BROWSER")
        self:createSectionContainer("summaryPanel", "summaryTitle", "summaryBody", "SUMMARY")
        self:createSectionContainer("tagsPanel", "tagsTitle", "tagsBody", "GENERATED TAGS")
        self:createSectionContainer("pricingPanel", "pricingTitle", "pricingBody", "PRICING AUDIT")
        self:createSectionContainer("signaturesPanel", "signaturesTitle", "signaturesBody", "SIGNATURE MATCHES")

        self.itemEntry = ISTextEntryBox:new("", 0, 0, 100, 24)
        self.itemEntry:initialise()
        self.itemEntry:instantiate()
        self.controlsPanel:addChild(self.itemEntry)

        self.lookupButton = ISButton:new(0, 0, 100, 24, "Lookup Item", self, self.onLookupClick)
        self.lookupButton:initialise()
        self.controlsPanel:addChild(self.lookupButton)

        self.buildButton = ISButton:new(0, 0, 100, 24, "Build Catalog", self, self.onBuildClick)
        self.buildButton:initialise()
        self.controlsPanel:addChild(self.buildButton)

        self.filterButton = ISButton:new(0, 0, 100, 24, "Apply Filter", self, self.onFilterClick)
        self.filterButton:initialise()
        self.controlsPanel:addChild(self.filterButton)

        self.clearButton = ISButton:new(0, 0, 100, 24, "Clear Cache", self, self.onClearClick)
        self.clearButton:initialise()
        self.controlsPanel:addChild(self.clearButton)

        self.exportButton = ISButton:new(0, 0, 100, 24, "Export Lua", self, self.onExportClick)
        self.exportButton:initialise()
        self.controlsPanel:addChild(self.exportButton)

        self.exportTextButton = ISButton:new(0, 0, 110, 24, "Dump Cache", self, self.onExportTextClick)
        self.exportTextButton:initialise()
        self.controlsPanel:addChild(self.exportTextButton)

        self.tagFilterCombo = ISComboBox:new(0, 0, 220, 24, self, self.onTagFilterChanged)
        self.tagFilterCombo:initialise()
        self.tagFilterCombo:addOption("All Tags")
        self.tagFilterCombo.selected = 1
        self.controlsPanel:addChild(self.tagFilterCombo)

        self.statusLabel = ISLabel:new(0, 0, STATUS_HEIGHT, "Status: idle", 0.86, 0.86, 0.86, 1, UIFont.Small, true)
        self.statusLabel:initialise()
        self.controlsPanel:addChild(self.statusLabel)

        self.helpLabel = ISLabel:new(
            0,
            0,
            STATUS_HEIGHT,
            "Lookup an item, filter by text, or narrow by generated tag using the tag combobox.",
            0.72,
            0.82,
            0.92,
            1,
            UIFont.Small,
            true
        )
        self.helpLabel:initialise()
        self.controlsPanel:addChild(self.helpLabel)

        self.catalogStatusLabel = ISLabel:new(0, 0, STATUS_HEIGHT, "No catalog built yet.", 0.74, 0.82, 0.94, 1, UIFont.Small, true)
        self.catalogStatusLabel:initialise()
        self.browserPanel:addChild(self.catalogStatusLabel)

        self.catalogList = ISScrollingListBox:new(0, 0, 100, 100)
        self.catalogList:initialise()
        self.catalogList:instantiate()
        self.catalogList.itemheight = 40
        self.catalogList.doDrawItem = renderCatalogRow
        self.catalogList.onmousedown = function(target, item)
            if not windowClass.instance then
                return false
            end

            if target and target.items then
                for i, row in ipairs(target.items) do
                    if row and row.item == item then
                        target.selected = i
                        break
                    end
                end
            end

            windowClass.instance:onCatalogSelected(item)
            return true
        end
        self.browserBody:addChild(self.catalogList)

        self.summaryText = ISRichTextPanel:new(0, 0, 100, 100)
        self.summaryText:initialise()
        self.summaryText:instantiate()
        self.summaryText.background = false
        self.summaryText.autosetheight = false
        self.summaryText:addScrollBars()
        self.summaryBody:addChild(self.summaryText)

        self.tagList = ISScrollingListBox:new(0, 0, 100, 100)
        self.tagList:initialise()
        self.tagList:instantiate()
        self.tagList.itemheight = 38
        self.tagList.doDrawItem = renderTagRow
        self.tagsBody:addChild(self.tagList)

        self.pricingText = ISRichTextPanel:new(0, 0, 100, 100)
        self.pricingText:initialise()
        self.pricingText:instantiate()
        self.pricingText.background = false
        self.pricingText.autosetheight = false
        self.pricingText:addScrollBars()
        self.pricingBody:addChild(self.pricingText)

        self.signatureList = ISScrollingListBox:new(0, 0, 100, 100)
        self.signatureList:initialise()
        self.signatureList:instantiate()
        self.signatureList.itemheight = 40
        self.signatureList.doDrawItem = renderSignatureRow
        self.signaturesBody:addChild(self.signatureList)

        self:refreshCatalogList()
        self:refreshTagFilterOptions()
        self:setStatus("Ready. Build the catalog or enter a full item type and press Lookup.")
    end

    function windowClass:onResize()
        ISCollapsableWindow.onResize(self)

        local innerX = PAD
        local innerY = self:titleBarHeight() + PAD
        local innerW = self:getWidth() - (PAD * 2)
        local innerH = self:getHeight() - self:titleBarHeight() - (PAD * 2)

        local controlsInnerW = math.max(320, innerW - (PAD * 2))
        local buttonCount = 6
        local minButtonsTotal = (CONTROL_BUTTON_MIN_WIDTH * buttonCount) + (GAP * (buttonCount - 1))
        local singleRow = controlsInnerW >= (CONTROL_MIN_ENTRY_WIDTH + GAP + minButtonsTotal)

        local row1Y = PAD
        local row2Y = row1Y + CONTROL_ROW_HEIGHT + CONTROL_ROW_GAP
        local buttonsY = singleRow and row1Y or row2Y
        local rowsBottom = singleRow and (row1Y + CONTROL_ROW_HEIGHT) or (row2Y + CONTROL_ROW_HEIGHT)

        local buttonW
        local entryW
        if singleRow then
            local availableForButtons = controlsInnerW - CONTROL_MIN_ENTRY_WIDTH - GAP - (GAP * (buttonCount - 1))
            buttonW = math.max(
                CONTROL_BUTTON_MIN_WIDTH,
                math.min(CONTROL_BUTTON_MAX_WIDTH, math.floor(availableForButtons / buttonCount))
            )
            local buttonsTotal = (buttonW * buttonCount) + (GAP * (buttonCount - 1))
            entryW = math.max(CONTROL_MIN_ENTRY_WIDTH, controlsInnerW - GAP - buttonsTotal)
        else
            buttonW = math.max(CONTROL_BUTTON_MIN_WIDTH, math.floor((controlsInnerW - (GAP * (buttonCount - 1))) / buttonCount))
            entryW = controlsInnerW
        end

        local comboY = rowsBottom + CONTROL_ROW_GAP
        local statusY = comboY + CONTROL_ROW_HEIGHT + 8
        local helpY = statusY + 20
        local controlsHeight = helpY + STATUS_HEIGHT + PAD

        self.controlsPanel:setX(innerX)
        self.controlsPanel:setY(innerY)
        self.controlsPanel:setWidth(innerW)
        self.controlsPanel:setHeight(controlsHeight)

        local contentY = innerY + controlsHeight + GAP
        local contentH = innerH - controlsHeight - GAP

        local browserX = innerX
        local browserY = contentY
        local browserW = innerW
        local browserH = math.max(220, math.floor(contentH * 0.32))
        local detailX = innerX
        local detailY = browserY + browserH + GAP
        local detailW = innerW
        local detailH = contentH - browserH - GAP

        if innerW >= 980 then
            browserW = math.min(BROWSER_MAX_WIDTH, math.max(BROWSER_MIN_WIDTH, math.floor(innerW * 0.31)))
            browserH = contentH
            detailX = browserX + browserW + GAP
            detailY = contentY
            detailW = innerW - browserW - GAP
            detailH = contentH
        end

        self.browserPanel:setX(browserX)
        self.browserPanel:setY(browserY)
        self.browserPanel:setWidth(browserW)
        self.browserPanel:setHeight(browserH)

        local rightPanels = {
            self.summaryPanel,
            self.tagsPanel,
            self.pricingPanel,
            self.signaturesPanel,
        }

        local detailColumns = detailW >= 760 and 2 or 1
        local detailRows = math.ceil(#rightPanels / detailColumns)
        local panelW = math.floor((detailW - ((detailColumns - 1) * GAP)) / detailColumns)
        local panelH = math.floor((detailH - ((detailRows - 1) * GAP)) / detailRows)

        for index, panel in ipairs(rightPanels) do
            local column = (index - 1) % detailColumns
            local row = math.floor((index - 1) / detailColumns)
            panel:setX(detailX + (column * (panelW + GAP)))
            panel:setY(detailY + (row * (panelH + GAP)))
            panel:setWidth(panelW)
            panel:setHeight(panelH)
        end

        self.itemEntry:setX(PAD)
        self.itemEntry:setY(row1Y)
        self.itemEntry:setWidth(entryW)
        self.itemEntry:setHeight(CONTROL_ROW_HEIGHT)

        local buttonsStartX = singleRow and (self.itemEntry:getX() + self.itemEntry:getWidth() + GAP) or PAD

        self.lookupButton:setX(buttonsStartX)
        self.lookupButton:setY(buttonsY)
        self.lookupButton:setWidth(buttonW)
        self.lookupButton:setHeight(CONTROL_ROW_HEIGHT)

        self.buildButton:setX(self.lookupButton:getX() + self.lookupButton:getWidth() + GAP)
        self.buildButton:setY(buttonsY)
        self.buildButton:setWidth(buttonW)
        self.buildButton:setHeight(CONTROL_ROW_HEIGHT)

        self.filterButton:setX(self.buildButton:getX() + self.buildButton:getWidth() + GAP)
        self.filterButton:setY(buttonsY)
        self.filterButton:setWidth(buttonW)
        self.filterButton:setHeight(CONTROL_ROW_HEIGHT)

        self.clearButton:setX(self.filterButton:getX() + self.filterButton:getWidth() + GAP)
        self.clearButton:setY(buttonsY)
        self.clearButton:setWidth(buttonW)
        self.clearButton:setHeight(CONTROL_ROW_HEIGHT)

        self.exportButton:setX(self.clearButton:getX() + self.clearButton:getWidth() + GAP)
        self.exportButton:setY(buttonsY)
        self.exportButton:setWidth(buttonW)
        self.exportButton:setHeight(CONTROL_ROW_HEIGHT)

        self.exportTextButton:setX(self.exportButton:getX() + self.exportButton:getWidth() + GAP)
        self.exportTextButton:setY(buttonsY)
        self.exportTextButton:setWidth(buttonW)
        self.exportTextButton:setHeight(CONTROL_ROW_HEIGHT)

        local comboWidth = math.max(240, math.min(460, controlsInnerW))
        self.tagFilterCombo:setX(PAD)
        self.tagFilterCombo:setY(comboY)
        self.tagFilterCombo:setWidth(comboWidth)
        self.tagFilterCombo:setHeight(CONTROL_ROW_HEIGHT)

        self.statusLabel:setX(PAD)
        self.statusLabel:setY(statusY)

        self.helpLabel:setX(PAD)
        self.helpLabel:setY(helpY)

        local browserTextY = PAD + 22
        self.browserTitle:setX(PAD)
        self.browserTitle:setY(PAD)
        self.catalogStatusLabel:setX(PAD)
        self.catalogStatusLabel:setY(browserTextY)
        self.browserBody:setX(PAD)
        self.browserBody:setY(browserTextY + 18)
        self.browserBody:setWidth(self.browserPanel:getWidth() - (PAD * 2))
        self.browserBody:setHeight(self.browserPanel:getHeight() - (browserTextY + 18) - PAD)
        self.catalogList:setX(0)
        self.catalogList:setY(0)
        self.catalogList:setWidth(self.browserBody:getWidth())
        self.catalogList:setHeight(self.browserBody:getHeight())

        local panelTextY = PAD + 22

        self:layoutBodyContent(self.summaryPanel, self.summaryTitle, self.summaryBody, self.summaryText, panelTextY)
        self:layoutBodyContent(self.tagsPanel, self.tagsTitle, self.tagsBody, self.tagList, panelTextY)
        self:layoutBodyContent(self.pricingPanel, self.pricingTitle, self.pricingBody, self.pricingText, panelTextY)
        self:layoutBodyContent(self.signaturesPanel, self.signaturesTitle, self.signaturesBody, self.signatureList, panelTextY)

        self:relayoutScrollWidgets()

        if self.summaryText.text and self.summaryText.text ~= "" then
            self.summaryText:paginate()
        end
        if self.pricingText.text and self.pricingText.text ~= "" then
            self.pricingText:paginate()
        end
    end
end

return UI
