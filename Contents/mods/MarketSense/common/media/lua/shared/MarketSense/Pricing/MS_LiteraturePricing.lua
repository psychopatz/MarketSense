-- MarketSense literature pricing.
-- Knowledge and information are the scarce resource: skill progression,
-- recipe unlocks, maps, and verified entertainment are positive anchors.

require "MarketSense/MS_Config"
require "MarketSense/MS_Core"
require "MarketSense/Pricing/MS_PricingUtils"
require "MarketSense/Pricing/MS_TransformPricing"

MarketSense = MarketSense or {}
MarketSense.LiteraturePricing = MarketSense.LiteraturePricing or {}

local LiteraturePricing = MarketSense.LiteraturePricing
local Config = MarketSense.ItemRuntimeConfig
local Core = MarketSense.Core
local Utils = require "MarketSense/Pricing/MS_PricingUtils"
local TransformPricing = MarketSense.TransformPricing

local DEFAULTS = {
    model = "literature_v2", anchor = 5.0, floor = 1.0, ceiling = 200.0,
    skillWeight = 2.0, recipeWeight = 1.5, mapAnchor = 4.0,
    entertainmentWeight = 0.04, writingAnchor = 1.5, weightPenalty = 0.55,
    genericPenalty = 0.5, conditionFloor = 0.20,
    yieldMultiplier = 1.0, yieldPremium = 0.0,
}

local function number(value, fallback)
    value = tonumber(value)
    return value ~= nil and value or fallback
end

local function settings()
    local configured = Config and Config.literaturePricing
    if type(configured) ~= "table" then return DEFAULTS end
    local result = {}
    for key, fallback in pairs(DEFAULTS) do
        result[key] = configured[key] ~= nil and configured[key] or fallback
    end
    return result
end

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function relief(value)
    return math.max(0, -number(value, 0))
end

local function countRecipes(recipes)
    if type(recipes) ~= "table" then return 0 end
    return #recipes
end

function LiteraturePricing.calculate(ctx, details)
    ctx = ctx or {}
    details = details or {}
    local c = settings()
    local classification = type(details.classificationDetails) == "table"
        and details.classificationDetails or {}
    local recipes = ctx.learnedRecipes or {}
    local recipeCount = countRecipes(recipes)
    local identity = lower(table.concat({
        details.primary or "", ctx.readType or "", ctx.description or "",
        ctx.idLower or "", ctx.displayNameLower or "",
    }, " "))
    local isMap = string.find(identity, "map", 1, true) ~= nil
        or string.find(identity, "cartograph", 1, true) ~= nil
    local heuristic = {
        model = tostring(c.model or DEFAULTS.model), status = "ready",
        subtype = details.primary or "Literature",
        reason = "Literature value combines knowledge unlocks, information, entertainment, and writing utility.",
        classifierSource = classification.source, classifierTag = classification.tag,
        skill = ctx.skillTrained, skillLevel = ctx.lvlSkillTrained,
        maxLevelTrained = ctx.maxLevelTrained, learnedRecipeCount = recipeCount,
        readType = ctx.readType, canBeWrite = ctx.canBeWrite == true,
        isLiteratureInstance = ctx.isLiteratureInstance == true,
        weight = ctx.weight, positiveContributions = {}, negativeContributions = {},
        plannedPositiveAnchors = {
            "skill progression and remaining level span",
            "recipe unlock count and utility",
            "map, navigation, or other information utility",
            "boredom, stress, and unhappiness relief",
            "readable or writable utility",
            "exact child-item yield valued per output quantity",
        },
        plannedNegativeAnchors = {
            "already-read or already-known state when exposed",
            "empty, consumed, or unusable content",
            "reading time and physical weight",
            "generic content without a mechanical effect",
            "format cost without additional utility",
        },
    }
    Utils.addYieldEvidence(heuristic, details)

    local transformScore, transform = TransformPricing.evaluate(ctx, details, {
        multiplier = c.yieldMultiplier, premium = c.yieldPremium,
        floor = c.floor, ceiling = c.ceiling,
    })
    if transformScore ~= nil then
        for key, value in pairs(transform) do heuristic[key] = value end
        heuristic.model = Utils.bundleModel(c.model)
        heuristic.status = "ready"
        heuristic.reason = "Deterministic transform valued from individualized child outputs."
        heuristic.yieldEvaluation = "valued"
        heuristic.positiveContributions = Core.deepCopy(transform.contributions)
        heuristic.score = transformScore
        details.priceHeuristic = heuristic
        return transformScore
    end
    heuristic.yieldEvaluation = "blocked"
    heuristic.yieldBlockedReason = type(transform) == "table" and transform.reason or nil

    local positives, negatives = heuristic.positiveContributions, heuristic.negativeContributions
    local level = number(ctx.lvlSkillTrained, -1)
    local maximum = number(ctx.maxLevelTrained, -1)
    local skillSpan = (level >= 0 and maximum >= level) and (maximum - level + 1) or 0
    local skillValue = math.min(10, skillSpan * number(c.skillWeight, 2))
    local recipeValue = math.min(10, math.sqrt(math.max(0, recipeCount))
        * number(c.recipeWeight, 1.5))
    local mapValue = isMap and number(c.mapAnchor, 4) or 0
    local entertainment = math.min(6, (relief(ctx.unhappyChange)
        + relief(ctx.boredomChange) + relief(ctx.stressChange))
        * number(c.entertainmentWeight, 0.04))
    local writing = ctx.canBeWrite == true and number(c.writingAnchor, 1.5) or 0
    Utils.addContribution(positives, "skill progression", skillValue, skillSpan)
    Utils.addContribution(positives, "recipe unlocks", recipeValue, recipeCount)
    Utils.addContribution(positives, "map or information", mapValue, isMap)
    Utils.addContribution(positives, "entertainment relief", entertainment, ctx.boredomChange)
    Utils.addContribution(positives, "writing utility", writing, ctx.canBeWrite)
    local weightPenalty = math.min(8, math.max(0, number(ctx.weight, 0))
        * number(c.weightPenalty, 0.55))
    local genericPenalty = (skillSpan <= 0 and recipeCount == 0 and not isMap
        and entertainment <= 0 and not ctx.canBeWrite)
        and number(c.genericPenalty, 0.5) or 0
    Utils.addContribution(negatives, "reading weight", weightPenalty, ctx.weight)
    Utils.addContribution(negatives, "generic no-effect content", genericPenalty, identity)
    local stateFactor = Utils.runtimeStateFactor(ctx, { conditionFloor = c.conditionFloor })
    local score, summary = Utils.scoreAnchors(c.anchor, positives, negatives, {
        stateFactor = stateFactor, floor = c.floor, ceiling = c.ceiling,
    })
    for key, value in pairs(summary) do heuristic[key] = value end
    heuristic.mode = "knowledge_and_information"
    heuristic.isMap = isMap
    heuristic.skillSpan = skillSpan
    heuristic.score = score
    details.priceHeuristic = heuristic
    return score
end

return LiteraturePricing
