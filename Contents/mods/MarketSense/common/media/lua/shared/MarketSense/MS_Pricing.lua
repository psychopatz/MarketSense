require "MarketSense/MS_Stock"
require "MarketSense/Pricing/MS_FluidPricing"

MarketSense = MarketSense or {}
MarketSense.Pricing = MarketSense.Pricing or {}

local Pricing  = MarketSense.Pricing
local Core     = MarketSense.Core
local TagUtils = MarketSense.TagUtils
local DB       = MarketSense.HeuristicsDB
local Config   = MarketSense.ItemRuntimeConfig
local FluidPricing = MarketSense.FluidPricing

local CATEGORY_BASE_SCORES = {
    Food = 7, Beverage = 8, Medical = 18, Weapon = 18, Tool = 14,
    Container = 14, Clothing = 4, Electronics = 14, Resource = 7,
    Building = 5, Liquid = 0, Misc = 2,
}

-- Melee is intentionally anchored by mechanical family before any future
-- market-role overlay is applied. These are relative multipliers, not hard
-- coded prices: damage, reach, hit count, durability, weight, and sandbox
-- settings still determine the final result.
local DEFAULT_MELEE_SUBTYPE_MULTIPLIERS = {
    WeaponImprovised = 0.72,
    WeaponCrafted    = 0.72, -- legacy token accepted for existing overrides
    WeaponUnarmed    = 0.35,
    WeaponSmallBlade = 0.86,
    WeaponSmallBlunt = 0.92,
    WeaponBlunt      = 1.00,
    WeaponSpear      = 1.03,
    WeaponAxe        = 1.08,
    WeaponLongBlade  = 1.22,
}

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function configuredMeleeMultiplier(cc, subtype)
    local configured = cc.melee_subtype_multipliers
    local value = type(configured) == "table" and configured[subtype] or nil
    if value == nil then value = DEFAULT_MELEE_SUBTYPE_MULTIPLIERS[subtype] end
    return clamp(tonumber(value) or 1.0, 0.35, 1.50)
end

local function conditionMultiplier(ctx, cc)
    if ctx.hasRuntimeState ~= true or ctx.hasRuntimeCondition ~= true
        or ctx.conditionRatio == nil then
        return 1.0
    end
    local floor = clamp(tonumber(cc.condition_floor) or 0.35, 0.10, 0.80)
    local curve = math.max(0.10, tonumber(cc.condition_curve) or 0.65)
    return clamp(floor + ((1.0 - floor) * (ctx.conditionRatio ^ curve)), floor, 1.0)
end

local function addAudit(audit, label, before, after, extra)
    if not audit then return end
    audit[#audit + 1] = { label = label, before = before, after = after, extra = extra }
end

local function applyAdjustment(value, entry, label, audit)
    if type(entry) ~= "table" then return value end
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
    local cc       = Config.categories and Config.categories[category] or {}
    local base     = cc.base or CATEGORY_BASE_SCORES[category] or CATEGORY_BASE_SCORES.Misc
    local weightPenalty = (ctx.weight or 0) * (cc.weight_penalty or 2.4)
    local score = base

    if category == "Food" then
        if hasTag(details, "Beverage") then
            score = base + ((ctx.thirst or 0) * (cc.thirst_weight or 90)) - weightPenalty
            if hasTag(details, "BeverageAlcohol") then score = score + (cc.alcohol_bonus or 12) end
        else
            local shelfLifeDays = math.max(ctx.daysFresh or 0, ctx.daysRotten or 0)
            local moodPenalty = ((ctx.unhappy or 0) + (ctx.boredom or 0) + ((ctx.stress or 0) * 2))
                                * ((cc.mood_penalty_weight or 40.0) / 100.0)
            score = base
                + ((ctx.hunger  or 0) * (cc.hunger_weight  or 160))
                + ((ctx.thirst  or 0) * (cc.thirst_weight  or 90))
                + ((ctx.calories or 0) * (cc.calorie_weight or 0.025))
                + (shelfLifeDays * (cc.shelf_life_weight or 1.35))
                - moodPenalty - weightPenalty
            if hasTag(details, "FoodNonPerishableCanned") then score = score + (cc.canned_bonus or 24) end
            if hasTag(details, "FoodNonPerishable")       then score = score + (cc.packaged_bonus or 10) end
        end

    elseif category == "Beverage" then
        score = base + ((ctx.thirst or 0) * (cc.thirst_weight or 90)) - weightPenalty
        if hasTag(details, "BeverageAlcohol") then score = score + (cc.alcohol_bonus or 12) end

    elseif category == "Liquid" then
        -- The vessel is deliberately excluded.  Only the primary fluid's
        -- measured volume contributes to the content value.
        score = FluidPricing.calculate(ctx, details)

    elseif category == "Medical" then
        score = base + 12 - weightPenalty
        if hasTag(details, "FirstAid")  then score = score + 16 end
        if hasTag(details, "Bandage")   then score = score + 8  end

    elseif category == "Weapon" then
        local avgDamage = ((ctx.minDamage or 0) + (ctx.maxDamage or 0)) * 0.5
        local mechanicalClass = details.weaponEvidence and details.weaponEvidence.mechanicalClass
            or details.primary or "Weapon"
        local meleeMultiplier = configuredMeleeMultiplier(cc, mechanicalClass)
        local isMelee = DEFAULT_MELEE_SUBTYPE_MULTIPLIERS[mechanicalClass] ~= nil
        score = base
            + (avgDamage * (cc.damage_weight or 28))
            + ((ctx.maxRange  or 0) * (cc.range_weight      or 4))
            + ((ctx.maxHit    or 1) * (cc.multi_hit_weight  or 10))
            + ((ctx.conditionMax or 0) * (cc.durability_weight or 2.2))
            - weightPenalty
        local preStateScore = score
        if isMelee then
            score = score * meleeMultiplier
            if ctx.isTwoHandWeapon == true then
                score = score + (cc.two_handed_bonus or 12)
            end
        end
        if hasTag(details, "Ammo") then
            score = base + ((ctx.conditionMax or 0) * (cc.reliability_weight or 0.6)) + (cc.ammo_base or 10)
        elseif hasTag(details, "Firearm") then
            score = score + (cc.firearm_bonus or 65)
        elseif hasTag(details, "Explosive") then
            score = score + (cc.explosive_bonus or 45)
        elseif hasTag(details, "WeaponPart") then
            score = score + 20
        end

        local stateMult = isMelee and conditionMultiplier(ctx, cc) or 1.0
        local preConditionScore = score
        if isMelee then score = score * stateMult end
        details.priceHeuristic = {
            model = isMelee and "weapon_melee_v1" or "weapon_v1",
            mechanicalClass = mechanicalClass,
            mechanicalFamily = isMelee and "Melee" or "Weapon",
            averageDamage = avgDamage,
            range = ctx.maxRange or 0,
            maxHitCount = ctx.maxHit or 1,
            conditionMax = ctx.conditionMax or 0,
            condition = ctx.condition,
            conditionRatio = ctx.conditionRatio,
            hasRuntimeState = ctx.hasRuntimeState == true,
            hasRuntimeCondition = ctx.hasRuntimeCondition == true,
            subtypeMultiplier = isMelee and meleeMultiplier or 1.0,
            conditionMultiplier = stateMult,
            twoHanded = ctx.isTwoHandWeapon == true,
            preStateScore = preStateScore,
            preConditionScore = preConditionScore,
            score = score,
            unavailableRuntimeMetrics = {
                "swingTime", "criticalChance", "knockdown", "pushback",
            },
        }

    elseif category == "Tool" then
        local durabilityWeight = (ctx.conditionMax or 0) * (ctx.useDelta and ctx.useDelta > 0 and 18 or 8)
        score = base + durabilityWeight - weightPenalty
        if hasTag(details, "ToolCraft")  then score = score + (cc.crafting_bonus or 20) end
        if hasTag(details, "ToolFarming") then score = score + (cc.farming_bonus  or 12) end
        if hasTag(details, "Cooking")    then score = score + 10 end

    elseif category == "Container" then
        score = base
            + ((ctx.capacity      or 0) * (cc.capacity_weight           or 4))
            + ((ctx.weightReduction or 0) * (cc.weight_reduction_weight or 0.65))
            - weightPenalty

    elseif category == "Clothing" then
        local defenseScore = (ctx.biteDefense    or 0) * 4
                           + (ctx.scratchDefense  or 0) * 3
                           + (ctx.bulletDefense   or 0) * 6
        score = base + defenseScore
            + ((ctx.insulation    or 0) * (cc.warmth_weight or 10))
            + ((ctx.windResistance or 0) * (cc.wind_weight   or 8))
            - weightPenalty

    elseif category == "Electronics" then
        score = base - weightPenalty
        if hasTag(details, "ElectronicsGenerator")   then score = score + (cc.generator_bonus or 240) end
        if hasTag(details, "ElectronicsBattery")     then score = score + (cc.battery_bonus   or 10)  end
        if hasTag(details, "ElectronicsRadio")       then score = score + (cc.radio_bonus     or 36)  end
        if hasTag(details, "ElectronicsLight")       then score = score + (cc.light_bonus     or 14)  end
        if hasTag(details, "ElectronicsTelevision")  then score = score + 42                          end

    elseif category == "Resource" then
        score = base - weightPenalty
        if hasTag(details, "ResourceFuel")          then score = score + (cc.fuel_container_bonus or 28) end
        if hasTag(details, "MaterialMetalworking")  then score = score + (cc.metal_family_generic_bonus or 4) end
        if hasTag(details, "MaterialHardware")      then score = score + (cc.hardware_bonus or 2) end
        if hasTag(details, "MaterialWood")          then score = score + 8 end
        if hasTag(details, "MaterialChemical")      then score = score + 18 end

    elseif category == "Building" then
        score = base + ((ctx.capacity or 0) * (cc.storage_capacity_weight or 0.18)) - weightPenalty
        if hasTag(details, "BuildingFurnitureStorage")   then score = score + (cc.storage_bonus   or 10) end
        if hasTag(details, "BuildingFixtureAppliance")   then score = score + (cc.appliance_bonus or 18) end
        if hasTag(details, "BuildingGarden")             then score = score + (cc.garden_bonus    or 4)  end
        if hasTag(details, "BuildingSurvival")           then score = score + (cc.survival_bonus  or 8)  end
        if hasTag(details, "BuildingVehicle")            then score = score + (cc.vehicle_bonus   or 8)  end

    else
        score = base - weightPenalty
    end

    if (details.primary or "") == "Misc" then
        score = math.max(score, CATEGORY_BASE_SCORES.Misc)
    end
    return math.max(score, Config.pricing.minPrice or 1)
end

function Pricing.applyBalances(ctx, details, audit)
    local working = tonumber(details.rawScore or 0) or 0
    addAudit(audit, "raw score", working, working)
    if details.priceHeuristic then
        addAudit(audit, tostring(details.priceHeuristic.model or "content") .. " heuristic",
            details.priceHeuristic.preConditionScore or working, working, {
                model = details.priceHeuristic.model,
                mechanicalClass = details.priceHeuristic.mechanicalClass,
                subtypeMultiplier = details.priceHeuristic.subtypeMultiplier,
                conditionMultiplier = details.priceHeuristic.conditionMultiplier,
                pricePerLiter = details.priceHeuristic.pricePerLiter,
                volume = details.priceHeuristic.volume,
                contentValue = details.priceHeuristic.contentValue,
            })
    end

    local beforeSandbox = working
    local sandboxAdd = Config.pricing.globalValue or 0
    if Config.getSandboxTagMultiplier then
        local tags = { details.primary }
        -- Liquid content has its own per-litre anchor.  Do not inherit
        -- generic item descriptor additions (for example Rarity.Common),
        -- because those additions describe the vessel/item and would turn
        -- Water at $5/L into a different price merely because it is in a
        -- bottle or can.  A future Liquid.* sandbox override can still use
        -- the primary liquid token above.
        if details.category ~= "Liquid" then
            for _, t in ipairs(details.tags or {}) do
                if string.find(t, ".", 1, true) then
                    tags[#tags + 1] = t
                end
            end
        end
        sandboxAdd = sandboxAdd + Config.getSandboxTagMultiplier("Price", tags)
    end
    working = working + sandboxAdd
    addAudit(audit, "sandbox add", beforeSandbox, working, sandboxAdd)

    local beforeGlobal = working
    working = working * (tonumber(Config.pricing.baseMultiplier) or 1)
    addAudit(audit, "global mult", beforeGlobal, working, Config.pricing.baseMultiplier)

    if details.category ~= "Liquid" then
        working = applyAdjustment(working, DB.getCategory(details.category), "category:" .. tostring(details.category), audit)
        for _, tag in ipairs(details.expandedTags or details.tags or {}) do
            working = applyAdjustment(working, DB.getTag(tag), "tag:" .. tag, audit)
        end
    else
        addAudit(audit, "liquid vessel-neutral balance", working, working, {
            fluidType = details.priceHeuristic and details.priceHeuristic.fluidType,
            pricePerLiter = details.priceHeuristic and details.priceHeuristic.pricePerLiter,
            volume = details.priceHeuristic and details.priceHeuristic.volume,
        })
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

function Pricing.calculateDetails(fullTypeOrContext, withAudit, inventoryItem)
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
    local working   = tonumber(staticDetails and staticDetails.price or details.price or details.rawScore) or details.rawScore

    addAudit(audit, "static baseline", working, working)

    local beforeSandbox = working
    local sandboxAdd = Config.pricing.globalValue or 0
    if Config.getSandboxTagMultiplier then
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

    working = working * (tonumber(Config.pricing.baseMultiplier) or 1)
    addAudit(audit, "global mult", beforeSandbox, working)
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
