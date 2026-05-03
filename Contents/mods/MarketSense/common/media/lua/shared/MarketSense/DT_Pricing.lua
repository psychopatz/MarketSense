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
    local cc = Config.categories and Config.categories[category] or {}
    local base = cc.base or CATEGORY_BASE_SCORES[category] or CATEGORY_BASE_SCORES.Misc
    local weightPenalty = (ctx.weight or 0) * (cc.weight_penalty or 2.4)
    local score = base

    if category == "Food" then
        local shelfLifeDays = math.max(ctx.daysFresh or 0, ctx.daysRotten or 0)
        local moodWeight = cc.mood_penalty_weight or 40.0
        local moodPenalty = ((ctx.unhappy or 0) + (ctx.boredom or 0) + ((ctx.stress or 0) * 2)) * (moodWeight / 100.0)
        score = base
            + ((ctx.hunger or 0) * (cc.hunger_weight or 160))
            + ((ctx.thirst or 0) * (cc.thirst_weight or 90))
            + ((ctx.calories or 0) * (cc.calorie_weight or 0.025))
            + (shelfLifeDays * (cc.shelf_life_weight or 1.35))
            - moodPenalty
            - weightPenalty

        if hasTag(details, "Food.NonPerishable.Canned") then score = score + (cc.canned_bonus or 24) end
        if hasTag(details, "Food.NonPerishable.General") then score = score + (cc.packaged_bonus or 10) end
        if hasTag(details, "Food.Drink") then score = score + (cc.drink_bonus or 8) end
        if hasTag(details, "Food.Drink.Alcohol") then score = score + (cc.alcohol_bonus or 12) end
        if hasTag(details, "Food.HighNutrition") then score = score * (cc.spice_multiplier or 1.15) end

    elseif category == "Medical" then
        score = base + 12 - weightPenalty
        if hasTag(details, "Medical.General.Pills") then score = score + (cc.painkiller_bonus or 18) end
        if hasTag(details, "Medical.General.Vitamin") then score = score + (cc.vitamin_bonus or 10) end
        if hasTag(details, "Medical.Healthcare") then score = score + 16 end
        if hasTag(details, "Medical.Consumable") then score = score + 8 end
        if hasTag(details, "Tool.Medical.Surgical") then score = score + (cc.surgical_bonus or 34) end
        if hasTag(details, "Medical.General.Drug") then score = score * 0.92 end

    elseif category == "Weapon" then
        local avgDamage = ((ctx.minDamage or 0) + (ctx.maxDamage or 0)) * 0.5
        score = base
            + (avgDamage * (cc.damage_weight or 28))
            + ((ctx.maxRange or 0) * (cc.range_weight or 4))
            + ((ctx.maxHit or 1) * (cc.multi_hit_weight or 10))
            + ((ctx.conditionMax or 0) * (cc.durability_weight or 2.2))
            - weightPenalty

        if hasTag(details, "Weapon.Ranged.Ammo") then
            score = base + ((ctx.conditionMax or 0) * (cc.reliability_weight or 0.6)) + (cc.ammo_base or 10)
        elseif hasTag(details, "Weapon.Ranged.Firearm") then
            score = score + (cc.firearm_bonus or 65)
        elseif hasTag(details, "Weapon.Explosive") then
            score = score + (cc.explosive_bonus or 45)
        elseif hasTag(details, "Weapon.Part.Accessory") then
            score = score + 20
        end

    elseif category == "Tool" then
        local durabilityWeight = (ctx.conditionMax or 0) * (ctx.useDelta and ctx.useDelta > 0 and 18 or 8)
        score = base + durabilityWeight - weightPenalty

        if hasTag(details, "Tool.Crafting") then score = score + (cc.crafting_bonus or 20) end
        if hasTag(details, "Tool.Farming") then score = score + (cc.farming_bonus or 12) end
        if hasTag(details, "Tool.Fishing") then score = score + (cc.fishing_bonus or 12) end
        if hasTag(details, "Tool.Medical") then score = score + (cc.medical_bonus or 12) end
        if hasTag(details, "Tool.Cookware") then score = score + 10 end
        if hasTag(details, "Tool.Utility") then score = score + 8 end

    elseif category == "Container" then
        score = base
            + ((ctx.capacity or 0) * (cc.capacity_weight or 4))
            + ((ctx.weightReduction or 0) * (cc.weight_reduction_weight or 0.65))
            - weightPenalty

    elseif category == "Clothing" then
        local defenseScore = (ctx.biteDefense or 0) * 4 + (ctx.scratchDefense or 0) * 3 + (ctx.bulletDefense or 0) * 6
        score = base
            + defenseScore
            + ((ctx.insulation or 0) * (cc.warmth_weight or 10))
            + ((ctx.windResistance or 0) * (cc.wind_weight or 8))
            - weightPenalty

    elseif category == "Electronics" then
        score = base - weightPenalty
        if hasTag(details, "Electronics.Generator") then score = score + (cc.generator_bonus or 240) end
        if hasTag(details, "Electronics.Battery") then score = score + (cc.battery_bonus or 10) end
        if hasTag(details, "Electronics.Radio") then score = score + (cc.radio_bonus or 36) end
        if hasTag(details, "Electronics.Light") then score = score + (cc.light_bonus or 14) end
        if hasTag(details, "Electronics.Television") then score = score + 42 end

    elseif category == "Resource" then
        score = base - weightPenalty
        if hasTag(details, "Resource.Fuel") then score = score + (cc.fuel_container_bonus or 28) end
        if hasTag(details, "Resource.Material.Metal") then score = score + (cc.metal_family_generic_bonus or 4) end
        if hasTag(details, "Resource.Material.Hardware") then score = score + (cc.hardware_bonus or 2) end
        if hasTag(details, "Resource.Material.Wood") then score = score + 8 end
        if hasTag(details, "Resource.Material.Chemical") then score = score + 18 end

    elseif category == "Building" then
        score = base + ((ctx.capacity or 0) * (cc.storage_capacity_weight or 0.18)) - weightPenalty
        if hasTag(details, "Building.Furniture.Storage") then score = score + (cc.storage_bonus or 10) end
        if hasTag(details, "Building.Fixture.Appliance") then score = score + (cc.appliance_bonus or 18) end
        if hasTag(details, "Building.Garden") then score = score + (cc.garden_bonus or 4) end
        if hasTag(details, "Building.Survival") then score = score + (cc.survival_bonus or 8) end
        if hasTag(details, "Building.Vehicle") then score = score + (cc.vehicle_bonus or 8) end

    else
        score = base - weightPenalty
    end

    if hasTag(details, "Rarity.Uncommon") then score = score * (Config.rarityMultipliers and Config.rarityMultipliers.Uncommon or 1.18) end
    if hasTag(details, "Rarity.Rare") then score = score * (Config.rarityMultipliers and Config.rarityMultipliers.Rare or 1.45) end
    if hasTag(details, "Rarity.Legendary") then score = score * (Config.rarityMultipliers and Config.rarityMultipliers.Legendary or 2.10) end
    if hasTag(details, "Quality.Waste") then score = score * (Config.qualityMultipliers and Config.qualityMultipliers.Waste or 0.30) end
    if hasTag(details, "Quality.Luxury") then score = score * (Config.qualityMultipliers and Config.qualityMultipliers.Luxury or 1.60) end
    if hasTag(details, "Origin.Modded") then score = score * 1.00 end

    if primary == "Misc.General" then
        score = math.max(score, CATEGORY_BASE_SCORES.Misc)
    end

    return math.max(score, Config.pricing.minPrice or 1)
end

function Pricing.applyBalances(ctx, details, audit)
    local working = tonumber(details.rawScore or 0) or 0
    addAudit(audit, "raw score", working, working)

    local beforeGlobal = working
    working = working * (tonumber(Config.pricing.baseMultiplier) or 1)
    addAudit(audit, "global mult", beforeGlobal, working, Config.pricing.baseMultiplier)
    
    if Config.getSandboxTagMultiplier then
        local beforeSandbox = working
        local tagMult = Config.getSandboxTagMultiplier("Price", details.primary)
        working = working * tagMult
        addAudit(audit, "sandbox mult", beforeSandbox, working, tagMult)
    end

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

    if Config.getSandboxTagMultiplier then
        local beforeSandbox = working
        local tagMult = Config.getSandboxTagMultiplier("Price", details.primary)
        working = working * tagMult
        addAudit(audit, "sandbox mult", beforeSandbox, working, tagMult)
    end

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
