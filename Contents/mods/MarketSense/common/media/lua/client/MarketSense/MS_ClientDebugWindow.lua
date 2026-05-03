if isServer() then
    return
end

require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"
require "ISUI/ISRichTextPanel"
require "ISUI/ISButton"
require "ISUI/ISTextEntryBox"
require "ISUI/ISComboBox"
require "MarketSense/DT_PublicAPI"

local Constants = require "MarketSense/ClientDebug/MS_ClientDebugConstants"
local DebugUtils = require "MarketSense/ClientDebug/MS_ClientDebugUtils"
local Renderers = require "MarketSense/ClientDebug/MS_ClientDebugRenderers"
local LayoutUtils = require "MarketSense/ClientDebug/MS_ClientDebugLayoutUtils"
local CatalogModule = require "MarketSense/ClientDebug/MS_ClientDebugCatalog"
local ReportModule = require "MarketSense/ClientDebug/MS_ClientDebugReport"
local UIModule = require "MarketSense/ClientDebug/MS_ClientDebugUI"

MS_ItemRuntimeDebugWindow = ISCollapsableWindow:derive("MS_ItemRuntimeDebugWindow")

local safeText = DebugUtils.safeText
local safeNumber = DebugUtils.safeNumber
local toRichText = DebugUtils.toRichText
local lower = DebugUtils.lower

CatalogModule.attach(MS_ItemRuntimeDebugWindow, {
    safeText = safeText,
    safeNumber = safeNumber,
    lower = lower,
    compareCatalogEntries = Renderers.compareCatalogEntries,
})

ReportModule.attach(MS_ItemRuntimeDebugWindow, {
    safeText = safeText,
    toRichText = toRichText,
    compareSignatureEntries = Renderers.compareSignatureEntries,
})

UIModule.attach(MS_ItemRuntimeDebugWindow, {
    constants = Constants,
    renderCatalogRow = Renderers.renderCatalogRow,
    renderTagRow = Renderers.renderTagRow,
    renderSignatureRow = Renderers.renderSignatureRow,
    attachPanelClipping = LayoutUtils.attachPanelClipping,
    relayoutWidgetScrollbars = LayoutUtils.relayoutWidgetScrollbars,
})

function MS_ItemRuntimeDebugWindow:initialise()
    ISCollapsableWindow.initialise(self)
    self:setTitle("MarketSense Item Runtime Debug")
    self:setResizable(true)

    local screenW = getCore():getScreenWidth()
    local screenH = getCore():getScreenHeight()
    self.minimumWidth = math.max(760, math.min(1080, math.floor(screenW * 0.72)))
    self.minimumHeight = math.max(520, math.min(700, math.floor(screenH * 0.70)))

    self.catalogItems = {}
    self.filteredCatalogItems = {}
    self.lastExportPreview = nil

    local existing = DynamicTrading.GetRuntimeCatalog()
    if existing then
        self.catalogItems = self:buildCatalogIndex(existing)
        self.filteredCatalogItems = self.catalogItems
    end
end

function MS_ItemRuntimeDebugWindow:setStatus(text)
    if self.statusLabel then
        self.statusLabel:setName("Status: " .. safeText(text, "idle"))
    end
end

function MS_ItemRuntimeDebugWindow:setCatalogStatus(text)
    if self.catalogStatusLabel then
        self.catalogStatusLabel:setName(safeText(text, "No catalog built yet."))
    end
end

function MS_ItemRuntimeDebugWindow:onLookupClick()
    local fullType = safeText(self.itemEntry and self.itemEntry:getText() or "")
    if fullType == "" then
        self:setStatus("Enter an item full type first.")
        return
    end

    if #self.catalogItems > 0 then
        local selectedTag = self:getSelectedTagFilter()
        local selectedOrigin = self:getSelectedOriginFilter()
        self:applyCatalogFilter(fullType, selectedTag, selectedOrigin)
        self:selectCatalogItem(fullType)
    end

    self:refreshReport(DynamicTrading.DebugItem(fullType))
end

function MS_ItemRuntimeDebugWindow:onFilterClick()
    if #self.catalogItems <= 0 then
        self:setStatus("Build the catalog first before filtering it.")
        return
    end

    local term = safeText(self.itemEntry and self.itemEntry:getText() or "")
    local selectedTag = self:getSelectedTagFilter()
    local selectedOrigin = self:getSelectedOriginFilter()
    self:applyCatalogFilter(term, selectedTag, selectedOrigin)

    local status = "Catalog filtered"
    if term ~= "" then status = status .. " by text" end
    if selectedTag ~= "" then status = status .. (term ~= "" and " and tag: " or " by tag: ") .. selectedTag end
    if selectedOrigin ~= "" then status = status .. ( (term ~= "" or selectedTag ~= "") and " and origin: " or " by origin: ") .. selectedOrigin end
    
    if term == "" and selectedTag == "" and selectedOrigin == "" then
        self:setStatus("Catalog filter cleared.")
    else
        self:setStatus(status .. ".")
    end
end

function MS_ItemRuntimeDebugWindow:onTagFilterChanged()
    if #self.catalogItems <= 0 then
        return
    end
    local term = safeText(self.itemEntry and self.itemEntry:getText() or "")
    local selectedTag = self:getSelectedTagFilter()
    local selectedOrigin = self:getSelectedOriginFilter()
    self:applyCatalogFilter(term, selectedTag, selectedOrigin)
end

function MS_ItemRuntimeDebugWindow:onOriginFilterChanged()
    if #self.catalogItems <= 0 then
        return
    end
    local term = safeText(self.itemEntry and self.itemEntry:getText() or "")
    local selectedTag = self:getSelectedTagFilter()
    local selectedOrigin = self:getSelectedOriginFilter()
    self:applyCatalogFilter(term, selectedTag, selectedOrigin)
end

function MS_ItemRuntimeDebugWindow:onClearClick()
    DynamicTrading.ClearRuntimeCache()
    
    local reloaded = false
    if DynamicTrading.ReloadRuntimeRegistry then
        DynamicTrading.ReloadRuntimeRegistry()
        reloaded = true
    end

    self.catalogItems = {}
    self.filteredCatalogItems = {}
    self.selectedCatalogFullType = nil
    self:refreshCatalogList()
    
    if reloaded then
        self:setStatus("Runtime cache cleared and DT_Items registry reloaded.")
    else
        self:setStatus("Runtime cache cleared. Catalog browser reset.")
    end
end

function MS_ItemRuntimeDebugWindow:onBuildClick()
    local catalog = DynamicTrading.BuildRuntimeCatalog()
    self.catalogItems = self:buildCatalogIndex(catalog)

    local term = safeText(self.itemEntry and self.itemEntry:getText() or "")
    local selectedTag = self:getSelectedTagFilter()
    local selectedOrigin = self:getSelectedOriginFilter()
    self:applyCatalogFilter(term, selectedTag, selectedOrigin)

    self:setStatus("Built catalog for " .. tostring(catalog.total or #self.catalogItems) .. " items.")
end

function MS_ItemRuntimeDebugWindow:onExportClick()
    local exported = DynamicTrading.ExportCatalogDebug()
    self.lastExportPreview = string.sub(exported or "", 1, 240)
    self:setStatus("Export generated. Preview stored in pricing panel footer.")

    if self.result then
        self:refreshReport(self.result)
    end
end

function MS_ItemRuntimeDebugWindow:onExportTextClick()
    if #self.catalogItems <= 0 then
        local catalog = DynamicTrading.BuildRuntimeCatalog()
        self.catalogItems = self:buildCatalogIndex(catalog)
        self.filteredCatalogItems = self.catalogItems
        self:refreshCatalogList()
    end

    if #self.catalogItems <= 0 then
        self:setStatus("No cached items available to dump.")
        return
    end

    local fileName = "MarketSense_ItemRuntimeCacheDump.txt"
    local writer = getFileWriter(fileName, true, false)
    if not writer then
        self:setStatus("Failed to create text export file.")
        return
    end

    local total = self:writeFormattedCacheDump(writer, self.catalogItems)
    writer:close()
    self:setStatus("Dumped " .. tostring(total) .. " cached items to " .. fileName)
end

function MS_ItemRuntimeDebugWindow:onCatalogSelected(entry)
    local selected = entry
    if not selected or not selected.fullType then
        return
    end

    self.selectedCatalogFullType = selected.fullType
    if self.itemEntry then
        self.itemEntry:setText(selected.fullType)
    end

    self:refreshReport(DynamicTrading.DebugItem(selected.fullType))
end

function MS_ItemRuntimeDebugWindow.Open()
    if MS_ItemRuntimeDebugWindow.instance then
        MS_ItemRuntimeDebugWindow.instance:bringToTop()
        MS_ItemRuntimeDebugWindow.instance:setVisible(true)
        return MS_ItemRuntimeDebugWindow.instance
    end

    local screenW = getCore():getScreenWidth()
    local screenH = getCore():getScreenHeight()
    local width = math.max(860, math.min(1460, math.floor(screenW * 0.92)))
    local height = math.max(560, math.min(900, math.floor(screenH * 0.90)))
    local x = math.floor((screenW - width) * 0.5)
    local y = math.floor((screenH - height) * 0.5)

    local window = MS_ItemRuntimeDebugWindow:new(x, y, width, height)
    window:initialise()
    window:addToUIManager()
    window:setVisible(true)
    window:createChildren()
    window:onResize()

    MS_ItemRuntimeDebugWindow.instance = window
    return window
end

function MS_ItemRuntimeDebugWindow:new(x, y, width, height)
    local o = ISCollapsableWindow:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.backgroundColor = { r = 0.04, g = 0.04, b = 0.04, a = 0.98 }
    o.borderColor = { r = 0.35, g = 0.35, b = 0.35, a = 1 }
    return o
end

return MS_ItemRuntimeDebugWindow
