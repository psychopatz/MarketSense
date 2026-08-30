require "MarketSense/MS_Core"
require "MarketSense/MS_Config"
require "MarketSense/MS_HeuristicsDB"
require "MarketSense/Pricing/MS_PricingUtils"

MarketSense = MarketSense or {}
MarketSense.MarketModifiers = MarketSense.MarketModifiers or {}

local Modifiers = MarketSense.MarketModifiers
local Core = MarketSense.Core
local Config = MarketSense.ItemRuntimeConfig
local DB = MarketSense.HeuristicsDB
local Utils = require "MarketSense/Pricing/MS_PricingUtils"
local addAudit = Utils.addAudit

local defaults = require "MarketSense/Pricing/MS_MarketModifiers_Data"
local tagModifiers = Modifiers.tagModifiers or {}
local categoryModifiers = Modifiers.categoryModifiers or {}
local itemModifiers = Modifiers.itemModifiers or {}

Modifiers.version = defaults.version or 1
Modifiers.tagModifiers = tagModifiers
Modifiers.categoryModifiers = categoryModifiers
Modifiers.itemModifiers = itemModifiers

local function copyRule(rule)
    return type(rule) == "table" and Core.deepCopy(rule) or {}
end

local function mergeRule(target, source)
    for key, value in pairs(source or {}) do
        if value ~= nil then target[key] = Core.deepCopy(value) end
    end
    return target
end

local function loadDefaults()
    for key, rule in pairs(defaults.tagModifiers or {}) do
        tagModifiers[key] = mergeRule(copyRule(tagModifiers[key]), rule)
    end
    for key, rule in pairs(defaults.categoryModifiers or {}) do
        categoryModifiers[key] = mergeRule(copyRule(categoryModifiers[key]), rule)
    end
    for key, rule in pairs(defaults.itemModifiers or {}) do
        itemModifiers[key] = mergeRule(copyRule(itemModifiers[key]), rule)
    end
end

loadDefaults()

local function applyExportedRules()
    local exported = Config and Config.marketModifiers or nil
    if type(exported) ~= "table" then return end
    for key, rule in pairs(exported.tag_modifiers or exported.tagModifiers or {}) do
        Modifiers.registerTag(key, rule)
    end
    for key, rule in pairs(exported.category_modifiers or exported.categoryModifiers or {}) do
        Modifiers.registerCategory(key, rule)
    end
    for key, rule in pairs(exported.item_modifiers or exported.itemModifiers or {}) do
        Modifiers.registerItem(key, rule)
    end
end

function Modifiers.registerTag(tag, rule)
    if type(tag) == "string" and tag ~= "" and type(rule) == "table" then
        tagModifiers[tag] = mergeRule(copyRule(tagModifiers[tag]), rule)
        return tagModifiers[tag]
    end
end

function Modifiers.registerCategory(category, rule)
    if type(category) == "string" and category ~= "" and type(rule) == "table" then
        categoryModifiers[category] = mergeRule(copyRule(categoryModifiers[category]), rule)
        return categoryModifiers[category]
    end
end

function Modifiers.registerItem(fullType, rule)
    if type(fullType) == "string" and fullType ~= "" and type(rule) == "table" then
        itemModifiers[fullType] = mergeRule(copyRule(itemModifiers[fullType]), rule)
        return itemModifiers[fullType]
    end
end

applyExportedRules()

local function number(value, fallback)
    value = tonumber(value)
    return value ~= nil and value or fallback
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, number(value, minimum)))
end

local function optionKey(tag, suffix)
    return "Price" .. tostring(tag):gsub("%.", "") .. suffix
end

local function sandboxRule(tag, rule)
    local result = copyRule(rule)
    local vars = Config and Config.sandboxVars or nil
    local add = vars and vars[optionKey(tag, "Value")] or nil
    local mult = vars and vars[optionKey(tag, "Mult")] or nil
    if add ~= nil then result.add = number(add, result.add or 0) end
    if mult ~= nil then result.mult = math.max(0, number(mult, result.mult or 1)) end
    return result
end

local function categoryAllowed(rule, category)
    if type(rule.categories) ~= "table" or #rule.categories == 0 then return true end
    for _, allowed in ipairs(rule.categories) do
        if tostring(allowed) == tostring(category) then return true end
    end
    return false
end

local function stateScale(details, rule)
    if rule.stateScaled ~= true then return 1 end
    local heuristic = details and details.priceHeuristic or nil
    return clamp(heuristic and heuristic.stateFactor or 1, 0, 1.5)
end

local function applyRule(value, rule, label, details, audit, summary)
    if type(rule) ~= "table" or not categoryAllowed(rule, details and details.category) then
        return value
    end

    local working = value
    local add = number(rule.add, 0) * stateScale(details, rule)
    local mult = math.max(0, number(rule.mult, 1))
    if rule.add ~= nil and add ~= 0 then
        local before = working
        working = working + add
        summary.add = summary.add + add
        addAudit(audit, label .. " add", before, working, {
            configured = number(rule.add, 0),
            stateScale = stateScale(details, rule),
            reason = rule.reason,
        })
    end
    if rule.mult ~= nil and mult ~= 1 then
        local before = working
        working = working * mult
        summary.mult = summary.mult * mult
        addAudit(audit, label .. " mult", before, working, {
            configured = mult,
            reason = rule.reason,
        })
    end
    local minimum = rule.minPrice or rule.min
    if minimum ~= nil then
        local before = working
        working = math.max(working, number(minimum, working))
        addAudit(audit, label .. " min", before, working, { reason = rule.reason })
    end
    return working
end

local function uniqueTags(details)
    local values = {}
    local seen = {}
    local function append(tag)
        tag = tostring(tag or "")
        if tag ~= "" and not seen[tag] then
            seen[tag] = true
            values[#values + 1] = tag
        end
    end
    for _, tag in ipairs(details and details.tags or {}) do append(tag) end
    for _, tag in ipairs(details and details.expandedTags or {}) do append(tag) end
    table.sort(values)
    return values
end

local function categoryAnchor(details)
    local heuristic = details and details.priceHeuristic or {}
    local anchor = number(heuristic.anchor, 0)
    if anchor > 0 then return anchor, "heuristic.anchor" end

    local keyByCategory = {
        Food = "foodPricing", Beverage = "foodPricing", Liquid = "liquidPricing",
        Resource = "resourcePricing", Misc = "miscPricing", Weapon = "weaponPricing",
        Literature = "literaturePricing", Clothing = "clothingPricing",
        Container = "containerPricing", Electronics = "electronicsPricing",
        Medical = "medicalPricing", Building = "buildingPricing", Tool = "toolPricing",
    }
    local config = Config and Config[keyByCategory[details and details.category] or ""] or nil
    anchor = number(config and config.anchor, 0)
    if anchor > 0 then return anchor, "category.anchor" end
    anchor = number(Utils.CATEGORY_BASE_SCORES[details and details.category], 0)
    return anchor, "category.base"
end

local function hashUnit(text)
    local hash = 5381
    text = tostring(text or "")
    for index = 1, #text do
        hash = (hash * 33 + string.byte(text, index)) % 4294967296
    end
    return hash / 4294967296, hash
end

local function seedInfo()
    if WorldGenParams and WorldGenParams.INSTANCE then
        local params = WorldGenParams.INSTANCE
        if type(params.getSeedString) == "function" then
            local seedString = params:getSeedString()
            if seedString ~= nil and tostring(seedString) ~= "" then
                return tostring(seedString), "WorldGenParams.seedString"
            end
        end
        if type(params.getSeed) == "function" then
            local seed = params:getSeed()
            if seed ~= nil then return tostring(seed), "WorldGenParams.seed" end
        end
    end
    return "MarketSense", "fallback"
end

local function applyAnchorSpread(value, details, audit, summary)
    local strength = clamp(Config and Config.pricing and Config.pricing.contrastStrength or 0, 0, 0.50)
    local anchor, anchorSource = categoryAnchor(details)
    if strength <= 0 or anchor <= 0 or value <= 0 then return value end

    local ratio = clamp(value / anchor, 0.25, 4.0)
    local spread = ratio ^ (1 + strength)
    local before = value
    value = value * spread / ratio
    summary.anchor = anchor
    summary.anchorSource = anchorSource
    summary.anchorSpreadMultiplier = spread / ratio
    addAudit(audit, "anchor contrast", before, value, {
        anchor = anchor,
        anchorSource = anchorSource,
        ratio = ratio,
        strength = strength,
        multiplier = spread / ratio,
    })
    return value
end

local function applyVariation(value, ctx, details, audit, summary)
    local pricing = Config and Config.pricing or {}
    local enabled = pricing.variationEnabled ~= false
    local strength = clamp(pricing.variationStrength or 0, 0, 0.50)
    if not enabled or strength <= 0 then
        summary.variationMultiplier = 1
        summary.variationSource = "disabled"
        return value
    end

    local seed, source = seedInfo()
    local salt = tostring(pricing.variationSalt or 1)
    local itemKey = tostring(ctx and ctx.fullType or details and details.fullType or "")
    local unit, seedHash = hashUnit(seed .. "|MarketSensePrice|" .. itemKey .. "|" .. salt)
    local multiplier = 1 + ((unit * 2) - 1) * strength
    local before = value
    value = value * multiplier
    summary.variationMultiplier = multiplier
    summary.variationSource = source
    summary.variationSeedHash = seedHash
    summary.variationStrength = strength
    summary.variationSalt = salt
    summary.variationScope = details and details.yieldResolution
        and details.yieldResolution.status == "resolved" and "aggregate" or "item"
    addAudit(audit, "save-seed variation", before, value, {
        seedSource = source,
        seedHash = seedHash,
        strength = strength,
        salt = salt,
        multiplier = multiplier,
        scope = summary.variationScope,
    })
    return value
end

function Modifiers.apply(ctx, details, value, audit, skipVariation)
    local working = number(value, 0)
    local summary = {
        baseScore = working,
        add = 0,
        mult = 1,
        anchor = nil,
        anchorSource = nil,
        anchorSpreadMultiplier = 1,
        tagAdd = 0,
        tagMultiplier = 1,
        categoryAdd = 0,
        categoryMultiplier = 1,
        moduleAdd = 0,
        moduleMultiplier = 1,
        itemAdd = 0,
        itemMultiplier = 1,
        variationMultiplier = 1,
        applied = {},
        variationScope = "item",
    }

    local itemRule = itemModifiers[ctx and ctx.fullType or ""] or DB.getItem(ctx and ctx.fullType)
    if itemRule and itemRule.price ~= nil then
        summary.absoluteOverride = true
        summary.overrideReason = itemRule.reason or "Exact item price override"
        summary.overridePrice = number(itemRule.price, working)
        details.marketPricing = summary
        addAudit(audit, "absolute item override", working, working, {
            price = itemRule.price,
            reason = summary.overrideReason,
        })
        if skipVariation then
            summary.variationSource = "bundle-child"
            summary.variationScope = "bundle-child"
        elseif Config and Config.pricing
            and Config.pricing.variationAbsoluteOverrides == true then
            summary.overridePrice = applyVariation(summary.overridePrice, ctx, details, audit, summary)
            if summary.variationSource ~= "disabled" then
                summary.variationScope = "absolute-override"
            else
                summary.variationScope = "disabled"
            end
        else
            summary.variationSource = "disabled"
            summary.variationScope = "disabled"
        end
        return working, summary
    end

    working = applyAnchorSpread(working, details, audit, summary)

    local categoryRule = categoryModifiers[details and details.category]
        or DB.getCategory(details and details.category)
    local beforeCategory = working
    working = applyRule(working, categoryRule, "category modifier", details, audit, summary)
    summary.categoryAdd = working - beforeCategory

    for _, tag in ipairs(uniqueTags(details)) do
        local rule = tagModifiers[tag]
        if not rule then
            local dbRule = DB.getTag(tag)
            if dbRule and (dbRule.priceModifier == true or dbRule.add ~= nil or dbRule.mult ~= nil) then
                rule = dbRule
            end
        end
        if rule then
            local configured = sandboxRule(tag, rule)
            local before = working
            working = applyRule(working, configured, "tag modifier:" .. tag, details, audit, summary)
            if working ~= before then
                summary.applied[#summary.applied + 1] = tag
                summary.tagAdd = summary.tagAdd + (working - before)
            end
        end
    end

    local moduleRule = DB.getModule(ctx and ctx.moduleName)
    local beforeModule = working
    working = applyRule(working, moduleRule, "module modifier", details, audit, summary)
    summary.moduleAdd = working - beforeModule

    local registeredItem = itemModifiers[ctx and ctx.fullType or ""]
    if registeredItem then
        local beforeItem = working
        working = applyRule(working, registeredItem, "item modifier:" .. tostring(ctx.fullType), details, audit, summary)
        summary.itemAdd = working - beforeItem
    elseif itemRule then
        local beforeItem = working
        working = applyRule(working, itemRule, "item modifier:" .. tostring(ctx.fullType), details, audit, summary)
        summary.itemAdd = working - beforeItem
    end

    if skipVariation then
        summary.variationSource = "bundle-child"
        summary.variationScope = "bundle-child"
    else
        working = applyVariation(working, ctx, details, audit, summary)
    end
    details.marketPricing = summary
    addAudit(audit, "market modifier summary", summary.baseScore, working, Core.deepCopy(summary))
    return working, summary
end

function Modifiers.getTagModifiers()
    return Core.deepCopy(tagModifiers)
end

return Modifiers
