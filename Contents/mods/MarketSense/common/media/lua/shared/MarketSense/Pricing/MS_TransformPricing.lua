-- Shared deterministic transform valuation for packages, cartons, boxes, and
-- any other item whose exact recipe outputs can be inspected.

require "MarketSense/MS_Core"
require "MarketSense/Pricing/MS_YieldResolver"
require "MarketSense/Pricing/MS_MarketModifiers"

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
    -- Bulk packages retain the value of more contents, but not linearly:
    -- the last units in a carton are less scarce. This is a discount curve,
    -- not a price ceiling; a large crisis bundle may still be very valuable.
    local quantityExponent = math.max(0.55, math.min(1.0,
        number(options.quantityExponent, 0.60)))
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

        local rawUnitValue = number(childDetails.rawScore, nil)
        if rawUnitValue == nil then
            return blocked("resolved", "output item did not produce a raw score: " .. fullType)
        end
        -- The parent package receives the child's mechanical score, then
        -- applies the parent's category/subcategory/theme/rarity rules once.
        -- Applying the child market layer here would charge those semantic
        -- premiums twice (the old path made packed tents and sleeping bags
        -- several times more expensive than their unpacked outputs).
        local unitValue, childSummary = MarketSense.MarketModifiers.apply(
            childContext, childDetails, rawUnitValue, nil, true, { rawOnly = true }
        )
        if childSummary and childSummary.absoluteOverride then
            unitValue = childSummary.overridePrice
        end
        unitValue = number(unitValue, rawUnitValue)
        unitValue = math.max(
            number(MarketSense.ItemRuntimeConfig and MarketSense.ItemRuntimeConfig.pricing
                and MarketSense.ItemRuntimeConfig.pricing.minPrice, 1),
            unitValue
        )
        local pricedQuantity = quantity <= 1 and quantity or quantity ^ quantityExponent
        local value = unitValue * pricedQuantity
        total = total + value
        totalQuantity = totalQuantity + quantity
        contributions[#contributions + 1] = {
            fullType = fullType,
            quantity = quantity,
            pricedQuantity = pricedQuantity,
            quantityDiscount = quantity > 0 and pricedQuantity / quantity or 1,
            chance = chance,
            unitRawScore = rawUnitValue,
            unitIntrinsicScore = unitValue,
            unitPricingStage = childSummary and childSummary.absoluteOverride
                and "exact_override" or "raw_mechanical",
            contribution = value,
            model = childDetails.priceHeuristic
                and childDetails.priceHeuristic.model or nil,
            category = childDetails.category,
            primary = childDetails.primary,
            marketModifiers = childSummary,
        }
    end

    if #contributions == 0 then
        return blocked("resolved", "yield has no outputs")
    end

    local multiplier = number(options.multiplier, 1.0)
    local premium = number(options.premium, 0.0)
    local floor = math.max(0, number(options.floor, 1.0))
    local ceiling = number(options.ceiling, nil)
    local score = (total * multiplier) + premium
    score = math.max(floor, score)
    if ceiling ~= nil then
        score = math.min(ceiling, score)
    end
    return score, {
        status = "valued",
        mode = (#contributions > 1 or hasMultiQuantity)
            and "multi_output_bundle" or "replacement",
        yieldValue = total,
        yieldMultiplier = multiplier,
        quantityExponent = quantityExponent,
        yieldPremium = premium,
        contributions = contributions,
        outputCount = #contributions,
        outputQuantity = totalQuantity,
        -- Kept as evidence for the report/API; nil means the aggregate is
        -- deliberately uncapped unless an integration explicitly opts in.
        aggregateCeiling = ceiling,
        aggregateFloor = floor,
        score = score,
    }
end

return TransformPricing
