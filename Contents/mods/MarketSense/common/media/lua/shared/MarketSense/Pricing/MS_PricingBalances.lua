require "MarketSense/MS_Config"
require "MarketSense/MS_Core"
require "MarketSense/MS_HeuristicsDB"
require "MarketSense/Pricing/MS_PricingUtils"
require "MarketSense/Pricing/MS_MarketModifiers"
require "MarketSense/Pricing/MS_VesselPricing"

MarketSense = MarketSense or {}
MarketSense.Pricing = MarketSense.Pricing or {}

local Pricing = MarketSense.Pricing
local Config = MarketSense.ItemRuntimeConfig
local DB = MarketSense.HeuristicsDB
local Core = MarketSense.Core
local Utils = require "MarketSense/Pricing/MS_PricingUtils"
local MarketModifiers = require "MarketSense/Pricing/MS_MarketModifiers"
local VesselPricing = require "MarketSense/Pricing/MS_VesselPricing"
local FoodPricing = MarketSense.FoodPricing
local addAudit = Utils.addAudit
local clampAndRound = Utils.clampAndRound

function Pricing.applyBalances(ctx, details, audit)
    local working = tonumber(details.rawScore or 0) or 0
    -- Persisted definition snapshots already contain the resolved vessel
    -- identity. Recalculate its small policy value, but never walk Java item
    -- definitions again on the catalog path. Concrete inventory instances do
    -- not set this field and continue through the live resolver.
    local vessel = details._cachedVesselPricing
    if type(vessel) ~= "table" then
        vessel = VesselPricing.calculate(ctx, details)
    end
    if details.priceHeuristic and type(vessel) == "table" then
        details.priceHeuristic.vesselModel = vessel.model
        details.priceHeuristic.vesselValue = vessel.value
        details.priceHeuristic.vesselStatus = vessel.status
        details.priceHeuristic.vesselSource = vessel.source
        details.priceHeuristic.vesselState = vessel.state
        details.priceHeuristic.vesselName = vessel.vesselName
        details.priceHeuristic.vesselFullType = vessel.vesselFullType
        details.priceHeuristic.vesselProfile = vessel.vesselProfile
        details.priceHeuristic.vesselCapacity = vessel.capacity
        details.priceHeuristic.vesselWeight = vessel.weight
    end
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
                fluidContainerName = details.priceHeuristic.fluidContainerName,
                fluidPrimaryAmount = details.priceHeuristic.fluidPrimaryAmount,
                fluidFilledRatio = details.priceHeuristic.fluidFilledRatio,
                fluidIsEmpty = details.priceHeuristic.fluidIsEmpty,
                fluidIsMixture = details.priceHeuristic.fluidIsMixture,
                yieldStatus = details.priceHeuristic.yieldStatus,
                yieldRecipe = details.priceHeuristic.yieldRecipe,
                yieldOutputCount = details.priceHeuristic.yieldOutputCount,
                yieldOutputQuantity = details.priceHeuristic.yieldOutputQuantity,
                yieldOutputs = details.priceHeuristic.yieldOutputs,
                yieldEvaluation = details.priceHeuristic.yieldEvaluation,
                yieldBlockedReason = details.priceHeuristic.yieldBlockedReason,
                yieldMode = details.priceHeuristic.mode,
                yieldValue = details.priceHeuristic.yieldValue,
                yieldMultiplier = details.priceHeuristic.yieldMultiplier,
                yieldPremium = details.priceHeuristic.yieldPremium,
                quantityExponent = details.priceHeuristic.quantityExponent,
                aggregateFloor = details.priceHeuristic.aggregateFloor,
                aggregateCeiling = details.priceHeuristic.aggregateCeiling,
                yieldContributions = details.priceHeuristic.contributions,
                positiveContributions = details.priceHeuristic.positiveContributions,
                negativeContributions = details.priceHeuristic.negativeContributions,
                anchor = details.priceHeuristic.anchor,
                positiveScore = details.priceHeuristic.positiveScore,
                negativeScore = details.priceHeuristic.negativeScore,
                subtotal = details.priceHeuristic.subtotal,
                stateFactor = details.priceHeuristic.stateFactor,
                weightPenalty = details.priceHeuristic.weightPenalty,
                vesselModel = details.priceHeuristic.vesselModel,
                vesselValue = details.priceHeuristic.vesselValue,
                vesselStatus = details.priceHeuristic.vesselStatus,
                vesselSource = details.priceHeuristic.vesselSource,
                vesselState = details.priceHeuristic.vesselState,
                vesselName = details.priceHeuristic.vesselName,
                vesselFullType = details.priceHeuristic.vesselFullType,
                vesselProfile = details.priceHeuristic.vesselProfile,
                vesselCapacity = details.priceHeuristic.vesselCapacity,
                vesselWeight = details.priceHeuristic.vesselWeight,
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
                materialFamily = details.priceHeuristic.materialFamily,
                materialForm = details.priceHeuristic.materialForm,
                canStack = details.priceHeuristic.canStack,
                stackCount = details.priceHeuristic.stackCount,
                unbundleCandidate = details.priceHeuristic.unbundleCandidate,
                signals = details.priceHeuristic.signals,
                isMemento = details.priceHeuristic.isMemento,
                isJunk = details.priceHeuristic.isJunk,
            })
    end

    -- Convert the heuristic score into the configured root-category currency
    -- band before applying semantic category, subcategory, theme, rarity,
    -- condition, and stock modifiers. The band is a normal-price reference,
    -- not a final ceiling.
    local itemEntry = DB.getItem(ctx.fullType)
    local exactPrice = tonumber(details.exactPrice)
    local hasExactPrice = not details._ignoreExactPrice
        and not details._instancePricing
        and ((itemEntry and itemEntry.price ~= nil) or exactPrice ~= nil)
    if not hasExactPrice then
        if FoodPricing and type(FoodPricing.applyPolicy) == "function" then
            working = FoodPricing.applyPolicy(ctx, details, working, audit)
        end
        local bandSummary = {}
        working = MarketModifiers.applyCategoryBand(working, details, audit, bandSummary)
        details.priceBandApplied = true
        if details.priceHeuristic and bandSummary.categoryBand then
            details.priceHeuristic.categoryBand = Core.deepCopy(bandSummary.categoryBand)
        end
    end

    if type(vessel) == "table" and tonumber(vessel.value) and vessel.value ~= 0
        and not hasExactPrice
    then
        local beforeVessel = working
        working = working + tonumber(vessel.value)
        addAudit(audit, "vessel value", beforeVessel, working, {
            value = vessel.value,
            vessel = vessel.vesselName,
            source = vessel.source,
            state = vessel.state,
            profile = vessel.vesselProfile,
            capacity = vessel.capacity,
        })
    end

    -- Typed category/tag/item modifiers are applied exactly once before the
    -- global controls. Bundle scores are already aggregate yield scores, so
    -- the seed variation is applied once to that aggregate here.
    working = MarketModifiers.apply(ctx, details, working, audit)

    local beforeSandbox = working
    local sandboxAdd = tonumber(Config.pricing.globalValue) or 0
    working = working + sandboxAdd
    addAudit(audit, "sandbox global add", beforeSandbox, working, sandboxAdd)

    local beforeGlobal = working
    working = working * (tonumber(Config.pricing.baseMultiplier) or 1)
    addAudit(audit, "global mult", beforeGlobal, working, Config.pricing.baseMultiplier)

    if hasExactPrice then
        local overridePrice = details.marketPricing
            and details.marketPricing.overridePrice
            or exactPrice
            or itemEntry.price
        local finalPrice = clampAndRound(overridePrice)
        addAudit(audit, "item final price", working, finalPrice)
        return finalPrice
    end

    local finalPrice = clampAndRound(working)
    addAudit(audit, "clamp+round", working, finalPrice)
    return finalPrice
end

return Pricing
