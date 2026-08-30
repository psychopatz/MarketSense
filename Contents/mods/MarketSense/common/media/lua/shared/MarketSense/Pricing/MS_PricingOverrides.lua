require "MarketSense/MS_Config"
require "MarketSense/MS_Core"
require "MarketSense/MS_HeuristicsDB"
require "MarketSense/MS_TagUtils"
require "MarketSense/MS_PropertyReader"
require "MarketSense/MS_Stock"
require "MarketSense/Pricing/MS_PricingUtils"

MarketSense = MarketSense or {}
MarketSense.Pricing = MarketSense.Pricing or {}

local Pricing = MarketSense.Pricing
local Core = MarketSense.Core
local TagUtils = MarketSense.TagUtils
local DB = MarketSense.HeuristicsDB
local Config = MarketSense.ItemRuntimeConfig
local Utils = require "MarketSense/Pricing/MS_PricingUtils"
local addAudit = Utils.addAudit
local applyAdjustment = Utils.applyAdjustment
local isFoodCategory = Utils.isFoodCategory
local isLiteratureCategory = Utils.isLiteratureCategory
local isClothingCategory = Utils.isClothingCategory
local isContainerCategory = Utils.isContainerCategory
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
                if text ~= "" then
                    removeSet[text] = true
                end
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

    local details = {
        fullType = ctx.fullType, moduleName = ctx.moduleName, typeName = ctx.typeName,
        sourceModId = ctx.sourceModId, sourceModName = ctx.sourceModName,
        category = tagInfo.category, primary = tagInfo.primary,
        tags = Core.deepCopy(tagInfo.tags), expandedTags = Core.deepCopy(tagInfo.expandedTags),
        classificationDetails = Core.deepCopy(tagInfo.details or {}),
        weaponEvidence = Core.deepCopy((tagInfo.details or {}).weaponEvidence),
        confidence = tagInfo.confidence, rawScore = 0, price = 0, stock = nil, source = "lazy",
    }

    local yieldPath = {}
    for key, value in pairs(internal and internal.yieldPath or {}) do
        yieldPath[key] = value
    end
    yieldPath[ctx.fullType] = true
    details._yieldPath = yieldPath
    details.yieldResolution = YieldResolver.resolve(ctx)

    local audit = withAudit and {} or nil
    applyTagOverrideIfPresent(ctx, details)
    details.rawScore = Pricing.calculateRawScore(ctx, details)
    details.price    = Pricing.applyBalances(ctx, details, audit)
    details.stock    = MarketSense.Stock.calculate(ctx.fullType, ctx, details)
    if audit then details.balanceAudit = audit end
    return details
end

function Pricing.applyOverridesOnly(fullTypeOrContext, staticDetails, withAudit)
    local ctx = type(fullTypeOrContext) == "table" and fullTypeOrContext.fullType
        and fullTypeOrContext or MarketSense.PropertyReader.buildContext(fullTypeOrContext)
    local details = Core.deepCopy(staticDetails or {})
    local audit = withAudit and {} or nil

    details.fullType    = details.fullType    or ctx.fullType
    details.moduleName  = details.moduleName  or ctx.moduleName
    details.typeName    = details.typeName    or ctx.typeName
    details.sourceModId = details.sourceModId or ctx.sourceModId
    details.sourceModName = details.sourceModName or ctx.sourceModName
    details.category    = details.category    or "Misc"
    details.primary     = details.primary     or "Misc"
    details.tags        = TagUtils.unique(details.tags or { details.primary })
    details.expandedTags = TagUtils.expandHierarchy(details.tags)
    details.rawScore    = tonumber(details.rawScore) or tonumber(details.price) or Config.pricing.minPrice

    local itemEntry = applyTagOverrideIfPresent(ctx, details)
    local working
    if details.category == "Weapon" or isLiteratureCategory(details.category)
        or isClothingCategory(details.category) or isContainerCategory(details.category)
        or details.category == "Tool" or details.category == "Electronics"
        or details.category == "Medical" or details.category == "Building"
        or details.category == "Liquid" or details.category == "Resource"
        or details.category == "Misc" then
        -- A cached detail may still contain a retired category score. Rebuild
        -- it after tag overrides so the cache cannot preserve legacy dollars.
        details.priceHeuristic = nil
        details.rawScore = Pricing.calculateRawScore(ctx, details)
        working = details.rawScore
    else
        working = tonumber(staticDetails and staticDetails.price or details.price or details.rawScore) or details.rawScore
    end

    addAudit(audit, "static baseline", working, working)

    local beforeSandbox = working
    local sandboxAdd = Config.pricing.globalValue or 0
    if Config.getSandboxTagMultiplier and details.category ~= "Weapon"
        and not isFoodCategory(details.category)
        and not isLiteratureCategory(details.category)
        and not isClothingCategory(details.category)
        and not isContainerCategory(details.category)
        and details.category ~= "Tool"
        and details.category ~= "Electronics"
        and details.category ~= "Medical"
        and details.category ~= "Building"
        and details.category ~= "Liquid"
        and details.category ~= "Resource"
        and details.category ~= "Misc" then
        local sandboxTags = { details.primary }
        for _, tag in ipairs(details.tags or {}) do
            if tag ~= details.primary and string.find(tag, ".", 1, true) then
                sandboxTags[#sandboxTags + 1] = tag
            end
        end
        sandboxAdd = sandboxAdd + Config.getSandboxTagMultiplier("Price", sandboxTags)
    end
    working = working + sandboxAdd
    addAudit(audit, "sandbox add", beforeSandbox, working, sandboxAdd)

    local beforeGlobal = working
    working = working * (tonumber(Config.pricing.baseMultiplier) or 1)
    addAudit(audit, "global mult", beforeGlobal, working)
    if not isFoodCategory(details.category) and details.category ~= "Weapon"
        and not isLiteratureCategory(details.category)
        and not isClothingCategory(details.category)
        and not isContainerCategory(details.category)
        and details.category ~= "Tool"
        and details.category ~= "Electronics"
        and details.category ~= "Medical"
        and details.category ~= "Building"
        and details.category ~= "Resource"
        and details.category ~= "Misc" then
        working = applyAdjustment(working, DB.getCategory(details.category), "category:" .. tostring(details.category), audit)
        for _, tag in ipairs(details.expandedTags or {}) do
            working = applyAdjustment(working, DB.getTag(tag), "tag:" .. tag, audit)
        end
    elseif details.category == "Weapon" then
        addAudit(audit, "weapon v2 balances", working, working, {
            legacyTagAdditions = false,
            reason = "Weapon valuation is combat performance, condition, handling, and recipe demand.",
        })
    elseif isLiteratureCategory(details.category) then
        addAudit(audit, "literature v2 balances", working, working, {
            legacyTagAdditions = false,
            reason = "Literature valuation is knowledge, information, entertainment, and writing utility.",
        })
    elseif isClothingCategory(details.category) then
        addAudit(audit, "clothing v2 balances", working, working, {
            legacyTagAdditions = false,
            reason = "Clothing valuation is protection, coverage, mobility, and condition.",
        })
    elseif isContainerCategory(details.category) then
        addAudit(audit, "container v2 balances", working, working, {
            legacyTagAdditions = false,
            reason = "Container valuation is useful capacity, carry efficiency, portability, and state.",
        })
    elseif details.category == "Tool" then
        addAudit(audit, "tool v2 balances", working, working, {
            legacyTagAdditions = false,
            reason = "Tool valuation is usefulness and recipe-demand driven.",
        })
    elseif details.category == "Electronics" then
        addAudit(audit, "electronics v2 balances", working, working, {
            legacyTagAdditions = false,
            reason = "Electronics valuation is verified device, light, power, and portability utility.",
        })
    elseif details.category == "Medical" then
        addAudit(audit, "medical v2 balances", working, working, {
            legacyTagAdditions = false,
            reason = "Medical valuation is treatment outcomes, doses, and patient-facing utility.",
        })
    elseif details.category == "Building" then
        addAudit(audit, "building v2 balances", working, working, {
            legacyTagAdditions = false,
            reason = "Building valuation is placed-object service, storage, and deployability utility.",
        })
    elseif details.category == "Liquid" then
        addAudit(audit, "liquid v2 balances", working, working, {
            legacyTagAdditions = false,
            reason = "Liquid valuation is measured amount, effects, fluid function, and safety.",
        })
    elseif details.category == "Resource" then
        addAudit(audit, "resource v2 balances", working, working, {
            legacyTagAdditions = false,
            reason = "Resource valuation is material role, usable form, quantity, and processing cost.",
        })
    elseif details.category == "Misc" then
        local heuristic = details.priceHeuristic or {}
        if heuristic.status == "ready" then
            addAudit(audit, "misc v2 heuristic balances", working, working, {
                legacyTagAdditions = false,
                model = heuristic.model,
                reason = "Deterministic Misc transform value is already included in the raw score.",
            })
        else
            addAudit(audit, "misc v2 fallback balances", working, working, {
                legacyTagAdditions = false,
                reason = "Misc fallback did not expose a ready heuristic; no legacy additions applied.",
            })
        end
    else
        addAudit(audit, "generic balances", working, working, {
            legacyTagAdditions = false,
            reason = "Generic category/tag balances applied.",
        })
    end
    working = applyAdjustment(working, DB.getModule(ctx.moduleName), "module:" .. tostring(ctx.moduleName), audit)
    working = applyAdjustment(working, itemEntry, "item:" .. tostring(ctx.fullType), audit)

    if itemEntry and itemEntry.price ~= nil then
        details.price = clampAndRound(itemEntry.price)
        addAudit(audit, "item final price", working, details.price)
        details.source = "override"
    else
        details.price  = clampAndRound(working)
        details.source = "static"
    end

    details.stock = MarketSense.Stock.calculate(ctx.fullType, ctx, details)
    if itemEntry and (itemEntry.tags or itemEntry.stock or itemEntry.add or itemEntry.mult or itemEntry.price ~= nil) then
        details.source = "override"
    end
    if audit then details.balanceAudit = audit end
    return details
end

Pricing.applyTagOverrideIfPresent = applyTagOverrideIfPresent

return Pricing
