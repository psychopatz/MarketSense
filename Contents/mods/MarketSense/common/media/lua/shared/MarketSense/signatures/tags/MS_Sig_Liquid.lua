require "MarketSense/signatures/tags/MS_TagMapper"

MarketSense = MarketSense or {}
MarketSense.Signatures = MarketSense.Signatures or {}

local Signature = {}
local TagMapper = MarketSense.TagMapper

-- Fluid names are runtime content names, not item/container names.  Keep the
-- rules longest-match-first by selecting the longest matching needle below;
-- this makes CarbonatedWater beat Water and AnimalBlood beat Blood without
-- relying on Lua table iteration order.
local FLUID_RULES = {
    { needle = "carbonatedwater", token = "LiquidCarbonatedWater", confidence = 0.96 },
    { needle = "taintedwater", token = "LiquidTaintedWater", confidence = 0.96 },
    { needle = "water", token = "LiquidWater", confidence = 0.94 },
    { needle = "animalblood", token = "LiquidAnimalBlood", confidence = 0.95 },
    { needle = "blood", token = "LiquidBlood", confidence = 0.94 },
    { needle = "animalgrease", token = "LiquidAnimalGrease", confidence = 0.95 },
    { needle = "grease", token = "LiquidAnimalGrease", confidence = 0.91 },
    { needle = "rubbingalcohol", token = "LiquidMedical", confidence = 0.95 },
    { needle = "cleaningliquid", token = "LiquidChemical", confidence = 0.95 },
    { needle = "cologne", token = "LiquidChemical", confidence = 0.92 },
    { needle = "perfume", token = "LiquidChemical", confidence = 0.92 },
    { needle = "hairdye", token = "LiquidHairDye", confidence = 0.96 },
    { needle = "dye", token = "LiquidDye", confidence = 0.93 },
    { needle = "acid", token = "LiquidChemical", confidence = 0.94 },
    { needle = "bleach", token = "LiquidChemical", confidence = 0.94 },
    { needle = "poison", token = "LiquidChemical", confidence = 0.90 },
    { needle = "petrol", token = "LiquidFuel", confidence = 0.96 },
    { needle = "diesel", token = "LiquidFuel", confidence = 0.96 },
    { needle = "kerosene", token = "LiquidFuel", confidence = 0.96 },
    { needle = "fuel", token = "LiquidFuel", confidence = 0.90 },
    { needle = "gingerale", token = "LiquidSoda", confidence = 0.94 },
    { needle = "softdrink", token = "LiquidSoda", confidence = 0.92 },
    { needle = "energy", token = "LiquidSoda", confidence = 0.88 },
    { needle = "cola", token = "LiquidSoda", confidence = 0.94 },
    { needle = "soda", token = "LiquidSoda", confidence = 0.94 },
    { needle = "lemonade", token = "LiquidJuice", confidence = 0.92 },
    { needle = "juice", token = "LiquidJuice", confidence = 0.92 },
    { needle = "syrup", token = "LiquidSyrup", confidence = 0.90 },
    { needle = "grenadine", token = "LiquidSyrup", confidence = 0.92 },
    { needle = "coffee", token = "LiquidCoffee", confidence = 0.92 },
    { needle = "tea", token = "LiquidTea", confidence = 0.92 },
    { needle = "cowmilk", token = "LiquidMilk", confidence = 0.94 },
    { needle = "animalmilk", token = "LiquidMilk", confidence = 0.94 },
    { needle = "sheepmilk", token = "LiquidMilk", confidence = 0.94 },
    { needle = "milk", token = "LiquidMilk", confidence = 0.92 },
    { needle = "champagne", token = "LiquidAlcohol", confidence = 0.94 },
    { needle = "brandy", token = "LiquidAlcohol", confidence = 0.94 },
    { needle = "liqueur", token = "LiquidAlcohol", confidence = 0.94 },
    { needle = "moonshine", token = "LiquidAlcohol", confidence = 0.94 },
    { needle = "whiskey", token = "LiquidAlcohol", confidence = 0.94 },
    { needle = "bourbon", token = "LiquidAlcohol", confidence = 0.94 },
    { needle = "vodka", token = "LiquidAlcohol", confidence = 0.94 },
    { needle = "tequila", token = "LiquidAlcohol", confidence = 0.94 },
    { needle = "cider", token = "LiquidAlcohol", confidence = 0.92 },
    { needle = "curacao", token = "LiquidAlcohol", confidence = 0.94 },
    { needle = "vermouth", token = "LiquidAlcohol", confidence = 0.94 },
    { needle = "sherry", token = "LiquidAlcohol", confidence = 0.94 },
    { needle = "scotch", token = "LiquidAlcohol", confidence = 0.94 },
    { needle = "port", token = "LiquidAlcohol", confidence = 0.94 },
    { needle = "beer", token = "LiquidBeer", confidence = 0.94 },
    { needle = "wine", token = "LiquidWine", confidence = 0.94 },
    { needle = "gin", token = "LiquidAlcohol", confidence = 0.94 },
    { needle = "rum", token = "LiquidAlcohol", confidence = 0.94 },
    { needle = "alcohol", token = "LiquidAlcohol", confidence = 0.88 },
}

local function hasCategory(ctx, token)
    if string.find(ctx.fluidCategoryLower or "", token, 1, true) then
        return true
    end
    for _, category in ipairs(ctx.fluidCategoriesLower or {}) do
        if string.find(category, token, 1, true) then
            return true
        end
    end
    return false
end

local function bestRule(fluidName)
    local selected = nil
    local selectedLength = -1
    for _, rule in ipairs(FLUID_RULES) do
        if string.find(fluidName, rule.needle, 1, true) then
            local length = #rule.needle
            if length > selectedLength
                or (length == selectedLength and selected
                    and rule.token < selected.token) then
                selected = rule
                selectedLength = length
            end
        end
    end
    return selected
end

local function actualFluid(ctx)
    if ctx.isActualLiquid == true then return true end
    return (ctx.fluidTypeStringLower or "") ~= ""
        or (ctx.fluidTypeLower or "") ~= ""
end

local function details(ctx, source)
    return {
        source = source,
        fluidType = ctx.fluidTypeString ~= "" and ctx.fluidTypeString or ctx.fluidType,
        fluidCategory = ctx.fluidCategory,
        fluidCategories = ctx.fluidCategories,
        amount = ctx.fluidAmount,
        capacity = ctx.fluidCapacity,
        primaryAmount = ctx.fluidPrimaryAmount,
        filledRatio = ctx.fluidFilledRatio,
        isMixture = ctx.fluidIsMixture,
        unit = "liter_deferred",
    }
end

function Signature.match(ctx)
    if not ctx or not actualFluid(ctx) then
        return { matched = false, confidence = 0 }
    end

    local fluidName = (ctx.fluidTypeStringLower or "")
    if fluidName == "" then fluidName = ctx.fluidTypeLower or "" end
    local rule = bestRule(fluidName)
    if rule then
        return TagMapper.makeResult(rule.token, rule.confidence,
            details(ctx, "liquid_fluid_type"))
    end

    -- Workshop fluids may use names that MarketSense has never seen.  Fluid
    -- categories still provide a stable broad bucket for future consumers.
    if hasCategory(ctx, "fuel") then
        return TagMapper.makeResult("LiquidFuel", 0.78, details(ctx, "liquid_fluid_category_fuel"))
    end
    if hasCategory(ctx, "dye") then
        return TagMapper.makeResult("LiquidDye", 0.76, details(ctx, "liquid_fluid_category_dye"))
    end
    if hasCategory(ctx, "medical") then
        return TagMapper.makeResult("LiquidMedical", 0.74, details(ctx, "liquid_fluid_category_medical"))
    end
    if hasCategory(ctx, "hazardous") or hasCategory(ctx, "industrial") then
        return TagMapper.makeResult("LiquidIndustrial", 0.70, details(ctx, "liquid_fluid_category_industrial"))
    end
    if hasCategory(ctx, "beverage") or hasCategory(ctx, "alcoholic") then
        return TagMapper.makeResult("LiquidBeverage", 0.72, details(ctx, "liquid_fluid_category_beverage"))
    end

    return TagMapper.makeResult("LiquidUnknown", 0.50, details(ctx, "liquid_unknown_fluid"))
end

MarketSense.Signatures.Liquid = Signature
return Signature
