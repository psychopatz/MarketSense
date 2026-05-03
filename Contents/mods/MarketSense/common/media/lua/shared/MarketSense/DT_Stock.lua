require "MarketSense/DT_AutoTag"

DynamicTrading = DynamicTrading or {}
DynamicTrading.Stock = DynamicTrading.Stock or {}

local Stock = DynamicTrading.Stock
local Core = DynamicTrading.Core
local DB = DynamicTrading.HeuristicsDB
local Config = DynamicTrading.ItemRuntimeConfig

local function cloneStock(stock)
    return {
        min = math.max(0, tonumber(stock and stock.min) or 0),
        max = math.max(0, tonumber(stock and stock.max) or 0),
    }
end

local function applyEntry(entry, state)
    if type(entry) ~= "table" then
        return
    end

    if type(entry.stock) == "table" then
        state.stock = cloneStock(entry.stock)
    end

    if entry.stockMultiplier ~= nil then
        state.multiplier = state.multiplier * math.max(0, tonumber(entry.stockMultiplier) or 1)
    end

    if entry.minRatio ~= nil then
        state.minRatio = math.max(0, tonumber(entry.minRatio) or state.minRatio)
    end
end

function Stock.baseMaxForWeight(weight)
    weight = tonumber(weight) or 0
    if weight <= 0.05 then return Config.stock.ultralightMax end
    if weight <= 0.20 then return Config.stock.lightMax end
    if weight <= 0.50 then return Config.stock.smallMax end
    if weight <= 1.50 then return Config.stock.mediumMax end
    if weight <= 5.00 then return Config.stock.heavyMax end
    return Config.stock.massiveMax
end

function Stock.calculate(fullType, ctx, details)
    ctx = ctx or DynamicTrading.PropertyReader.buildContext(fullType)
    details = details or {}

    local baseStock = details.stock and cloneStock(details.stock) or {
        min = 0,
        max = Stock.baseMaxForWeight(ctx.weight),
    }

    if baseStock.min <= 0 then
        baseStock.min = math.floor(baseStock.max * (Config.stock.defaultMinRatio or 0.2))
    end

    local globalMult = Config.stock.globalMultiplier or 1.0
    local tagMult = Config.getSandboxTagMultiplier and Config.getSandboxTagMultiplier("Stock", details.primary) or 1.0

    local state = {
        stock = baseStock,
        multiplier = globalMult * tagMult,
        minRatio = Config.stock.defaultMinRatio or 0.2,
    }

    applyEntry(DB.getCategory(details.category), state)

    for _, tag in ipairs(details.expandedTags or details.tags or {}) do
        applyEntry(DB.getTag(tag), state)
    end

    applyEntry(DB.getModule(ctx.moduleName), state)

    local itemEntry = DB.getItem(ctx.fullType)
    if itemEntry and type(itemEntry.stock) == "table" then
        return cloneStock(itemEntry.stock)
    end

    applyEntry(itemEntry, state)

    local maxValue = math.max(0, Core.round((state.stock.max or 0) * state.multiplier))
    maxValue = math.min(maxValue, Config.stock.maxCap or 100)

    local minValue = state.stock.min or 0
    minValue = math.max(minValue, math.floor(maxValue * state.minRatio))
    minValue = math.min(minValue, maxValue)

    return {
        min = minValue,
        max = maxValue,
    }
end

return Stock
