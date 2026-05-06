require "MarketSense/signatures/tags/MS_TagMapper"

MarketSense = MarketSense or {}
MarketSense.Signatures = MarketSense.Signatures or {}

local Signature = {}
local TagMapper = MarketSense.TagMapper

local FLUID_TOKENS = {
    water      = "BeverageWater",
    cleanwater = "BeverageWater",
    saltwater   = "BeverageWater",
    beer        = "BeverageBeer",
    wine        = "BeverageWine",
    whiskey     = "BeverageAlcohol",
    bourbon     = "BeverageAlcohol",
    vodka       = "BeverageAlcohol",
    rum         = "BeverageAlcohol",
    gin         = "BeverageAlcohol",
    moonshine   = "BeverageAlcohol",
    coffee      = "BeverageCoffee",
    tea         = "BeverageTea",
    juice       = "BeverageJuice",
    soda        = "BeverageSoda",
    cola        = "BeverageSoda",
    energy      = "BeverageSoda",
    milk        = "BeverageDairy",
}

local function isFluidContainer(ctx)
    return ctx.isFluidContainer == true
        or ctx.hasPourType == true
        or (ctx.lootTypeLower or "") == "beverage"
        or (ctx.eatTypeLower or "") == "beverage"
end

local function detectFluidToken(ctx)
    local fluidStr = (ctx.fluidTypeStringLower or "") ~= "" and ctx.fluidTypeStringLower
                     or ctx.fluidTypeLower or ""
    for key, token in pairs(FLUID_TOKENS) do
        if fluidStr:find(key, 1, true) then return token end
    end
    -- Fallback: check id/display name
    local id = ctx.idLower or ""
    for key, token in pairs(FLUID_TOKENS) do
        if id:find(key, 1, true) then return token end
    end
    return nil
end

function Signature.match(ctx)
    if not isFluidContainer(ctx) then
        return { matched = false, confidence = 0 }
    end

    -- Alcohol check: high alcohol power or isPoison-tagged beverages
    if (tonumber(ctx.alcoholPower) or 0) > 0.05 then
        local fluTok = detectFluidToken(ctx)
        if fluTok then
            return TagMapper.makeResult(fluTok, 0.93, { source = "beverage_fluid_alcohol" })
        end
        return TagMapper.makeResult("BeverageAlcohol", 0.88, { source = "beverage_alcohol_power" })
    end

    local fluTok = detectFluidToken(ctx)
    if fluTok then
        return TagMapper.makeResult(fluTok, 0.92, { source = "beverage_fluid" })
    end

    return TagMapper.makeResult("Beverage", 0.82, { source = "beverage_generic" })
end

MarketSense.Signatures.Beverage = Signature
return Signature
