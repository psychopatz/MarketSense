-- Shared deterministic transform valuation for packages, cartons, boxes, and
-- any other item whose exact recipe outputs can be inspected.

require "MarketSense/MS_Core"
require "MarketSense/Pricing/MS_YieldResolver"

MarketSense = MarketSense or {}
MarketSense.TransformPricing = MarketSense.TransformPricing or {}

local TransformPricing = MarketSense.TransformPricing
local YieldResolver = MarketSense.YieldResolver

local function number(value, fallback)
    value = tonumber(value)
    return value ~= nil and value or fallback
end

local function copyPath(path)
    local result = {}
    for key, value in pairs(path or {}) do result[key] = value end
    return result
end

local function inheritedFoodState(parent, child, output)
    if output and output.inheritFoodAge == true and parent.hasRuntimeFoodAge == true then
        child.foodAge = parent.foodAge
        child.hasRuntimeFoodAge = true
        child.hasRuntimeFoodState = parent.hasRuntimeFoodState == true
        child.isRotten = parent.isRotten == true
        child.isFrozen = parent.isFrozen == true
    end
    return child
end

local function blocked(status, reason)
    return nil, {
        status = "blocked",
        yieldStatus = status or "not_detected",
        reason = reason or "transform is not deterministic",
    }
end

function TransformPricing.evaluate(ctx, details, options)
    ctx = ctx or {}
    details = details or {}
    options = options or {}

    local yieldInfo = type(details.yieldResolution) == "table"
        and details.yieldResolution or YieldResolver.resolve(ctx)
    details.yieldResolution = yieldInfo
    if type(yieldInfo) ~= "table" then
        return blocked("not_detected", "yield resolver returned no result")
    end
    if yieldInfo.status ~= "resolved" then
        return blocked(yieldInfo.status, "yield status is " .. tostring(yieldInfo.status))
    end

    local Pricing = MarketSense.Pricing
    if not Pricing or type(Pricing.calculateDetails) ~= "function" then
        return blocked("resolved", "pricing API unavailable")
    end

    local path = copyPath(details._yieldPath)
    local sourceFullType = tostring(ctx.fullType or "")
    if sourceFullType ~= "" then path[sourceFullType] = true end

    local total = 0
    local totalQuantity = 0
    local contributions = {}
    local hasMultiQuantity = false
    for _, output in ipairs(yieldInfo.outputs or {}) do
        local quantity = number(output.quantity, 0)
        local chance = number(output.chance, 1.0)
        local fullType = tostring(output.fullType or "")
        local resolution = tostring(output.resolution or "exact")
        if fullType == "" then
            return blocked("resolved", "output item is unresolved")
        end
        if quantity <= 0 then
            return blocked("resolved", "output quantity is not positive")
        end
        if chance < 1.0 or resolution ~= "exact" then
            return blocked("resolved", "probabilistic output is not deterministic")
        end
        if quantity ~= 1 then hasMultiQuantity = true end
        if path[fullType] then
            return blocked("resolved", "yield cycle detected")
        end

        local childContext = MarketSense.PropertyReader
            and MarketSense.PropertyReader.buildContext(fullType) or nil
        if type(childContext) ~= "table" or childContext.item == nil then
            return blocked("resolved", "output item is unavailable: " .. fullType)
        end
        childContext = inheritedFoodState(ctx, childContext, output)

        local childPath = copyPath(path)
        childPath[fullType] = true
        local childDetails = Pricing.calculateDetails(
            childContext, false, nil, { yieldPath = childPath }
        )
        if type(childDetails) ~= "table" then
            return blocked("resolved", "output item did not produce pricing details: " .. fullType)
        end
        local childYield = childDetails.yieldResolution
        if type(childYield) == "table"
            and childYield.status == "resolved"
            and (childYield.evaluation == "fallback"
                or (childDetails.priceHeuristic
                    and childDetails.priceHeuristic.yieldEvaluation == "blocked")) then
            return blocked("resolved", "nested transform evaluation failed: " .. fullType)
        end

        local unitValue = number(childDetails.rawScore, nil)
        if unitValue == nil then
            return blocked("resolved", "output item did not produce a raw score: " .. fullType)
        end
        local value = unitValue * quantity
        total = total + value
        totalQuantity = totalQuantity + quantity
        contributions[#contributions + 1] = {
            fullType = fullType,
            quantity = quantity,
            chance = chance,
            unitRawScore = unitValue,
            contribution = value,
            model = childDetails.priceHeuristic
                and childDetails.priceHeuristic.model or nil,
            category = childDetails.category,
            primary = childDetails.primary,
        }
    end

    if #contributions == 0 then
        return blocked("resolved", "yield has no outputs")
    end

    local multiplier = number(options.multiplier, 1.0)
    local premium = number(options.premium, 0.0)
    local floor = math.max(0, number(options.floor, 1.0))
    local ceiling = math.max(floor, number(options.ceiling, 250.0))
    local score = (total * multiplier) + premium
    score = math.max(floor, math.min(ceiling, score))
    return score, {
        status = "valued",
        mode = (#contributions > 1 or hasMultiQuantity)
            and "multi_output_bundle" or "replacement",
        yieldValue = total,
        yieldMultiplier = multiplier,
        yieldPremium = premium,
        contributions = contributions,
        outputCount = #contributions,
        outputQuantity = totalQuantity,
        score = score,
    }
end

return TransformPricing
