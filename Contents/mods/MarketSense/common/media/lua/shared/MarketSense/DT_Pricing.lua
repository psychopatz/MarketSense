require "MarketSense/DT_Stock"

DynamicTrading = DynamicTrading or {}
DynamicTrading.Pricing = DynamicTrading.Pricing or {}

local Pricing = DynamicTrading.Pricing
local Core = DynamicTrading.Core
local TagUtils = DynamicTrading.TagUtils
local DB = DynamicTrading.HeuristicsDB
local Config = DynamicTrading.ItemRuntimeConfig

local CATEGORY_BASE_SCORES = {
    Food = 7,
    Medical = 18,
    Weapon = 18,
    Tool = 14,
    Container = 14,
    Clothing = 4,
    Electronics = 14,
    Resource = 7,
    Building = 5,
    Misc = 2,
}

local function addAudit(audit, label, before, after, extra)
    if not audit then
        return
    end
    audit[#audit + 1] = {
        label = label,
        before = before,
        after = after,
        extra = extra,
    }
end

local function applyAdjustment(value, entry, label, audit)
    if type(entry) ~= "table" then
        return value
    end

    local working = value
    if entry.add ~= nil then
        local before = working
        working = working + (tonumber(entry.add) or 0)
        addAudit(audit, label .. " add", before, working)
    end

    if entry.mult ~= nil then
        local before = working
        working = working * math.max(0, tonumber(entry.mult) or 1)
        addAudit(audit, label .. " mult", before, working)
    end

    local minPrice = entry.minPrice or entry.min
    if minPrice ~= nil then
        local before = working
        working = math.max(working, tonumber(minPrice) or working)
        addAudit(audit, label .. " min", before, working)
    end

    return working
end

local function hasTag(details, tag)
    return TagUtils.hasTag(details.expandedTags or details.tags or {}, tag)
end

local function clampAndRound(value)
    return Core.round(Core.priceClamp(value))
end

function Pricing.calculateRawScore(ctx, details)
    local category = details.category or "Misc"
    local primary = details.primary or "Misc.General"
    local base = CATEGORY_BASE_SCORES[category] or CATEGORY_BASE_SCORES.Misc
    local weightPenalty = (ctx.weight or 0) * 2.4
    local score = base

    if category == "Food" then
        local shelfLifeDays = math.max(ctx.daysFresh or 0, ctx.daysRotten or 0)
        local moodPenalty = (ctx.unhappy or 0) + (ctx.boredom or 0) + ((ctx.stress or 0) * 2)
        score = base
            + ((ctx.hunger or 0) * 160)
            + ((ctx.thirst or 0) * 90)
            + ((ctx.calories or 0) * 0.025)
            + (shelfLifeDays * 1.35)
            - moodPenalty
            - (ctx.weight * 6)

        if hasTag(details, "Food.NonPerishable.Canned") then score = score + 24 end
        if hasTag(details, "Food.NonPerishable.General") then score = score + 12 end
        if hasTag(details, "Food.Drink") then score = score + 8 end
        if hasTag(details, "Food.Drink.Alcohol") then score = score + 18 end
        if hasTag(details, "Food.HighNutrition") then score = score * 1.15 end
    elseif category == "Medical" then
        score = base + 12 - (ctx.weight * 4)
        if hasTag(details, "Medical.General.Pills") then score = score + 18 end
        if hasTag(details, "Medical.General.Vitamin") then score = score + 10 end
        if hasTag(details, "Medical.Healthcare") then score = score + 16 end
        if hasTag(details, "Medical.Consumable") then score = score + 8 end
        if hasTag(details, "Tool.Medical.Surgical") then score = score + 24 end
        if hasTag(details, "Medical.General.Drug") then score = score * 0.92 end
    elseif category == "Weapon" then
        local avgDamage = ((ctx.minDamage or 0) + (ctx.maxDamage or 0)) * 0.5
        score = base
            + (avgDamage * 28)
            + ((ctx.maxRange or 0) * 4)
            + ((ctx.maxHit or 1) * 10)
            + ((ctx.conditionMax or 0) * 2.2)
            - (ctx.weight * 3)

        if hasTag(details, "Weapon.Ranged.Ammo") then
            score = base + ((ctx.conditionMax or 0) * 0.75) + 6
        elseif hasTag(details, "Weapon.Ranged.Firearm") then
            score = score + 65
        elseif hasTag(details, "Weapon.Explosive") then
            score = score + 90
        elseif hasTag(details, "Weapon.Part.Accessory") then
            score = score + 20
        end
    elseif category == "Tool" then
        local durabilityWeight = (ctx.conditionMax or 0) * (ctx.useDelta and ctx.useDelta > 0 and 18 or 8)
        score = base + durabilityWeight - weightPenalty

        if hasTag(details, "Tool.Crafting") then score = score + 18 end
        if hasTag(details, "Tool.Farming") then score = score + 16 end
        if hasTag(details, "Tool.Fishing") then score = score + 14 end
        if hasTag(details, "Tool.Medical") then score = score + 12 end
        if hasTag(details, "Tool.Cookware") then score = score + 10 end
        if hasTag(details, "Tool.Utility") then score = score + 8 end
    elseif category == "Container" then
        score = base
            + ((ctx.capacity or 0) * 4)
            + ((ctx.weightReduction or 0) * 0.65)
            - (ctx.weight * 1.8)
    elseif category == "Clothing" then
        local defenseScore = (ctx.biteDefense or 0) * 4 + (ctx.scratchDefense or 0) * 3 + (ctx.bulletDefense or 0) * 6
        score = base
            + defenseScore
            + ((ctx.insulation or 0) * 10)
            + ((ctx.windResistance or 0) * 8)
            - (ctx.weight * 1.5)
    elseif category == "Electronics" then
        score = base - weightPenalty
        if hasTag(details, "Electronics.Generator") then score = score + 180 end
        if hasTag(details, "Electronics.Battery") then score = score + 22 end
        if hasTag(details, "Electronics.Radio") then score = score + 38 end
        if hasTag(details, "Electronics.Light") then score = score + 16 end
        if hasTag(details, "Electronics.Television") then score = score + 42 end
    elseif category == "Resource" then
        score = base - (ctx.weight * 1.2)
        if hasTag(details, "Resource.Fuel") then score = score + 28 end
        if hasTag(details, "Resource.Material.Metal") then score = score + 14 end
        if hasTag(details, "Resource.Material.Hardware") then score = score + 12 end
        if hasTag(details, "Resource.Material.Wood") then score = score + 8 end
        if hasTag(details, "Resource.Material.Chemical") then score = score + 18 end
    elseif category == "Building" then
        score = base + ((ctx.capacity or 0) * 1.5) - (ctx.weight * 1.3)
        if hasTag(details, "Building.Furniture.Storage") then score = score + 24 end
        if hasTag(details, "Building.Fixture.Appliance") then score = score + 18 end
        if hasTag(details, "Building.Garden") then score = score + 12 end
        if hasTag(details, "Building.Survival") then score = score + 16 end
        if hasTag(details, "Building.Vehicle") then score = score + 20 end
    else
        score = base + math.max(0, (ctx.weight or 0) * 0.2)
    end

    if hasTag(details, "Rarity.Uncommon") then score = score * 1.10 end
    if hasTag(details, "Rarity.Rare") then score = score * 1.30 end
    if hasTag(details, "Rarity.Legendary") then score = score * 1.75 end
    if hasTag(details, "Quality.Waste") then score = score * 0.30 end
    if hasTag(details, "Quality.Luxury") then score = score * 1.35 end
    if hasTag(details, "Origin.Modded") then score = score * 1.00 end

    if primary == "Misc.General" then
        score = math.max(score, CATEGORY_BASE_SCORES.Misc)
    end

    return math.max(score, Config.pricing.minPrice)
end

function Pricing.applyBalances(ctx, details, audit)
    local working = tonumber(details.rawScore or 0) or 0
    addAudit(audit, "raw score", working, working)

    local beforeGlobal = working
    working = working * (tonumber(Config.pricing.baseMultiplier) or 1)
    addAudit(audit, "global mult", beforeGlobal, working, Config.pricing.baseMultiplier)

    working = applyAdjustment(working, DB.getCategory(details.category), "category:" .. tostring(details.category), audit)

    for _, tag in ipairs(details.expandedTags or details.tags or {}) do
        working = applyAdjustment(working, DB.getTag(tag), "tag:" .. tag, audit)
    end

    working = applyAdjustment(working, DB.getModule(ctx.moduleName), "module:" .. tostring(ctx.moduleName), audit)

    local itemEntry = DB.getItem(ctx.fullType)
    working = applyAdjustment(working, itemEntry, "item:" .. tostring(ctx.fullType), audit)

    if itemEntry and itemEntry.price ~= nil then
        local finalPrice = clampAndRound(itemEntry.price)
        addAudit(audit, "item final price", working, finalPrice)
        return finalPrice
    end

    local finalPrice = clampAndRound(working)
    addAudit(audit, "clamp+round", working, finalPrice)
    return finalPrice
end

local function applyTagOverrideIfPresent(ctx, details)
    local itemEntry = DB.getItem(ctx.fullType)
    if itemEntry and type(itemEntry.tags) == "table" and #itemEntry.tags > 0 then
        details.tags = TagUtils.unique(itemEntry.tags)
        details.primary = details.tags[1] or details.primary
        details.category = TagUtils.categoryFromPrimary(details.primary)
        details.expandedTags = TagUtils.expandHierarchy(details.tags)
    end
    return itemEntry
end

function Pricing.calculateDetails(fullTypeOrContext, withAudit)
    local ctx = type(fullTypeOrContext) == "table" and fullTypeOrContext.fullType
        and fullTypeOrContext or DynamicTrading.PropertyReader.buildContext(fullTypeOrContext)
    local tagInfo = DynamicTrading.AutoTag.generate(ctx)

    local details = {
        fullType = ctx.fullType,
        moduleName = ctx.moduleName,
        typeName = ctx.typeName,
        sourceModId = ctx.sourceModId,
        sourceModName = ctx.sourceModName,
        category = tagInfo.category,
        primary = tagInfo.primary,
        tags = Core.deepCopy(tagInfo.tags),
        expandedTags = Core.deepCopy(tagInfo.expandedTags),
        confidence = tagInfo.confidence,
        rawScore = 0,
        price = 0,
        stock = nil,
        source = "lazy",
    }

    local audit = withAudit and {} or nil
    applyTagOverrideIfPresent(ctx, details)
    details.rawScore = Pricing.calculateRawScore(ctx, details)
    details.price = Pricing.applyBalances(ctx, details, audit)
    details.stock = DynamicTrading.Stock.calculate(ctx.fullType, ctx, details)

    if audit then
        details.balanceAudit = audit
    end

    return details
end

function Pricing.applyOverridesOnly(fullTypeOrContext, staticDetails, withAudit)
    local ctx = type(fullTypeOrContext) == "table" and fullTypeOrContext.fullType
        and fullTypeOrContext or DynamicTrading.PropertyReader.buildContext(fullTypeOrContext)
    local details = Core.deepCopy(staticDetails or {})
    local audit = withAudit and {} or nil

    details.fullType = details.fullType or ctx.fullType
    details.moduleName = details.moduleName or ctx.moduleName
    details.typeName = details.typeName or ctx.typeName
    details.sourceModId = details.sourceModId or ctx.sourceModId
    details.sourceModName = details.sourceModName or ctx.sourceModName
    details.category = details.category or "Misc"
    details.primary = details.primary or "Misc.General"
    details.tags = TagUtils.unique(details.tags or { details.primary })
    details.expandedTags = TagUtils.expandHierarchy(details.tags)
    details.rawScore = tonumber(details.rawScore) or tonumber(details.price) or Config.pricing.minPrice

    local itemEntry = applyTagOverrideIfPresent(ctx, details)
    local working = tonumber(staticDetails and staticDetails.price or details.price or details.rawScore) or details.rawScore

    addAudit(audit, "static baseline", working, working)

    local beforeGlobal = working
    working = working * (tonumber(Config.pricing.baseMultiplier) or 1)
    addAudit(audit, "global mult", beforeGlobal, working)

    working = applyAdjustment(working, DB.getCategory(details.category), "category:" .. tostring(details.category), audit)

    for _, tag in ipairs(details.expandedTags or {}) do
        working = applyAdjustment(working, DB.getTag(tag), "tag:" .. tag, audit)
    end

    working = applyAdjustment(working, DB.getModule(ctx.moduleName), "module:" .. tostring(ctx.moduleName), audit)
    working = applyAdjustment(working, itemEntry, "item:" .. tostring(ctx.fullType), audit)

    if itemEntry and itemEntry.price ~= nil then
        details.price = clampAndRound(itemEntry.price)
        addAudit(audit, "item final price", working, details.price)
        details.source = "override"
    else
        details.price = clampAndRound(working)
        details.source = "static"
    end

    details.stock = DynamicTrading.Stock.calculate(ctx.fullType, ctx, details)

    if itemEntry and (itemEntry.tags or itemEntry.stock or itemEntry.add or itemEntry.mult or itemEntry.price ~= nil) then
        details.source = "override"
    end

    if audit then
        details.balanceAudit = audit
    end

    return details
end

function Pricing.generateDetailsOnce(fullTypeOrContext, withAudit)
    local details = Pricing.calculateDetails(fullTypeOrContext, withAudit)
    local ctx = type(fullTypeOrContext) == "table" and fullTypeOrContext.fullType
        and fullTypeOrContext or DynamicTrading.PropertyReader.buildContext(fullTypeOrContext)
    local itemEntry = DB.getItem(ctx.fullType)
    if itemEntry and (itemEntry.tags or itemEntry.stock or itemEntry.add or itemEntry.mult or itemEntry.price ~= nil) then
        details.source = "override"
    else
        details.source = "lazy"
    end
    return details
end

return Pricing
