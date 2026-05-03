local Catalog = {}

-- Rendering thousands of ISScrollingListBox rows at once can freeze the UI.
-- Keep the full catalog in memory, but only push this many rows into the listbox.
local CATALOG_RENDER_LIMIT = 800

function Catalog.attach(windowClass, deps)
    deps = deps or {}

    local safeText = deps.safeText
    local safeNumber = deps.safeNumber
    local lower = deps.lower
    local compareCatalogEntries = deps.compareCatalogEntries
    local renderLimit = tonumber(deps.catalogRenderLimit) or CATALOG_RENDER_LIMIT

    local function entryHasTag(entry, selectedTagLower)
        if selectedTagLower == "" then
            return true
        end

        if entry.tagLookup then
            return entry.tagLookup[selectedTagLower] == true
        end

        if lower(entry.primary or "") == selectedTagLower then
            return true
        end

        for _, tag in ipairs(entry.tags or {}) do
            if lower(tag) == selectedTagLower then
                return true
            end
        end

        return false
    end

    function windowClass:buildCatalogIndex(catalog)
        local items = {}
        local tagSet = {}
        local source = catalog and catalog.items or nil

        self.catalogRenderLimit = renderLimit

        if type(source) ~= "table" then
            self.catalogTagOptions = { "All Tags" }
            self:refreshTagFilterOptions()
            return items
        end

        local count = 0

        for fullType, details in pairs(source) do
            local rawTags = details.tags or {}
            local tags = {}

            if type(rawTags) == "table" then
                for _, tag in ipairs(rawTags) do
                    local tagText = safeText(tag, "")
                    if tagText ~= "" then
                        tags[#tags + 1] = tagText
                    end
                end
            end

            local entry = {
                fullType = fullType,
                moduleName = safeText(details.moduleName, ""),
                typeName = safeText(details.typeName, ""),
                sourceModId = safeText(details.sourceModId, ""),
                sourceModName = safeText(details.sourceModName, ""),
                category = safeText(details.category, "Misc"),
                primary = safeText(details.primary, "Misc.General"),
                price = safeNumber(details.price, 0) or 0,
                confidence = safeNumber(details.confidence, 0) or 0,
                tags = tags,
                tagLookup = {},
            }

            if entry.primary ~= "" then
                tagSet[entry.primary] = true
                entry.tagLookup[lower(entry.primary)] = true
            end

            for _, tag in ipairs(entry.tags or {}) do
                if tag ~= "" then
                    tagSet[tag] = true
                    entry.tagLookup[lower(tag)] = true
                end
            end

            entry.searchText = lower(table.concat({
                entry.fullType,
                entry.moduleName,
                entry.typeName,
                entry.sourceModId,
                entry.sourceModName,
                entry.category,
                entry.primary,
                table.concat(entry.tags, " "),
            }, " "))

            count = count + 1
            items[count] = entry
        end

        table.sort(items, compareCatalogEntries)

        local tagOptions = { "All Tags" }

        for tag, _ in pairs(tagSet) do
            tagOptions[#tagOptions + 1] = tag
        end

        table.sort(tagOptions, function(a, b)
            if a == "All Tags" then
                return true
            end

            if b == "All Tags" then
                return false
            end

            return lower(a) < lower(b)
        end)

        self.catalogTagOptions = tagOptions
        self:refreshTagFilterOptions()

        return items
    end

    function windowClass:refreshTagFilterOptions()
        if not self.tagFilterCombo then
            return
        end

        local previous = self:getSelectedTagFilter()

        self.tagFilterCombo:clear()

        local options = self.catalogTagOptions or { "All Tags" }
        local selectedIndex = 1

        for index, label in ipairs(options) do
            self.tagFilterCombo:addOption(label)

            if previous ~= "" and label == previous then
                selectedIndex = index
            end
        end

        self.tagFilterCombo.selected = selectedIndex
        self.selectedTagFilter = selectedIndex > 1 and options[selectedIndex] or ""
    end

    function windowClass:getSelectedTagFilter()
        if not self.tagFilterCombo then
            return ""
        end

        local index = self.tagFilterCombo.selected or 1

        if index <= 1 then
            return ""
        end

        return safeText(self.tagFilterCombo:getOptionText(index), "")
    end

    function windowClass:refreshCatalogList()
        local previous = self.selectedCatalogFullType

        self.catalogList:clear()

        local source = self.filteredCatalogItems or {}
        local total = #(self.catalogItems or {})
        local filteredTotal = #source
        local maxRows = tonumber(self.catalogRenderLimit) or renderLimit
        local rowsToRender = math.min(filteredTotal, maxRows)

        for index = 1, rowsToRender do
            local entry = source[index]
            self.catalogList:addItem(entry.fullType, entry)
        end

        if previous then
            for index, row in ipairs(self.catalogList.items) do
                if row and row.item and row.item.fullType == previous then
                    self.catalogList.selected = index
                    break
                end
            end
        end

        if total <= 0 then
            self:setCatalogStatus("No catalog built yet.")
        elseif filteredTotal <= 0 then
            self:setCatalogStatus("No items match the current filter.")
        elseif filteredTotal > rowsToRender then
            self:setCatalogStatus(
                string.format(
                    "Showing first %d of %d matches. Narrow search or tag filter for more precise results.",
                    rowsToRender,
                    filteredTotal
                )
            )
        elseif filteredTotal == total then
            self:setCatalogStatus(string.format("Showing all %d generated items.", total))
        else
            self:setCatalogStatus(string.format("Showing %d of %d generated items.", filteredTotal, total))
        end
    end

    function windowClass:applyCatalogFilter(term, selectedTag)
        local query = lower(term)
        local tagFilter = safeText(selectedTag, "")
        local tagFilterLower = lower(tagFilter)

        if query == "" and tagFilterLower == "" then
            self.filteredCatalogItems = self.catalogItems or {}
            self.selectedTagFilter = ""
            self:refreshCatalogList()
            return
        end

        local filtered = {}
        local filteredCount = 0

        for _, entry in ipairs(self.catalogItems or {}) do
            local matchesText = (query == "") or string.find(entry.searchText, query, 1, true)
            local matchesTag = entryHasTag(entry, tagFilterLower)

            if matchesText and matchesTag then
                filteredCount = filteredCount + 1
                filtered[filteredCount] = entry
            end
        end

        self.filteredCatalogItems = filtered
        self.selectedTagFilter = tagFilter
        self:refreshCatalogList()
    end

    function windowClass:selectCatalogItem(fullType)
        if not fullType or not self.catalogList or not self.catalogList.items then
            return false
        end

        for index, row in ipairs(self.catalogList.items) do
            if row and row.item and row.item.fullType == fullType then
                self.catalogList.selected = index
                self.selectedCatalogFullType = fullType
                return true
            end
        end

        return false
    end
end

return Catalog
