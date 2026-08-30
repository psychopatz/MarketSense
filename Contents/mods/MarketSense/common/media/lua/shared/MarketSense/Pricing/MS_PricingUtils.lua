require "MarketSense/MS_Core"

local Core = MarketSense.Core
local Utils = {}

local CATEGORY_BASE_SCORES = {
    Medical = 18, Weapon = 18, Tool = 14,
    Container = 14, Clothing = 4, Electronics = 14, Resource = 5,
    Building = 5, Liquid = 5, Literature = 5, Misc = 2,
}

local function addAudit(audit, label, before, after, extra)
    if not audit then return end
    audit[#audit + 1] = { label = label, before = before, after = after, extra = extra }
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

local function number(value, fallback)
    value = tonumber(value)
    return value ~= nil and value or fallback
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function normalized(value, scale, ceiling)
    value = number(value, 0)
    scale = number(scale, 1)
    if value <= 0 or scale <= 0 then return 0 end
    return math.min(number(ceiling, 1), value / scale)
end

local function addContribution(list, label, value, evidence)
    value = number(value, 0)
    if value <= 0 then return 0 end
    local contribution = {
        anchor = tostring(label or "anchor"),
        contribution = value,
    }
    if evidence ~= nil then contribution.evidence = evidence end
    list[#list + 1] = contribution
    return value
end

local function sumContributions(list)
    local total = 0
    for _, entry in ipairs(list or {}) do
        total = total + number(entry and entry.contribution, 0)
    end
    return total
end

local function scoreAnchors(anchor, positive, negative, options)
    options = options or {}
    local positiveScore = sumContributions(positive)
    local negativeScore = sumContributions(negative)
    local subtotal = number(anchor, 0) + positiveScore - negativeScore
    local stateFactor = clamp(number(options.stateFactor, 1), 0, 1.5)
    local weightPenalty = math.max(0, number(options.weightPenalty, 0))
    local floor = math.max(0, number(options.floor, 1))
    local ceiling = math.max(floor, number(options.ceiling, 250))
    local score = clamp(subtotal * stateFactor - weightPenalty, floor, ceiling)
    return score, {
        anchor = number(anchor, 0),
        positiveScore = positiveScore,
        negativeScore = negativeScore,
        subtotal = subtotal,
        stateFactor = stateFactor,
        weightPenalty = weightPenalty,
        floor = floor,
        ceiling = ceiling,
    }
end

local function runtimeStateFactor(ctx, options)
    ctx = ctx or {}
    options = options or {}
    local factor = 1.0
    local conditionMax = number(ctx.conditionMax, 0)
    if conditionMax > 0 and ctx.conditionRatio ~= nil then
        local floor = clamp(number(options.conditionFloor, 0.15), 0, 1)
        factor = floor + (1 - floor) * clamp(number(ctx.conditionRatio, 1), 0, 1)
    end
    if ctx.remainingUsesRatio ~= nil then
        local floor = clamp(number(options.usesFloor, 0.25), 0, 1)
        factor = factor * (floor + (1 - floor)
            * clamp(number(ctx.remainingUsesRatio, 1), 0, 1))
    end
    if ctx.isRotten == true or ctx.isPoison == true or ctx.isBurnt == true then
        factor = factor * clamp(number(options.harmfulFactor, 0.15), 0, 1)
    elseif ctx.isDung == true then
        factor = factor * clamp(number(options.wasteFactor, 0.35), 0, 1)
    end
    return clamp(factor, 0, 1.5)
end

local function addYieldEvidence(heuristic, details)
    heuristic = heuristic or {}
    local yield = type(details) == "table"
        and type(details.yieldResolution) == "table"
        and details.yieldResolution or {}
    heuristic.yieldStatus = yield.status or "not_detected"
    heuristic.yieldRecipe = yield.recipe
    heuristic.yieldOutputCount = type(yield.outputs) == "table"
        and #yield.outputs or 0
    local totalQuantity = 0
    local outputs = {}
    for _, output in ipairs(yield.outputs or {}) do
        local quantity = tonumber(output.quantity)
        if quantity ~= nil then totalQuantity = totalQuantity + quantity end
        outputs[#outputs + 1] = Core.deepCopy(output)
    end
    heuristic.yieldOutputQuantity = totalQuantity
    heuristic.yieldOutputs = outputs
    return heuristic
end

local function bundleModel(model)
    model = tostring(model or "v2")
    if string.sub(model, -8) == "_pending" then
        model = string.sub(model, 1, -9)
    end
    return model .. "_bundle"
end

Utils.CATEGORY_BASE_SCORES = CATEGORY_BASE_SCORES
Utils.addAudit = addAudit
Utils.isFoodCategory = isFoodCategory
Utils.isLiteratureCategory = isLiteratureCategory
Utils.isClothingCategory = isClothingCategory
Utils.isContainerCategory = isContainerCategory
Utils.clampAndRound = clampAndRound
Utils.number = number
Utils.clamp = clamp
Utils.normalized = normalized
Utils.addContribution = addContribution
Utils.sumContributions = sumContributions
Utils.scoreAnchors = scoreAnchors
Utils.bundleModel = bundleModel
Utils.runtimeStateFactor = runtimeStateFactor
Utils.addYieldEvidence = addYieldEvidence

return Utils
