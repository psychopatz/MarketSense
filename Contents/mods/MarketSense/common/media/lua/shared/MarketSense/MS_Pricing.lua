require "MarketSense/MS_Core"
require "MarketSense/MS_Config"
require "MarketSense/MS_Stock"
require "MarketSense/signatures/tags/MS_TagMapper"
require "MarketSense/Pricing/MS_YieldResolver"

MarketSense = MarketSense or {}
MarketSense.Pricing = MarketSense.Pricing or {}

local Pricing = MarketSense.Pricing
local Core = MarketSense.Core
local Config = MarketSense.ItemRuntimeConfig
local TagMapper = MarketSense.TagMapper
local DB = MarketSense.HeuristicsDB
local YieldResolver = MarketSense.YieldResolver

-- Domain scorers and balance/override phases attach their stable public
-- functions to MarketSense.Pricing before the orchestration methods run.
require "MarketSense/Pricing/MS_PricingRaw"
require "MarketSense/Pricing/MS_PricingBalances"
require "MarketSense/Pricing/MS_PricingOverrides"
local applyTagOverrideIfPresent = Pricing.applyTagOverrideIfPresent
local VesselPricing = MarketSense.VesselPricing

local function attachHierarchy(details)
    local definition = TagMapper and TagMapper.getDefinition
        and TagMapper.getDefinition(details.primary) or nil
    if type(definition) ~= "table" then return details end
    details.subcategory = definition.subcategory or "General"
    details.leaf = definition.leaf or details.primary
    details.primaryPrefix = definition.primaryPrefix
    return details
end

local function resolveContext(fullTypeOrContext, inventoryItem)
    local ctx
    if type(fullTypeOrContext) == "table" and fullTypeOrContext.fullType and inventoryItem == nil then
        ctx = fullTypeOrContext
    elseif type(fullTypeOrContext) == "table" and fullTypeOrContext.fullType then
        ctx = MarketSense.PropertyReader.buildContext(fullTypeOrContext.item or fullTypeOrContext.fullType, inventoryItem)
    else
        ctx = MarketSense.PropertyReader.buildContext(fullTypeOrContext, inventoryItem)
    end
    return ctx
end

local function buildDetails(fullTypeOrContext, inventoryItem, internal)
    local ctx = resolveContext(fullTypeOrContext, inventoryItem)
    local tagInfo = internal and internal.tagInfo
        or MarketSense.AutoTag.generate(ctx)

    local temporaryContext = ctx.isTemporary == true
        or (ctx.foodFactTrace and ctx.foodFactTrace.isTemporary == true)
    local details = {
        fullType = ctx.fullType, moduleName = ctx.moduleName, typeName = ctx.typeName,
        sourceModId = ctx.sourceModId, sourceModName = ctx.sourceModName,
        category = tagInfo.category, primary = tagInfo.primary,
        subcategory = "General", leaf = tagInfo.primary,
        tags = Core.deepCopy(tagInfo.tags), expandedTags = Core.deepCopy(tagInfo.expandedTags),
        classificationDetails = Core.deepCopy(tagInfo.details or {}),
        descriptorEvidence = Core.deepCopy((tagInfo.details or {}).descriptorEvidence),
        descriptorRejected = Core.deepCopy((tagInfo.details or {}).descriptorRejected),
        rarityEvidence = Core.deepCopy((tagInfo.details or {}).rarityEvidence),
        weaponEvidence = Core.deepCopy((tagInfo.details or {}).weaponEvidence),
        confidence = tagInfo.confidence, rawScore = 0, price = 0, stock = nil, source = "lazy",
        -- Materialized catalog prices are deterministic definition prices;
        -- concrete inventory instances must be recalculated so a transferred
        -- liquid uses its current vessel instead of the cached definition.
        _instancePricing = inventoryItem ~= nil
            or (ctx.isInventoryItemInstance == true and not temporaryContext),
        _ignoreExactPrice = internal and internal.ignoreExactPrice == true or false,
    }

    local yieldPath = {}
    for key, value in pairs(internal and internal.yieldPath or {}) do
        yieldPath[key] = value
    end
    yieldPath[ctx.fullType] = true
    details._yieldPath = yieldPath
    details.yieldResolution = YieldResolver.resolve(ctx)

    return ctx, details
end

-- Builds the expensive, definition-dependent part of pricing. The returned
-- object is safe to persist as an intrinsic valuation snapshot; it does not
-- contain sandbox multipliers, save-seeded variation, or a final dollar price.
function Pricing.calculateIntrinsicDetails(fullTypeOrContext, withAudit, inventoryItem, internal)
    local ctx, details = buildDetails(fullTypeOrContext, inventoryItem, internal)

    local audit = withAudit and {} or nil
    attachHierarchy(details)
    applyTagOverrideIfPresent(ctx, details)
    attachHierarchy(details)
    details.rawScore = Pricing.calculateRawScore(ctx, details)
    details._cachedVesselPricing = VesselPricing
        and type(VesselPricing.calculate) == "function"
        and VesselPricing.calculate(ctx, details) or nil
    details.stock    = MarketSense.Stock.calculate(ctx.fullType, ctx, details)
    details.price = nil
    details.source = "intrinsic"
    if audit then
        audit[#audit + 1] = {
            stage = "intrinsic snapshot",
            before = details.rawScore,
            after = details.rawScore,
        }
        details.balanceAudit = audit
    end
    return details, ctx
end

function Pricing.calculateIntrinsicSnapshot(fullTypeOrContext, withAudit, inventoryItem, internal)
    local details, ctx = Pricing.calculateIntrinsicDetails(
        fullTypeOrContext, withAudit, inventoryItem, internal)
    if type(details) ~= "table" or type(ctx) ~= "table" then return nil end

    return {
        item = details.fullType,
        fullType = details.fullType,
        moduleName = details.moduleName,
        typeName = details.typeName,
        sourceModId = details.sourceModId,
        sourceModName = details.sourceModName,
        category = details.category,
        primary = details.primary,
        subcategory = details.subcategory,
        leaf = details.leaf,
        primaryPrefix = details.primaryPrefix,
        tags = Core.deepCopy(details.tags or {}),
        expandedTags = Core.deepCopy(details.expandedTags or {}),
        confidence = details.confidence,
        intrinsicScore = tonumber(details.rawScore) or 0,
        -- Keep the old field as an in-memory compatibility alias. Persisted
        -- V2 rows use the explicit intrinsicScore column instead.
        basePrice = tonumber(details.rawScore) or 0,
        rawScore = tonumber(details.rawScore) or 0,
        stockRange = Core.deepCopy(details.stock or { min = 0, max = 0 }),
        foodState = details.foodState,
        isActualLiquid = ctx.isActualLiquid == true,
        vesselPricing = Core.deepCopy(details._cachedVesselPricing),
        source = "intrinsic-cache",
    }
end

-- Finalizes a persisted intrinsic snapshot using the current sandbox and
-- modifier policy. This path deliberately reconstructs only the tiny context
-- required by the balance phase; it never invokes PropertyReader or AutoTag.
function Pricing.finalizeIntrinsicSnapshot(snapshot, withAudit, options)
    if type(snapshot) ~= "table" then return nil end
    options = options or {}

    local fullType = tostring(snapshot.fullType or snapshot.item or "")
    if fullType == "" then return nil end
    local moduleName = snapshot.moduleName
    local typeName = snapshot.typeName
    if (moduleName == nil or typeName == nil) and Core.splitFullType then
        moduleName, typeName = Core.splitFullType(fullType)
    end
    local ctx = options.context or {
        fullType = fullType,
        moduleName = moduleName,
        typeName = typeName,
        sourceModId = snapshot.sourceModId,
        sourceModName = snapshot.sourceModName,
    }
    local details = Core.deepCopy(snapshot)
    details.fullType = fullType
    details.item = fullType
    details.moduleName = details.moduleName or moduleName
    details.typeName = details.typeName or typeName
    details.tags = Core.deepCopy(details.tags or {})
    details.expandedTags = Core.deepCopy(details.expandedTags or details.tags)
    details.category = details.category or "Misc"
    details.primary = details.primary or details.tags[1] or "Misc"
    attachHierarchy(details)
    details.rawScore = tonumber(details.intrinsicScore or details.rawScore
        or details.basePrice) or (Config and Config.pricing.minPrice or 1)
    details._instancePricing = options.instancePricing == true
    details._ignoreExactPrice = options.ignoreExactPrice == true

    if not details._instancePricing then
        if VesselPricing and type(VesselPricing.calculateCached) == "function" then
            details._cachedVesselPricing = VesselPricing.calculateCached(snapshot, details)
        else
            details._cachedVesselPricing = Core.deepCopy(snapshot.vesselPricing)
        end
    end

    local audit = withAudit and {} or nil
    details.price = Pricing.applyBalances(ctx, details, audit)
    details.stock = Core.deepCopy(snapshot.stock
        or snapshot.stockRange or { min = 0, max = 0 })
    if details.stock.min == nil then details.stock.min = 0 end
    if details.stock.max == nil then details.stock.max = 0 end
    details.source = "intrinsic-cache"
    local itemEntry = DB and DB.getItem and DB.getItem(fullType) or nil
    if details.exactPrice ~= nil or (itemEntry and itemEntry.price ~= nil) then
        details.source = "override"
    end
    if audit then details.balanceAudit = audit end
    return details
end

function Pricing.calculateDetails(fullTypeOrContext, withAudit, inventoryItem, internal)
    local ctx, details = buildDetails(fullTypeOrContext, inventoryItem, internal)
    local audit = withAudit and {} or nil
    attachHierarchy(details)
    applyTagOverrideIfPresent(ctx, details)
    attachHierarchy(details)
    details.rawScore = Pricing.calculateRawScore(ctx, details)
    details.price    = Pricing.applyBalances(ctx, details, audit)
    details.stock    = MarketSense.Stock.calculate(ctx.fullType, ctx, details)
    if audit then details.balanceAudit = audit end
    return details
end

function Pricing.calculateCatalogPrice(ctx, tagInfo, withAudit)
    if type(ctx) ~= "table" or not ctx.fullType then return nil end
    -- Keep explicit item prices authoritative in the static catalog. The
    -- normal definition context already has no live vessel state; concrete
    -- inventory instances use GetPriceDetailsForInstance instead.
    local details = Pricing.calculateDetails(ctx, withAudit == true)
    return details and details.price or nil
end

function Pricing.generateDetailsOnce(fullTypeOrContext, withAudit)
    local details = Pricing.calculateDetails(fullTypeOrContext, withAudit)
    local ctx = type(fullTypeOrContext) == "table" and fullTypeOrContext.fullType
        and fullTypeOrContext or MarketSense.PropertyReader.buildContext(fullTypeOrContext)
    local itemEntry = DB.getItem(ctx.fullType)
    details.source = (itemEntry and (itemEntry.tags or itemEntry.stock or itemEntry.add or itemEntry.mult or itemEntry.price ~= nil))
        and "override" or "lazy"
    return details
end

return Pricing
