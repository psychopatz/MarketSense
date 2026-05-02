local Catalog = {}

function Catalog.attach(windowClass, deps)
    local safeText = deps.safeText
    local safeNumber = deps.safeNumber
    local lower = deps.lower
    local compareCatalogEntries = deps.compareCatalogEntries

    local function entryHasTag(entry, selectedTagLower)
        if selectedTagLower == "" then
            return true
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
        if type(source) ~= "table" then
            self.catalogTagOptions = { "All Tags" }
            self:refreshTagFilterOptions()
            return items
        end

        for fullType, details in pairs(source) do
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
                tags = details.tags or {},
            }

            if entry.primary ~= "" then
                tagSet[entry.primary] = true
            end
            for _, tag in ipairs(entry.tags or {}) do
                if tag ~= "" then
                    tagSet[tag] = true
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
            items[#items + 1] = entry
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

        for _, entry in ipairs(self.filteredCatalogItems or {}) do
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

        local total = #(self.catalogItems or {})
        local shown = #(self.filteredCatalogItems or {})
        if total <= 0 then
            self:setCatalogStatus("No catalog built yet.")
        elseif shown == total then
            self:setCatalogStatus(string.format("Showing all %d generated items.", total))
        else
            self:setCatalogStatus(string.format("Showing %d of %d generated items.", shown, total))
        end
    end

    function windowClass:applyCatalogFilter(term, selectedTag)
        local query = lower(term)
        local tagFilter = safeText(selectedTag, "")
        local tagFilterLower = lower(tagFilter)

        local filtered = {}
        for _, entry in ipairs(self.catalogItems or {}) do
            local matchesText = (query == "") or string.find(entry.searchText, query, 1, true)
            local matchesTag = entryHasTag(entry, tagFilterLower)
            if matchesText and matchesTag then
                filtered[#filtered + 1] = entry
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
