require "MarketSense/MS_Config"
require "MarketSense/Pricing/MS_LiquidPricing"
require "MarketSense/Pricing/MS_ResourcePricing"
require "MarketSense/Pricing/MS_MiscPricing"
require "MarketSense/Pricing/MS_FoodPricing"
require "MarketSense/Pricing/MS_ContainerPricing"
require "MarketSense/Pricing/MS_ElectronicsPricing"
require "MarketSense/Pricing/MS_MedicalPricing"
require "MarketSense/Pricing/MS_BuildingPricing"
require "MarketSense/Pricing/MS_ToolRecipeDemand"
require "MarketSense/Pricing/MS_ToolPricing"
require "MarketSense/MS_Core"
require "MarketSense/Pricing/MS_PricingUtils"

MarketSense = MarketSense or {}
MarketSense.Pricing = MarketSense.Pricing or {}

local Pricing = MarketSense.Pricing
local Core = MarketSense.Core
local Config = MarketSense.ItemRuntimeConfig
local Utils = require "MarketSense/Pricing/MS_PricingUtils"
local LiquidPricing = MarketSense.LiquidPricing
local ResourcePricing = MarketSense.ResourcePricing
local MiscPricing = MarketSense.MiscPricing
local FoodPricing = MarketSense.FoodPricing
local ContainerPricing = MarketSense.ContainerPricing
local ElectronicsPricing = MarketSense.ElectronicsPricing
local MedicalPricing = MarketSense.MedicalPricing
local BuildingPricing = MarketSense.BuildingPricing
local ToolPricing = MarketSense.ToolPricing
local CATEGORY_BASE_SCORES = Utils.CATEGORY_BASE_SCORES
local isFoodCategory = Utils.isFoodCategory
local isLiteratureCategory = Utils.isLiteratureCategory
local isClothingCategory = Utils.isClothingCategory
local isContainerCategory = Utils.isContainerCategory

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
        -- The old resource score mixed a weight penalty with flat family and
        -- fuel dollars. Keep material, form, quantity, and processing evidence
        -- visible while the delivered-utility model is calibrated.
        details.priceHeuristic = ResourcePricing.buildPendingHeuristic(ctx, details)
        score = base

    elseif category == "Misc" then
        -- Misc is a heterogeneous fallback. Keep verified capability, state,
        -- and package evidence visible while preventing the old flat subtype
        -- bonuses from pricing unknown or decorative items as useful goods.
        details.priceHeuristic = MiscPricing.buildPendingHeuristic(ctx, details)
        score = base

    else
        score = base - weightPenalty
    end

    if (details.primary or "") == "Misc" then
        score = math.max(score, CATEGORY_BASE_SCORES.Misc)
    end
    return math.max(score, Config.pricing.minPrice or 1)
end

return Pricing
