require "MarketSense/MS_Config"
require "MarketSense/MS_Core"
require "MarketSense/MS_HeuristicsDB"
require "MarketSense/Pricing/MS_PricingUtils"

MarketSense = MarketSense or {}
MarketSense.Pricing = MarketSense.Pricing or {}

local Pricing = MarketSense.Pricing
local Core = MarketSense.Core
local Config = MarketSense.ItemRuntimeConfig
local DB = MarketSense.HeuristicsDB
local Utils = require "MarketSense/Pricing/MS_PricingUtils"
local addAudit = Utils.addAudit
local applyAdjustment = Utils.applyAdjustment
local isFoodCategory = Utils.isFoodCategory
local isLiteratureCategory = Utils.isLiteratureCategory
local isClothingCategory = Utils.isClothingCategory
local isContainerCategory = Utils.isContainerCategory
local clampAndRound = Utils.clampAndRound

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
                yieldEvaluation = details.priceHeuristic.yieldEvaluation,
                yieldBlockedReason = details.priceHeuristic.yieldBlockedReason,
                yieldMode = details.priceHeuristic.mode,
                yieldValue = details.priceHeuristic.yieldValue,
                yieldContributions = details.priceHeuristic.contributions,
                positiveContributions = details.priceHeuristic.positiveContributions,
                negativeContributions = details.priceHeuristic.negativeContributions,
                anchor = details.priceHeuristic.anchor,
                positiveScore = details.priceHeuristic.positiveScore,
                negativeScore = details.priceHeuristic.negativeScore,
                subtotal = details.priceHeuristic.subtotal,
                stateFactor = details.priceHeuristic.stateFactor,
                weightPenalty = details.priceHeuristic.weightPenalty,
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
        and details.category ~= "Building"
        and details.category ~= "Resource"
        and details.category ~= "Misc" then
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
        addAudit(audit, "weapon v2 balances", working, working, {
            legacyTagAdditions = false,
            reason = "Weapon valuation is combat performance, condition, handling, and verified recipe demand.",
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

return Pricing
