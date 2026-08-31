require "MarketSense/MS_Core"
require "MarketSense/MS_Config"
require "MarketSense/MS_Stock"
require "MarketSense/signatures/tags/MS_TagMapper"
require "MarketSense/Pricing/MS_YieldResolver"

MarketSense = MarketSense or {}
MarketSense.Pricing = MarketSense.Pricing or {}

local Pricing = MarketSense.Pricing
local Core = MarketSense.Core
local TagMapper = MarketSense.TagMapper
local DB = MarketSense.HeuristicsDB
local YieldResolver = MarketSense.YieldResolver

-- Domain scorers and balance/override phases attach their stable public
-- functions to MarketSense.Pricing before the orchestration methods run.
require "MarketSense/Pricing/MS_PricingRaw"
require "MarketSense/Pricing/MS_PricingBalances"
require "MarketSense/Pricing/MS_PricingOverrides"
local applyTagOverrideIfPresent = Pricing.applyTagOverrideIfPresent

local function attachHierarchy(details)
    local definition = TagMapper and TagMapper.getDefinition
        and TagMapper.getDefinition(details.primary) or nil
    if type(definition) ~= "table" then return details end
    details.subcategory = definition.subcategory or "General"
    details.leaf = definition.leaf or details.primary
    details.primaryPrefix = definition.primaryPrefix
    return details
end

function Pricing.calculateDetails(fullTypeOrContext, withAudit, inventoryItem, internal)
    local ctx
    if type(fullTypeOrContext) == "table" and fullTypeOrContext.fullType and inventoryItem == nil then
        ctx = fullTypeOrContext
    elseif type(fullTypeOrContext) == "table" and fullTypeOrContext.fullType then
        ctx = MarketSense.PropertyReader.buildContext(fullTypeOrContext.item or fullTypeOrContext.fullType, inventoryItem)
    else
        ctx = MarketSense.PropertyReader.buildContext(fullTypeOrContext, inventoryItem)
    end
    local tagInfo = MarketSense.AutoTag.generate(ctx)

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
