require "MarketSense/DT_Pricing"

DynamicTrading = DynamicTrading or {}
DynamicTrading.DebugTools = DynamicTrading.DebugTools or {}

local DebugTools = DynamicTrading.DebugTools
local Core = DynamicTrading.Core
local Cache = DynamicTrading.RuntimeCache

local function serialize(value, indent)
    indent = indent or ""
    local nextIndent = indent .. "    "

    if type(value) == "string" then
        return string.format("%q", value)
    end
    if type(value) ~= "table" then
        return tostring(value)
    end

    local lines = { "{" }
    for key, innerValue in pairs(value) do
        local keyText
        if type(key) == "string" and string.match(key, "^[%a_][%w_]*$") then
            keyText = key
        else
            keyText = "[" .. serialize(key, nextIndent) .. "]"
        end
        lines[#lines + 1] = nextIndent .. keyText .. " = " .. serialize(innerValue, nextIndent) .. ","
    end
    lines[#lines + 1] = indent .. "}"
    return table.concat(lines, "\n")
end

local function buildTagLine(tags)
    return table.concat(tags or {}, ", ")
end

function DebugTools.inspect(fullType)
    local ctx = DynamicTrading.PropertyReader.buildContext(fullType)
    local cacheHit = Cache.getDetails(ctx.fullType) ~= nil
    local staticDetails = DynamicTrading.StaticCatalog[ctx.fullType]
    local signatureData = DynamicTrading.AutoTag.compareSignatures(ctx)
    local resolved = staticDetails
        and DynamicTrading.Pricing.applyOverridesOnly(ctx, staticDetails, true)
        or DynamicTrading.Pricing.generateDetailsOnce(ctx, true)

    local report = {
        source = "debug",
        lookupSource = cacheHit and "cache" or (staticDetails and "static" or "lazy"),
        fullType = ctx.fullType,
        moduleName = ctx.moduleName,
        typeName = ctx.typeName,
        sourceModId = ctx.sourceModId,
        sourceModName = ctx.sourceModName,
        category = resolved.category,
        primary = resolved.primary,
        tags = Core.deepCopy(resolved.tags),
        expandedTags = Core.deepCopy(resolved.expandedTags),
        confidence = resolved.confidence,
        rawScore = resolved.rawScore,
        price = resolved.price,
        stock = Core.deepCopy(resolved.stock),
        appliedBalances = Core.deepCopy(resolved.balanceAudit or {}),
        signatureComparisons = Core.deepCopy(signatureData.results or {}),
    }

    local lines = {
        "full type: " .. tostring(report.fullType),
        "module: " .. tostring(report.moduleName),
        "type name: " .. tostring(report.typeName),
        "category: " .. tostring(report.category),
        "primary tag: " .. tostring(report.primary),
        "tags: " .. buildTagLine(report.tags),
        "expanded tags: " .. buildTagLine(report.expandedTags),
        "confidence: " .. tostring(report.confidence or 0),
        "raw score: " .. tostring(report.rawScore or 0),
        "final price: " .. tostring(report.price or 0),
        "stock range: " .. tostring(report.stock and report.stock.min or 0) .. " - " .. tostring(report.stock and report.stock.max or 0),
        "source: " .. tostring(report.lookupSource),
    }

    report.text = table.concat(lines, "\n")

    if DynamicTrading.IsItemRuntimeDebugEnabled() then
        print("[DynamicTrading/ItemRuntime] " .. report.text)
    end

    return report
end

function DebugTools.scanAll()
    if DynamicTrading.BuildRuntimeCatalog then
        return DynamicTrading.BuildRuntimeCatalog()
    end
    return {
        items = {},
        total = 0,
        modules = {},
        categories = {},
        tags = {},
    }
end

function DebugTools.exportCatalog()
    local catalog = {
        items = {},
        total = 0,
    }

    if not Cache.built and DynamicTrading.BuildRuntimeCatalog then
        catalog = DynamicTrading.BuildRuntimeCatalog()
    else
        catalog.items = Core.deepCopy(Cache.details)
        for _ in pairs(catalog.items) do
            catalog.total = catalog.total + 1
        end
    end

    local compact = {}
    for fullType, details in pairs(catalog.items or {}) do
        compact[fullType] = {
            fullType = details.fullType,
            moduleName = details.moduleName,
            typeName = details.typeName,
            category = details.category,
            primary = details.primary,
            tags = details.tags,
            expandedTags = details.expandedTags,
            price = details.price,
            rawScore = details.rawScore,
            confidence = details.confidence,
            stock = details.stock,
        }
    end

    return "DynamicTrading = DynamicTrading or {}\nDynamicTrading.StaticCatalog = DynamicTrading.StaticCatalog or "
        .. serialize(compact) .. "\nreturn DynamicTrading.StaticCatalog"
end

DynamicTrading.DebugItem = DebugTools.inspect
DynamicTrading.DebugScanAll = DebugTools.scanAll
DynamicTrading.ExportCatalogDebug = DebugTools.exportCatalog

return DebugTools
