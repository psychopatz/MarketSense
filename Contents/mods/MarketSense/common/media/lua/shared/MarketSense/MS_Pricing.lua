require "MarketSense/MS_Stock"
require "MarketSense/Pricing/MS_LiquidPricing"
require "MarketSense/Pricing/MS_FoodPricing"
require "MarketSense/Pricing/MS_YieldResolver"
require "MarketSense/Pricing/MS_ContainerPricing"
require "MarketSense/Pricing/MS_ElectronicsPricing"
require "MarketSense/Pricing/MS_MedicalPricing"
require "MarketSense/Pricing/MS_BuildingPricing"
require "MarketSense/Pricing/MS_ToolRecipeDemand"
require "MarketSense/Pricing/MS_ToolPricing"

MarketSense = MarketSense or {}
MarketSense.Pricing = MarketSense.Pricing or {}

local Pricing  = MarketSense.Pricing
local Core     = MarketSense.Core
local TagUtils = MarketSense.TagUtils
local DB       = MarketSense.HeuristicsDB
local Config   = MarketSense.ItemRuntimeConfig
local LiquidPricing = MarketSense.LiquidPricing
local FoodPricing = MarketSense.FoodPricing
local YieldResolver = MarketSense.YieldResolver
local ContainerPricing = MarketSense.ContainerPricing
local ElectronicsPricing = MarketSense.ElectronicsPricing
local MedicalPricing = MarketSense.MedicalPricing
local BuildingPricing = MarketSense.BuildingPricing
local ToolPricing = MarketSense.ToolPricing

local CATEGORY_BASE_SCORES = {
    Medical = 18, Weapon = 18, Tool = 14,
    Container = 14, Clothing = 4, Electronics = 14, Resource = 7,
    Building = 5, Liquid = 5, Literature = 5, Misc = 2,
}

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

local function isFoodCategory(category)
    return category == "Food" or category == "Beverage"
end

local function isLiteratureCategory(category)
    return category == "Literature"
end

local function isClothingCategory(category)
    return category == "Clothing"
end

local function isContainerCategory(category)
    return category == "Container"
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

    if isFoodCategory(category) then
        score = FoodPricing.calculate(ctx, details)

    elseif category == "Liquid" then
        -- Retain the complete fluid evidence surface while the new utility
        -- anchors are calibrated.  Vessel capacity is not liquid value.
        details.priceHeuristic = LiquidPricing.buildPendingHeuristic(ctx, details)
        score = base

    elseif category == "Medical" then
        -- The old medical score stacked a generic weight penalty with flat
        -- FirstAid/Bandage dollars. Keep medical evidence visible while the
        -- treatment-effect model is calibrated.
        details.priceHeuristic = MedicalPricing.buildPendingHeuristic(ctx, details)
        score = base

    elseif category == "Building" then
        -- Building contains heterogeneous placeables, fixtures, survival
        -- objects, and world-capability items. Keep their evidence visible
        -- while those functions are calibrated into comparable anchors.
        details.priceHeuristic = BuildingPricing.buildPendingHeuristic(ctx, details)
        score = base

    elseif category == "Weapon" then
        -- Some native weapons are also reusable crafting tools (for example,
        -- Base.Hammer). Keep the weapon root/category, but bridge verified
        -- reusable recipe utility into the pending weapon score so those
        -- items are not priced like combat-only or unused weapons.
        local weaponEvidence = details.weaponEvidence or {}
        local recipeDemand, recipeContribution = ToolPricing.recipeEvidence(ctx)
        details.priceHeuristic = {
            model = "weapon_v2_pending",
            status = "pending",
            reason = "Weapon scoring is pending; verified reusable tool recipes are bridged.",
            mechanicalClass = weaponEvidence.mechanicalClass or details.primary or "Weapon",
            mechanicalFamily = weaponEvidence.mechanicalFamily,
            marketRole = weaponEvidence.marketRole,
            nativeCategories = weaponEvidence.nativeCategories,
            conditionMax = ctx.conditionMax,
            condition = ctx.condition,
            conditionRatio = ctx.conditionRatio,
            hasRuntimeState = ctx.hasRuntimeState == true,
            hasRuntimeCondition = ctx.hasRuntimeCondition == true,
            twoHanded = ctx.isTwoHandWeapon == true,
            recipeDemand = recipeDemand,
            recipeDemandScore = recipeDemand.recipeDemandScore,
            recipeCriticality = recipeDemand.criticality,
            recipeContribution = recipeContribution,
            staticMetricsAvailable = {
                minDamage = ctx.minDamage ~= nil,
                maxDamage = ctx.maxDamage ~= nil,
                maxRange = ctx.maxRange ~= nil,
                maxHitCount = ctx.maxHit ~= nil,
                conditionMax = ctx.conditionMax ~= nil,
                weight = ctx.weight ~= nil,
                twoHandWeapon = ctx.isTwoHandWeapon ~= nil,
                recipeDemand = recipeDemand.status == "resolved",
            },
            plannedPositiveAnchors = {
                "effective damage throughput",
                "reach and target coverage",
                "reliability and durability",
                "ammunition compatibility or yield",
                "reusable crafting and repair recipe demand for tool hybrids",
            },
            plannedNegativeAnchors = {
                "weight relative to performance",
                "condition and broken state",
                "hand occupancy and handling cost",
                "scarcity or compatibility gaps",
            },
        }
        score = base + recipeContribution

    elseif category == "Literature" then
        -- The old literature score was a collection of flat root/subtype
        -- additions. It is intentionally retired until the value of
        -- knowledge, information, entertainment, and physical format can be
        -- normalized into one evidence-based model.
        local literatureDetails = type(details.classificationDetails) == "table"
            and details.classificationDetails or {}
        local learnedRecipes = type(ctx.learnedRecipes) == "table"
            and ctx.learnedRecipes or {}
        details.priceHeuristic = {
            model = "literature_v2_pending",
            status = "pending",
            reason = "Legacy literature scoring removed; awaiting calibrated usefulness anchors.",
            subtype = details.primary or "Literature",
            classifierSource = literatureDetails.source,
            skill = ctx.skillTrained,
            skillLevel = ctx.lvlSkillTrained,
            maxLevelTrained = ctx.maxLevelTrained,
            learnedRecipeCount = #learnedRecipes,
            readType = ctx.readType,
            canBeWrite = ctx.canBeWrite == true,
            isLiteratureInstance = ctx.isLiteratureInstance == true,
            staticMetricsAvailable = {
                skill = ctx.skillTrained ~= nil and ctx.skillTrained ~= "",
                skillLevel = (tonumber(ctx.lvlSkillTrained) or -1) >= 0,
                maxLevelTrained = (tonumber(ctx.maxLevelTrained) or -1) >= 0,
                learnedRecipes = ctx.learnedRecipes ~= nil,
                readType = ctx.readType ~= nil and ctx.readType ~= "",
                entertainmentEffects = ctx.boredomChange ~= nil
                    or ctx.unhappyChange ~= nil or ctx.stressChange ~= nil,
                writing = ctx.canBeWrite ~= nil,
                weight = ctx.weight ~= nil,
            },
            plannedPositiveAnchors = {
                "skill progression and level span",
                "recipe unlock count and utility",
                "map or information utility",
                "boredom, stress, and unhappiness relief",
                "readable or writable utility",
            },
            plannedNegativeAnchors = {
                "already-read or already-known state",
                "empty, consumed, or unusable content",
                "reading time and physical weight",
                "generic or explicitly uninteresting content",
                "format cost without additional utility",
            },
        }
        score = base

    elseif category == "Tool" then
        score = ToolPricing.calculate(ctx, details)

    elseif isContainerCategory(category) then
        details.priceHeuristic = ContainerPricing.buildPendingHeuristic(ctx, details)
        score = base

    elseif isClothingCategory(category) then
        -- The old clothing score stacked raw defense, warmth, wind, and a
        -- flat weight penalty.  It is intentionally retired until those
        -- signals are normalized by clothing family, coverage, and state.
        details.priceHeuristic = {
            model = "clothing_v2_pending",
            status = "pending",
            reason = "Legacy clothing scoring removed; awaiting calibrated clothing anchors.",
            subtype = details.primary or "Clothing",
            bodyLocation = ctx.bodyLocation,
            bodyLocationToken = ctx.bodyLocationToken,
            biteDefense = ctx.biteDefense,
            scratchDefense = ctx.scratchDefense,
            bulletDefense = ctx.bulletDefense,
            insulation = ctx.insulation,
            windResistance = ctx.windResistance,
            waterResistance = ctx.waterResistance,
            temperature = ctx.temperature,
            runSpeedModifier = ctx.runSpeedModifier,
            combatSpeedModifier = ctx.combatSpeedModifier,
            neckProtectionModifier = ctx.neckProtectionModifier,
            conditionMax = ctx.conditionMax,
            condition = ctx.condition,
            conditionRatio = ctx.conditionRatio,
            weight = ctx.weight,
            staticMetricsAvailable = {
                bodyLocation = ctx.bodyLocation ~= nil and ctx.bodyLocation ~= "",
                biteDefense = ctx.biteDefense ~= nil,
                scratchDefense = ctx.scratchDefense ~= nil,
                bulletDefense = ctx.bulletDefense ~= nil,
                insulation = ctx.insulation ~= nil,
                windResistance = ctx.windResistance ~= nil,
                waterResistance = ctx.waterResistance ~= nil,
                temperature = ctx.temperature ~= nil,
                runSpeedModifier = ctx.runSpeedModifier ~= nil,
                combatSpeedModifier = ctx.combatSpeedModifier ~= nil,
                neckProtectionModifier = ctx.neckProtectionModifier ~= nil,
                conditionMax = ctx.conditionMax ~= nil,
                weight = ctx.weight ~= nil,
            },
            plannedPositiveAnchors = {
                "effective bite, scratch, and bullet protection",
                "body-slot coverage and protection relevance",
                "insulation, wind, water, and temperature utility",
                "mobility or combat-speed benefit",
                "durability and repairability",
                "functional or verified accessory utility",
            },
            plannedNegativeAnchors = {
                "weight relative to delivered protection or utility",
                "run-speed, combat-speed, or fall-risk penalties",
                "holes, broken condition, and worn state",
                "blood, dirtiness, and wetness maintenance state",
                "neck-protection reduction or uncovered critical areas",
                "cosmetic or rarity labels without mechanical utility",
            },
        }
        score = base

    elseif category == "Electronics" then
        -- The old electronics score stacked a weight penalty with flat
        -- generator, battery, radio, light, and television dollars.  Keep
        -- the evidence visible while the functional model is calibrated.
        details.priceHeuristic = ElectronicsPricing.buildPendingHeuristic(ctx, details)
        score = base

    elseif category == "Resource" then
        score = base - weightPenalty
        if hasTag(details, "ResourceFuel")          then score = score + (cc.fuel_container_bonus or 28) end
        if hasTag(details, "MaterialMetalworking")  then score = score + (cc.metal_family_generic_bonus or 4) end
        if hasTag(details, "MaterialHardware")      then score = score + (cc.hardware_bonus or 2) end
        if hasTag(details, "MaterialWood")          then score = score + 8 end
        if hasTag(details, "MaterialChemical")      then score = score + 18 end

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
    if details.yieldResolution then
        addAudit(audit, "yield resolution", working, working,
            details.yieldResolution)
    end
    if details.priceHeuristic then
        addAudit(audit, tostring(details.priceHeuristic.model or "content") .. " heuristic",
            working, working, {
                model = details.priceHeuristic.model,
                status = details.priceHeuristic.status,
                mechanicalClass = details.priceHeuristic.mechanicalClass,
                role = details.priceHeuristic.role,
                subtype = details.priceHeuristic.subtype,
                learnedRecipeCount = details.priceHeuristic.learnedRecipeCount,
                skillLevel = details.priceHeuristic.skillLevel,
                readType = details.priceHeuristic.readType,
                fluidType = details.priceHeuristic.fluidType,
                fluidTypeString = details.priceHeuristic.fluidTypeString,
                fluidCategory = details.priceHeuristic.fluidCategory,
                fluidCategories = details.priceHeuristic.fluidCategories,
                fluidAmount = details.priceHeuristic.fluidAmount,
                fluidCapacity = details.priceHeuristic.fluidCapacity,
                fluidPrimaryAmount = details.priceHeuristic.fluidPrimaryAmount,
                fluidFilledRatio = details.priceHeuristic.fluidFilledRatio,
                fluidIsEmpty = details.priceHeuristic.fluidIsEmpty,
                fluidIsMixture = details.priceHeuristic.fluidIsMixture,
                yieldStatus = details.priceHeuristic.yieldStatus,
                yieldRecipe = details.priceHeuristic.yieldRecipe,
                yieldOutputCount = details.priceHeuristic.yieldOutputCount,
                yieldOutputQuantity = details.priceHeuristic.yieldOutputQuantity,
                yieldOutputs = details.priceHeuristic.yieldOutputs,
                bodyLocation = details.priceHeuristic.bodyLocation,
                bodyLocationToken = details.priceHeuristic.bodyLocationToken,
                biteDefense = details.priceHeuristic.biteDefense,
                scratchDefense = details.priceHeuristic.scratchDefense,
                bulletDefense = details.priceHeuristic.bulletDefense,
                insulation = details.priceHeuristic.insulation,
                windResistance = details.priceHeuristic.windResistance,
                conditionRatio = details.priceHeuristic.conditionRatio,
                runSpeedModifier = details.priceHeuristic.runSpeedModifier,
                combatSpeedModifier = details.priceHeuristic.combatSpeedModifier,
                capacity = details.priceHeuristic.capacity,
                weightReduction = details.priceHeuristic.weightReduction,
                contentYieldStatus = details.priceHeuristic.contentYieldStatus,
                contentYieldOutputCount = details.priceHeuristic.contentYieldOutputCount,
                conditionLowerChance = details.priceHeuristic.conditionLowerChance,
                useDelta = details.priceHeuristic.useDelta,
                maxUses = details.priceHeuristic.maxUses,
                remainingUsesRatio = details.priceHeuristic.remainingUsesRatio,
                weightEmpty = details.priceHeuristic.weightEmpty,
                mechanicType = details.priceHeuristic.mechanicType,
                classifierSource = details.priceHeuristic.classifierSource,
                classifierTag = details.priceHeuristic.classifierTag,
                displayCategory = details.priceHeuristic.displayCategory,
                itemType = details.priceHeuristic.itemType,
                lightStrength = details.priceHeuristic.lightStrength,
                lightDistance = details.priceHeuristic.lightDistance,
                lightCanEmit = details.priceHeuristic.lightCanEmit,
                lightUseBattery = details.priceHeuristic.lightUseBattery,
                lightHasBattery = details.priceHeuristic.lightHasBattery,
                deviceDataAvailable = details.priceHeuristic.deviceDataAvailable,
                deviceIsBatteryPowered = details.priceHeuristic.deviceIsBatteryPowered,
                deviceHasBattery = details.priceHeuristic.deviceHasBattery,
                deviceIsTelevision = details.priceHeuristic.deviceIsTelevision,
                deviceIsTwoWay = details.priceHeuristic.deviceIsTwoWay,
                deviceIsPortable = details.priceHeuristic.deviceIsPortable,
                deviceTransmitRange = details.priceHeuristic.deviceTransmitRange,
                devicePower = details.priceHeuristic.devicePower,
                capabilities = details.priceHeuristic.capabilities,
                requirements = details.priceHeuristic.requirements,
                capabilityEvidence = details.priceHeuristic.capabilityEvidence,
                worldEvidenceAvailable = details.priceHeuristic.worldEvidenceAvailable,
                familyAnchor = details.priceHeuristic.familyAnchor,
                recipeDemandScore = details.priceHeuristic.recipeDemandScore,
                recipeCriticality = details.priceHeuristic.recipeCriticality,
                recipeContribution = details.priceHeuristic.recipeContribution,
                recipeDemand = details.priceHeuristic.recipeDemand,
                medicalLoot = details.priceHeuristic.isMedicalLoot,
                canBandage = details.priceHeuristic.canBandage,
                bandagePower = details.priceHeuristic.bandagePower,
                reduceInfectionPower = details.priceHeuristic.reduceInfectionPower,
                alcoholPower = details.priceHeuristic.alcoholPower,
                painReduction = details.priceHeuristic.painReduction,
                fluReduction = details.priceHeuristic.fluReduction,
                foodSicknessChange = details.priceHeuristic.foodSicknessChange,
                useSelf = details.priceHeuristic.useSelf,
                replaceOnUse = details.priceHeuristic.replaceOnUse,
                replaceOnUseOn = details.priceHeuristic.replaceOnUseOn,
                isDisappearOnUse = details.priceHeuristic.isDisappearOnUse,
                worldObjectClass = details.priceHeuristic.worldObjectClass,
                worldContainerCapacity = details.priceHeuristic.worldContainerCapacity,
                worldSurface = details.priceHeuristic.worldSurface,
            })
    end

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
        and details.category ~= "Liquid" then
        local tags = { details.primary }
        for _, t in ipairs(details.tags or {}) do
            if string.find(t, ".", 1, true) then
                tags[#tags + 1] = t
            end
        end
        sandboxAdd = sandboxAdd + Config.getSandboxTagMultiplier("Price", tags)
    end
    working = working + sandboxAdd
    addAudit(audit, "sandbox add", beforeSandbox, working, sandboxAdd)

    local beforeGlobal = working
    working = working * (tonumber(Config.pricing.baseMultiplier) or 1)
    addAudit(audit, "global mult", beforeGlobal, working, Config.pricing.baseMultiplier)

    if details.category ~= "Liquid" and details.category ~= "Weapon"
        and not isFoodCategory(details.category)
        and not isLiteratureCategory(details.category)
        and not isClothingCategory(details.category)
        and not isContainerCategory(details.category)
        and details.category ~= "Tool"
        and details.category ~= "Medical"
        and details.category ~= "Building" then
        working = applyAdjustment(working, DB.getCategory(details.category), "category:" .. tostring(details.category), audit)
        for _, tag in ipairs(details.expandedTags or details.tags or {}) do
            working = applyAdjustment(working, DB.getTag(tag), "tag:" .. tag, audit)
        end
    elseif isFoodCategory(details.category) then
        addAudit(audit, "food v2 balances", working, working, {
            legacyTagAdditions = false,
            reason = "Food valuation is feature/profile driven.",
        })
    elseif details.category == "Weapon" then
        addAudit(audit, "weapon v2 pending balances", working, working, {
            legacyTagAdditions = false,
            reason = "Weapon valuation is neutral pending calibration except for verified reusable tool demand.",
        })
    elseif isLiteratureCategory(details.category) then
        addAudit(audit, "literature v2 pending balances", working, working, {
            legacyTagAdditions = false,
            reason = "Literature valuation is intentionally neutral pending calibration.",
        })
    elseif isClothingCategory(details.category) then
        addAudit(audit, "clothing v2 pending balances", working, working, {
            legacyTagAdditions = false,
            reason = "Clothing valuation is intentionally neutral pending calibration.",
        })
    elseif isContainerCategory(details.category) then
        addAudit(audit, "container v2 pending balances", working, working, {
            legacyTagAdditions = false,
            reason = "Container valuation is intentionally neutral pending calibration.",
        })
    elseif details.category == "Tool" then
        addAudit(audit, "tool v2 balances", working, working, {
            legacyTagAdditions = false,
            reason = "Tool valuation is usefulness and recipe-demand driven.",
        })
    elseif details.category == "Electronics" then
        addAudit(audit, "electronics v2 pending balances", working, working, {
            legacyTagAdditions = false,
            reason = "Electronics valuation is neutral pending calibrated functional anchors.",
        })
    elseif details.category == "Medical" then
        addAudit(audit, "medical v2 pending balances", working, working, {
            legacyTagAdditions = false,
            reason = "Medical valuation is neutral pending calibrated treatment anchors.",
        })
    elseif details.category == "Building" then
        addAudit(audit, "building v2 pending balances", working, working, {
            legacyTagAdditions = false,
            reason = "Building valuation is neutral pending calibrated function anchors.",
        })
    elseif details.category == "Liquid" then
        addAudit(audit, "liquid v2 pending balances", working, working, {
            legacyTagAdditions = false,
            reason = "Liquid valuation is neutral pending calibrated utility anchors.",
        })
    else
        addAudit(audit, "generic balances", working, working, {
            reason = "Generic category/tag balances applied.",
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
        or details.category == "Liquid" then
        -- A cached pre-v2 detail may still contain a retired category score.
        -- Rebuild the neutral pending score after tag overrides so the cache
        -- cannot preserve legacy category dollars across a catalog refresh.
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
        and details.category ~= "Liquid" then
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
    if not isFoodCategory(details.category) and details.category ~= "Weapon"
        and not isLiteratureCategory(details.category)
        and not isClothingCategory(details.category)
        and not isContainerCategory(details.category)
        and details.category ~= "Tool"
        and details.category ~= "Electronics"
        and details.category ~= "Medical"
        and details.category ~= "Building" then
        working = applyAdjustment(working, DB.getCategory(details.category), "category:" .. tostring(details.category), audit)
        for _, tag in ipairs(details.expandedTags or {}) do
            working = applyAdjustment(working, DB.getTag(tag), "tag:" .. tag, audit)
        end
    elseif details.category == "Weapon" then
        addAudit(audit, "weapon v2 pending balances", working, working, {
            legacyTagAdditions = false,
            reason = "Weapon valuation is intentionally neutral pending calibration.",
        })
    elseif isLiteratureCategory(details.category) then
        addAudit(audit, "literature v2 pending balances", working, working, {
            legacyTagAdditions = false,
            reason = "Literature valuation is intentionally neutral pending calibration.",
        })
    elseif isClothingCategory(details.category) then
        addAudit(audit, "clothing v2 pending balances", working, working, {
            legacyTagAdditions = false,
            reason = "Clothing valuation is intentionally neutral pending calibration.",
        })
    elseif isContainerCategory(details.category) then
        addAudit(audit, "container v2 pending balances", working, working, {
            legacyTagAdditions = false,
            reason = "Container valuation is intentionally neutral pending calibration.",
        })
    elseif details.category == "Tool" then
        addAudit(audit, "tool v2 balances", working, working, {
            legacyTagAdditions = false,
            reason = "Tool valuation is usefulness and recipe-demand driven.",
        })
    elseif details.category == "Electronics" then
        addAudit(audit, "electronics v2 pending balances", working, working, {
            legacyTagAdditions = false,
            reason = "Electronics valuation is neutral pending calibrated functional anchors.",
        })
    elseif details.category == "Medical" then
        addAudit(audit, "medical v2 pending balances", working, working, {
            legacyTagAdditions = false,
            reason = "Medical valuation is neutral pending calibrated treatment anchors.",
        })
    elseif details.category == "Building" then
        addAudit(audit, "building v2 pending balances", working, working, {
            legacyTagAdditions = false,
            reason = "Building valuation is neutral pending calibrated function anchors.",
        })
    elseif details.category == "Liquid" then
        addAudit(audit, "liquid v2 pending balances", working, working, {
            legacyTagAdditions = false,
            reason = "Liquid valuation is neutral pending calibrated utility anchors.",
        })
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
