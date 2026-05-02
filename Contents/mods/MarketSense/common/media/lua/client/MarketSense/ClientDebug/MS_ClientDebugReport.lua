local Report = {}

function Report.attach(windowClass, deps)
    local safeText = deps.safeText
    local toRichText = deps.toRichText
    local compareSignatureEntries = deps.compareSignatureEntries

    function windowClass:refreshReport(report)
        report = report or {}
        self.result = report

        local context = DynamicTrading.PropertyReader and DynamicTrading.PropertyReader.buildContext
            and DynamicTrading.PropertyReader.buildContext(report.fullType)
            or nil

        local summaryLines = {
            " <RGB:0.92,0.92,0.92> Full Type: <RGB:0.70,0.82,0.96> " .. safeText(report.fullType, "-"),
            " <RGB:0.92,0.92,0.92> Module: <RGB:0.78,0.90,0.78> " .. safeText(report.moduleName, "-"),
            " <RGB:0.92,0.92,0.92> Source Mod: <RGB:0.82,0.90,0.96> " .. safeText(report.sourceModName, "Unknown"),
            " <RGB:0.92,0.92,0.92> Source Mod ID: <RGB:0.82,0.90,0.96> " .. safeText(report.sourceModId, "-"),
            " <RGB:0.92,0.92,0.92> Display: <RGB:0.96,0.84,0.68> " .. safeText(context and context.displayName or report.typeName, "-"),
            " <RGB:0.92,0.92,0.92> Display Category: <RGB:0.82,0.82,0.96> " .. safeText(context and context.displayCategory, "-"),
            " <RGB:0.92,0.92,0.92> Category: <RGB:0.96,0.84,0.68> " .. safeText(report.category, "-"),
            " <RGB:0.92,0.92,0.92> Primary Tag: <RGB:0.72,0.86,0.72> " .. safeText(report.primary, "-"),
            " <RGB:0.92,0.92,0.92> Final Price: <RGB:0.78,0.96,0.72> " .. safeText(report.price, "0"),
            " <RGB:0.92,0.92,0.92> Generated Price Seed: <RGB:0.82,0.82,0.96> rawScore=" .. safeText(report.rawScore, "0"),
            " <RGB:0.92,0.92,0.92> Raw Score: <RGB:0.78,0.96,0.72> " .. safeText(report.rawScore, "0"),
            " <RGB:0.92,0.92,0.92> Stock Range: <RGB:0.78,0.96,0.72> "
                .. safeText(report.stock and report.stock.min or 0) .. " - " .. safeText(report.stock and report.stock.max or 0),
            (function()
                local src = safeText(report.lookupSource, "-")
                local srcColor
                if     src == "override" then srcColor = "<RGB:0.95,0.78,0.30>"  -- amber  = manager override
                elseif src == "cache"    then srcColor = "<RGB:0.60,0.88,0.60>"  -- green  = cached hit
                elseif src == "static"   then srcColor = "<RGB:0.70,0.82,0.96>"  -- blue   = static catalog
                elseif src == "lazy"     then srcColor = "<RGB:0.82,0.76,0.96>"  -- purple = heuristic computed
                else                          srcColor = "<RGB:0.82,0.82,0.96>"
                end
                local hint = src == "override" and "  (manager file)"
                          or src == "cache"    and "  (runtime cache)"
                          or src == "static"   and "  (DT_StaticCatalog)"
                          or src == "lazy"     and "  (heuristic on-demand)"
                          or ""
                return " <RGB:0.92,0.92,0.92> Lookup Source: " .. srcColor .. src .. " <RGB:0.60,0.60,0.60>" .. hint
            end)(),
            " <RGB:0.92,0.92,0.92> Confidence: <RGB:0.82,0.82,0.96> " .. safeText(report.confidence, "0"),
        }

        -- Manager Runtime Rules status block
        local RR = DynamicTrading.RuntimeRules
        if RR and report.fullType and report.fullType ~= "" then
            RR.loadFromFile(true)
            local isBlacklisted = RR.blacklist[report.fullType] == true
            local isWhitelisted = RR.whitelist[report.fullType] == true
            local hasOverride   = RR.appliedItems and RR.appliedItems[report.fullType] == true
            local overrideData  = RR.getOverride and RR.getOverride(report.fullType) or nil
            local rulesLoaded   = RR.loaded == true

            local blacklistCount = 0
            local whitelistCount = 0
            local overrideCount  = 0
            for _ in pairs(RR.blacklist or {})        do blacklistCount = blacklistCount + 1 end
            for _ in pairs(RR.whitelist or {})        do whitelistCount = whitelistCount + 1 end
            for _ in pairs(RR.appliedItems or {})     do overrideCount  = overrideCount  + 1 end

            local fileStatus = rulesLoaded
                and string.format("<RGB:0.60,0.92,0.60>loaded  <RGB:0.70,0.70,0.70>(BL:%d  WL:%d  Overrides:%d)", blacklistCount, whitelistCount, overrideCount)
                or  "<RGB:0.90,0.50,0.30>not loaded"

            local bStr = isBlacklisted and "<RGB:1.00,0.38,0.38>YES" or "<RGB:0.55,0.75,0.55>no"
            local wStr = isWhitelisted and "<RGB:0.45,0.92,0.55>YES" or "<RGB:0.55,0.55,0.55>no"
            local oStr = hasOverride   and "<RGB:0.95,0.78,0.30>YES" or "<RGB:0.55,0.55,0.55>no"

            summaryLines[#summaryLines + 1] = " <LINE>"
            summaryLines[#summaryLines + 1] = " <RGB:0.80,0.80,1.00> -- Manager Runtime Rules --"
                summaryLines[#summaryLines + 1] = " <RGB:0.60,0.60,0.60> File: DT/MarketSense/Items/MS_RuntimeRules_Data.lua"
            summaryLines[#summaryLines + 1] = " <RGB:0.92,0.92,0.92> Rules File: " .. fileStatus
            summaryLines[#summaryLines + 1] = " <RGB:0.92,0.92,0.92> Blacklisted:       " .. bStr
            summaryLines[#summaryLines + 1] = " <RGB:0.92,0.92,0.92> Whitelisted:       " .. wStr
            summaryLines[#summaryLines + 1] = " <RGB:0.92,0.92,0.92> Manager Override:  " .. oStr

            if hasOverride and type(overrideData) == "table" then
                local overrideTags = table.concat(overrideData.tags or {}, ", ")
                local stockMin = overrideData.stock and overrideData.stock.min or "-"
                local stockMax = overrideData.stock and overrideData.stock.max or "-"

                summaryLines[#summaryLines + 1] = " <RGB:0.70,0.70,0.70> Override Details:"
                summaryLines[#summaryLines + 1] = " <RGB:0.70,0.70,0.70>   price    = " .. safeText(overrideData.price, "-")
                summaryLines[#summaryLines + 1] = " <RGB:0.70,0.70,0.70>   tags     = " .. safeText(overrideTags, "-")
                summaryLines[#summaryLines + 1] = " <RGB:0.70,0.70,0.70>   stockMin = " .. safeText(stockMin, "-")
                summaryLines[#summaryLines + 1] = " <RGB:0.70,0.70,0.70>   stockMax = " .. safeText(stockMax, "-")
            end
        end

        if context then
            summaryLines[#summaryLines + 1] = " <LINE> <RGB:0.92,0.92,0.92> Weight: <RGB:0.82,0.82,0.96> " .. safeText(context.weight, "0")
            summaryLines[#summaryLines + 1] = " <RGB:0.92,0.92,0.92> Flags: <RGB:0.82,0.82,0.96> "
                .. string.format(
                    "drainable=%s, water=%s, cookable=%s, moveable=%s",
                    tostring(context.isDrainable == true),
                    tostring(context.canStoreWater == true),
                    tostring(context.isCookable == true),
                    tostring(context.isMoveable == true)
                )
        end

        self.summaryText:setText(toRichText(summaryLines))
        self.summaryText:paginate()

        self.tagList:clear()
        local seenTags = {}
        for _, tag in ipairs(report.tags or {}) do
            seenTags[tag] = true
            self.tagList:addItem(tag, { tag = tag, kind = "base" })
        end
        for _, tag in ipairs(report.expandedTags or {}) do
            if not seenTags[tag] then
                self.tagList:addItem(tag, { tag = tag, kind = "expanded" })
            end
        end

        local pricingLines = {
            " <RGB:0.92,0.92,0.92> Balance Steps:",
        }

        if report.appliedBalances and #report.appliedBalances > 0 then
            for _, entry in ipairs(report.appliedBalances) do
                pricingLines[#pricingLines + 1] = string.format(
                    " <RGB:0.72,0.86,0.72> %s <RGB:0.80,0.80,0.80> %.2f -> %.2f",
                    safeText(entry.label, "?"),
                    tonumber(entry.before) or 0,
                    tonumber(entry.after) or 0
                )
            end
        else
            pricingLines[#pricingLines + 1] = " <RGB:0.80,0.80,0.80> No pricing audit entries available."
        end

        if context then
            pricingLines[#pricingLines + 1] = " <LINE> <RGB:0.92,0.92,0.92> Context Snapshot:"
            pricingLines[#pricingLines + 1] = string.format(
                " <RGB:0.82,0.82,0.96> hunger=%s thirst=%s calories=%s daysFresh=%s daysRotten=%s",
                safeText(context.hunger, "0"),
                safeText(context.thirst, "0"),
                safeText(context.calories, "0"),
                safeText(context.daysFresh, "0"),
                safeText(context.daysRotten, "0")
            )
            pricingLines[#pricingLines + 1] = string.format(
                " <RGB:0.82,0.82,0.96> minDamage=%s maxDamage=%s capacity=%s conditionMax=%s",
                safeText(context.minDamage, "0"),
                safeText(context.maxDamage, "0"),
                safeText(context.capacity, "0"),
                safeText(context.conditionMax, "0")
            )
        end

        if self.lastExportPreview and self.lastExportPreview ~= "" then
            pricingLines[#pricingLines + 1] = " <LINE> <RGB:0.92,0.92,0.92> Last Export Preview:"
            pricingLines[#pricingLines + 1] = " <RGB:0.80,0.80,0.80> " .. self.lastExportPreview
        end

        self.pricingText:setText(toRichText(pricingLines))
        self.pricingText:paginate()

        self.signatureList:clear()
        local signatures = {}
        for _, entry in ipairs(report.signatureComparisons or {}) do
            signatures[#signatures + 1] = entry
        end
        table.sort(signatures, compareSignatureEntries)
        for _, entry in ipairs(signatures) do
            self.signatureList:addItem(safeText(entry.signature, "?"), entry)
        end

        if report.fullType and report.fullType ~= "" then
            self:setStatus("Loaded " .. safeText(report.fullType) .. " from " .. safeText(report.lookupSource, "debug"))
            self:selectCatalogItem(report.fullType)
        else
            self:setStatus("No item loaded.")
        end
    end

    function windowClass:buildFormattedReportText(report)
        report = report or self.result or {}

        local context = DynamicTrading.PropertyReader and DynamicTrading.PropertyReader.buildContext
            and DynamicTrading.PropertyReader.buildContext(report.fullType)
            or nil

        local lines = {
            "=== MarketSense Item Runtime Debug ===",
            "FullType: " .. safeText(report.fullType, "-"),
            "Module: " .. safeText(report.moduleName, "-"),
            "Display: " .. safeText(context and context.displayName or report.typeName, "-"),
            "DisplayCategory: " .. safeText(context and context.displayCategory, "-"),
            "Category: " .. safeText(report.category, "-"),
            "PrimaryTag: " .. safeText(report.primary, "-"),
            "Price: " .. safeText(report.price, "0"),
            "RawScore: " .. safeText(report.rawScore, "0"),
            "StockRange: " .. safeText(report.stock and report.stock.min or 0) .. " - " .. safeText(report.stock and report.stock.max or 0),
            "LookupSource: " .. safeText(report.lookupSource, "-"),
            "Confidence: " .. safeText(report.confidence, "0"),
            "",
            "BaseTags: " .. table.concat(report.tags or {}, ", "),
            "ExpandedTags: " .. table.concat(report.expandedTags or {}, ", "),
            "",
            "BalanceSteps:",
        }

        if report.appliedBalances and #report.appliedBalances > 0 then
            for _, entry in ipairs(report.appliedBalances) do
                lines[#lines + 1] = string.format(
                    "- %s: %.2f -> %.2f",
                    safeText(entry.label, "?"),
                    tonumber(entry.before) or 0,
                    tonumber(entry.after) or 0
                )
            end
        else
            lines[#lines + 1] = "- none"
        end

        lines[#lines + 1] = ""
        lines[#lines + 1] = "SignatureComparisons:"
        if report.signatureComparisons and #report.signatureComparisons > 0 then
            for _, entry in ipairs(report.signatureComparisons) do
                lines[#lines + 1] = string.format(
                    "- %s | matched=%s | confidence=%.2f | primary=%s",
                    safeText(entry.signature, "?"),
                    tostring(entry.matched == true),
                    tonumber(entry.confidence) or 0,
                    safeText(entry.primary, "Misc.General")
                )
            end
        else
            lines[#lines + 1] = "- none"
        end

        if context then
            lines[#lines + 1] = ""
            lines[#lines + 1] = "Context:"
            lines[#lines + 1] = string.format(
                "hunger=%s thirst=%s calories=%s daysFresh=%s daysRotten=%s",
                safeText(context.hunger, "0"),
                safeText(context.thirst, "0"),
                safeText(context.calories, "0"),
                safeText(context.daysFresh, "0"),
                safeText(context.daysRotten, "0")
            )
            lines[#lines + 1] = string.format(
                "minDamage=%s maxDamage=%s capacity=%s conditionMax=%s",
                safeText(context.minDamage, "0"),
                safeText(context.maxDamage, "0"),
                safeText(context.capacity, "0"),
                safeText(context.conditionMax, "0")
            )
            lines[#lines + 1] = string.format(
                "weight=%s flags=[drainable=%s, water=%s, cookable=%s, moveable=%s]",
                safeText(context.weight, "0"),
                tostring(context.isDrainable == true),
                tostring(context.canStoreWater == true),
                tostring(context.isCookable == true),
                tostring(context.isMoveable == true)
            )
        end

        return table.concat(lines, "\r\n") .. "\r\n"
    end

    function windowClass:writeFormattedCacheDump(writer, catalogItems)
        if not writer then
            return 0
        end

        local function tokenOrFallback(value, fallback)
            local text = safeText(value, fallback or "")
            text = tostring(text or "")
            text = text:gsub("[\r\n]", " ")
            text = text:gsub(",", " ")
            text = text:gsub("%{", "(")
            text = text:gsub("%}", ")")
            text = text:gsub("^%s+", "")
            text = text:gsub("%s+$", "")
            if text == "" then
                return fallback or "Unknown"
            end
            return text
        end

        local function boolToLuaToken(value)
            return value and "TRUE" or "FALSE"
        end

        local function numberOrZero(value)
            return tonumber(value) or 0
        end

        local items = catalogItems or self.catalogItems or {}
        local total = #items
        writer:write("-- MarketSense Runtime Legacy Item Dump\r\n")
        writer:write("-- Schema: item <ItemID> { Key = Value, ... }\r\n")
        writer:write("-- ItemCount=" .. tostring(total) .. "\r\n\r\n")

        for _, entry in ipairs(items) do
            local fullType = entry and entry.fullType or nil
            if fullType and fullType ~= "" then
                local report = DynamicTrading.DebugItem(fullType) or { fullType = fullType }
                local context = DynamicTrading.PropertyReader and DynamicTrading.PropertyReader.buildContext
                    and DynamicTrading.PropertyReader.buildContext(report.fullType)
                    or nil

                local moduleName = safeText(report.moduleName, context and context.moduleName or "Base")
                local typeName = safeText(report.typeName, context and context.typeName or "Unknown")
                local itemId = tokenOrFallback(typeName, "Unknown")
                local fullTypeToken = tokenOrFallback(report.fullType, moduleName .. "." .. itemId)
                local displayNameToken = tokenOrFallback(typeName, itemId)
                local tagsValue = table.concat(report.tags or {}, ";")
                local expandedTagsValue = table.concat(report.expandedTags or {}, ";")

                writer:write("item " .. itemId .. " {\r\n")
                writer:write("    FullType = " .. fullTypeToken .. ",\r\n")
                writer:write("    Module = " .. tokenOrFallback(moduleName, "Base") .. ",\r\n")
                writer:write("    DisplayName = " .. displayNameToken .. ",\r\n")
                writer:write("    DisplayCategory = " .. tokenOrFallback(context and context.displayCategory or "", "None") .. ",\r\n")
                writer:write("    Category = " .. tokenOrFallback(report.category, "Misc") .. ",\r\n")
                writer:write("    PrimaryTag = " .. tokenOrFallback(report.primary, "Misc.General") .. ",\r\n")
                writer:write("    Weight = " .. tostring(numberOrZero(context and context.weight)) .. ",\r\n")
                writer:write("    HungerChange = " .. tostring(-numberOrZero(context and context.hunger)) .. ",\r\n")
                writer:write("    ThirstChange = " .. tostring(-numberOrZero(context and context.thirst)) .. ",\r\n")
                writer:write("    Calories = " .. tostring(numberOrZero(context and context.calories)) .. ",\r\n")
                writer:write("    DaysFresh = " .. tostring(numberOrZero(context and context.daysFresh)) .. ",\r\n")
                writer:write("    DaysTotallyRotten = " .. tostring(numberOrZero(context and context.daysRotten)) .. ",\r\n")
                writer:write("    UnhappyChange = " .. tostring(numberOrZero(context and context.unhappy)) .. ",\r\n")
                writer:write("    BoredomChange = " .. tostring(numberOrZero(context and context.boredom)) .. ",\r\n")
                writer:write("    StressChange = " .. tostring(numberOrZero(context and context.stress)) .. ",\r\n")
                writer:write("    MinDamage = " .. tostring(numberOrZero(context and context.minDamage)) .. ",\r\n")
                writer:write("    MaxDamage = " .. tostring(numberOrZero(context and context.maxDamage)) .. ",\r\n")
                writer:write("    MaxRange = " .. tostring(numberOrZero(context and context.maxRange)) .. ",\r\n")
                writer:write("    MaxHitCount = " .. tostring(numberOrZero(context and context.maxHit)) .. ",\r\n")
                writer:write("    ConditionMax = " .. tostring(numberOrZero(context and context.conditionMax)) .. ",\r\n")
                writer:write("    UseDelta = " .. tostring(numberOrZero(context and context.useDelta)) .. ",\r\n")
                writer:write("    Capacity = " .. tostring(numberOrZero(context and context.capacity)) .. ",\r\n")
                writer:write("    WeightReduction = " .. tostring(numberOrZero(context and context.weightReduction)) .. ",\r\n")
                writer:write("    BiteDefense = " .. tostring(numberOrZero(context and context.biteDefense)) .. ",\r\n")
                writer:write("    ScratchDefense = " .. tostring(numberOrZero(context and context.scratchDefense)) .. ",\r\n")
                writer:write("    BulletDefense = " .. tostring(numberOrZero(context and context.bulletDefense)) .. ",\r\n")
                writer:write("    Insulation = " .. tostring(numberOrZero(context and context.insulation)) .. ",\r\n")
                writer:write("    WindResistance = " .. tostring(numberOrZero(context and context.windResistance)) .. ",\r\n")
                writer:write("    IsCookable = " .. boolToLuaToken(context and context.isCookable == true) .. ",\r\n")
                writer:write("    IsDrainable = " .. boolToLuaToken(context and context.isDrainable == true) .. ",\r\n")
                writer:write("    CanStoreWater = " .. boolToLuaToken(context and context.canStoreWater == true) .. ",\r\n")
                writer:write("    AmmoType = " .. tokenOrFallback(context and context.ammoType or "", "None") .. ",\r\n")
                writer:write("    BodyLocation = " .. tokenOrFallback(context and context.bodyLocation or "", "None") .. ",\r\n")
                writer:write("    Tags = " .. tokenOrFallback(tagsValue, "Misc.General") .. ",\r\n")
                writer:write("    ExpandedTags = " .. tokenOrFallback(expandedTagsValue, "Misc.General") .. ",\r\n")
                writer:write("    DT_Price = " .. tostring(numberOrZero(report.price)) .. ",\r\n")
                writer:write("    DT_RawScore = " .. tostring(numberOrZero(report.rawScore)) .. ",\r\n")
                writer:write("    DT_StockMin = " .. tostring(numberOrZero(report.stock and report.stock.min)) .. ",\r\n")
                writer:write("    DT_StockMax = " .. tostring(numberOrZero(report.stock and report.stock.max)) .. ",\r\n")
                writer:write("    DT_LookupSource = " .. tokenOrFallback(report.lookupSource, "cache") .. ",\r\n")
                writer:write("    DT_Confidence = " .. tostring(numberOrZero(report.confidence)) .. ",\r\n")
                writer:write("}\r\n\r\n")
            end
        end

        return total
    end
end

return Report
