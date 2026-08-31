require "MarketSense/MS_Config"
require "MarketSense/MS_Core"
require "MarketSense/MS_HeuristicsDB"
require "MarketSense/MS_TagUtils"
require "MarketSense/MS_PropertyReader"
require "MarketSense/MS_Stock"
require "MarketSense/Pricing/MS_PricingUtils"
require "MarketSense/Pricing/MS_MarketModifiers"

MarketSense = MarketSense or {}
MarketSense.Pricing = MarketSense.Pricing or {}

local Pricing = MarketSense.Pricing
local Core = MarketSense.Core
local TagUtils = MarketSense.TagUtils
local DB = MarketSense.HeuristicsDB
local Config = MarketSense.ItemRuntimeConfig
local Utils = require "MarketSense/Pricing/MS_PricingUtils"
local MarketModifiers = require "MarketSense/Pricing/MS_MarketModifiers"
local addAudit = Utils.addAudit
local clampAndRound = Utils.clampAndRound

local function applyTagOverrideIfPresent(ctx, details)
    local itemEntry = DB.getItem(ctx.fullType)
    if itemEntry and type(itemEntry.tags) == "table" and #itemEntry.tags > 0 then
        details.tags = TagUtils.unique(itemEntry.tags)
        details.primary = details.tags[1] or details.primary
        details.category = TagUtils.categoryFromPrimary(details.primary)
        details.expandedTags = TagUtils.expandHierarchy(details.tags)
    elseif itemEntry and (type(itemEntry.addTags) == "table" or type(itemEntry.removeTags) == "table") then
        local merged = Core.deepCopy(details.tags or {})

        if type(itemEntry.addTags) == "table" then
            for _, tag in ipairs(itemEntry.addTags) do
                merged[#merged + 1] = tostring(tag)
            end
        end

        if type(itemEntry.removeTags) == "table" then
            local removeSet = {}
            for _, tag in ipairs(itemEntry.removeTags) do
                local text = tostring(tag or "")
                if text ~= "" then removeSet[text] = true end
            end

            local filtered = {}
            for _, tag in ipairs(merged) do
                if not removeSet[tostring(tag or "")] then
                    filtered[#filtered + 1] = tag
                end
            end
            merged = filtered
        end

        details.tags = TagUtils.unique(merged)
        details.primary = details.tags[1] or details.primary
        details.category = TagUtils.categoryFromPrimary(details.primary)
        details.expandedTags = TagUtils.expandHierarchy(details.tags)
    end
    return itemEntry
end

function Pricing.applyOverridesOnly(fullTypeOrContext, staticDetails, withAudit)
    local ctx = type(fullTypeOrContext) == "table" and fullTypeOrContext.fullType
        and fullTypeOrContext or MarketSense.PropertyReader.buildContext(fullTypeOrContext)
    local details = Core.deepCopy(staticDetails or {})
    local audit = withAudit and {} or nil

    details.fullType = details.fullType or ctx.fullType
    details.moduleName = details.moduleName or ctx.moduleName
    details.typeName = details.typeName or ctx.typeName
    details.sourceModId = details.sourceModId or ctx.sourceModId
    details.sourceModName = details.sourceModName or ctx.sourceModName
    details.category = details.category or "Misc"
    details.primary = details.primary or "Misc"
    details.tags = TagUtils.unique(details.tags or { details.primary })
    details.expandedTags = TagUtils.expandHierarchy(details.tags)
    details.rawScore = tonumber(details.rawScore)
        or tonumber(details.price) or Config.pricing.minPrice

    local itemEntry = applyTagOverrideIfPresent(ctx, details)
    local working
    if details.category == "Weapon" or details.category == "Literature"
        or details.category == "Clothing" or details.category == "Container"
        or details.category == "Tool" or details.category == "Electronics"
        or details.category == "Medical" or details.category == "Building"
        or details.category == "Liquid" or details.category == "Resource"
        or details.category == "Misc" or details.category == "Food"
        or details.category == "Beverage" then
        -- Rebuild category scores after a tag override so cached legacy dollars
        -- cannot survive a resolver refresh.
        details.priceHeuristic = nil
        details.rawScore = Pricing.calculateRawScore(ctx, details)
        working = details.rawScore
    else
        working = tonumber(staticDetails and staticDetails.price
            or details.price or details.rawScore) or details.rawScore
    end

    addAudit(audit, "static baseline", working, working)
    if not (itemEntry and itemEntry.price ~= nil) then
        local bandSummary = {}
        working = MarketModifiers.applyCategoryBand(working, details, audit, bandSummary)
        details.priceBandApplied = true
        if details.priceHeuristic and bandSummary.categoryBand then
            details.priceHeuristic.categoryBand = Core.deepCopy(bandSummary.categoryBand)
        end
    end
    working = MarketModifiers.apply(ctx, details, working, audit)

    local beforeSandbox = working
    local sandboxAdd = tonumber(Config.pricing.globalValue) or 0
    working = working + sandboxAdd
    addAudit(audit, "sandbox global add", beforeSandbox, working, sandboxAdd)

    local beforeGlobal = working
    working = working * (tonumber(Config.pricing.baseMultiplier) or 1)
    addAudit(audit, "global mult", beforeGlobal, working, Config.pricing.baseMultiplier)

    if itemEntry and itemEntry.price ~= nil then
        local overridePrice = details.marketPricing
            and details.marketPricing.overridePrice or itemEntry.price
        details.price = clampAndRound(overridePrice)
        addAudit(audit, "item final price", working, details.price)
        details.source = "override"
    else
        details.price = clampAndRound(working)
        details.source = "static"
    end

    details.stock = MarketSense.Stock.calculate(ctx.fullType, ctx, details)
    if itemEntry and (itemEntry.tags or itemEntry.stock or itemEntry.add
        or itemEntry.mult or itemEntry.price ~= nil) then
        details.source = "override"
    end
    if audit then details.balanceAudit = audit end
    return details
end

Pricing.applyTagOverrideIfPresent = applyTagOverrideIfPresent

return Pricing
