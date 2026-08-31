MarketSense = MarketSense or {}
MarketSense.Config = MarketSense.Config or {}

MarketSense.Log = MarketSense.Log or function(level, subsystem, message)
    if type(print) == "function" then
        print("[MarketSense][" .. tostring(level or "Info") .. "]["
            .. tostring(subsystem or "Runtime") .. "] " .. tostring(message or ""))
    end
end

local rootConfig = MarketSense.Config
rootConfig.Runtime = rootConfig.Runtime or {}

local defaults = {
    debug = false,
    server = {
        buildCatalogOnBoot = false,
        allowLazyGeneration = false,
        cacheLazyItems = true,
        verboseBootScan = false,
    },
    pricing = {
        minPrice = 1,
        -- There is intentionally no global upper bound. Crisis prices must
        -- be able to reflect scarce weapons, medicine, fuel, and bulk goods.
        baseMultiplier = 1.0,
        baseMultiplierPercent = 0,
        globalValue = 0,
        openedPenalty = 0.72,
        contrastStrength = 0.08,
        contrastPercent = 8,
        variationEnabled = true,
        variationStrength = 0.08,
        variationPercent = 8,
        variationSalt = 1,
        variationAbsoluteOverrides = false,
        -- These are normal-price bands, not final hard caps. Multipliers for
        -- rarity, condition, scarcity, and exceptional utility may carry an
        -- item above the configured reference maximum.
        categoryBands = {
            Food = { min = 50, max = 500, response = 55, exponent = 0.85 },
            Beverage = { min = 25, max = 350, response = 35, exponent = 0.85 },
            Liquid = { min = 15, max = 400, response = 35, exponent = 0.85 },
            Weapon = { min = 40, max = 2000, response = 55, exponent = 0.85 },
            Medical = { min = 40, max = 1200, response = 35, exponent = 0.85 },
            Tool = { min = 25, max = 1000, response = 40, exponent = 0.85 },
            -- A normal pot/bowl/bottle should occupy the lower-middle of the
            -- container band; high-capacity bags and specialized storage can
            -- still overflow the normal reference maximum.
            Container = { min = 20, max = 700, response = 80, exponent = 0.85 },
            Clothing = { min = 10, max = 500, response = 25, exponent = 0.85 },
            Electronics = { min = 25, max = 750, response = 35, exponent = 0.85 },
            Literature = { min = 10, max = 300, response = 20, exponent = 0.85 },
            Resource = { min = 10, max = 700, response = 25, exponent = 0.85 },
            Building = { min = 20, max = 800, response = 35, exponent = 0.85 },
            Misc = { min = 5, max = 300, response = 20, exponent = 0.85 },
        },
    },
    foodPricing = {
        highCalorieThreshold = 300.0,
        highFatThreshold = 20.0,
        highProteinThreshold = 20.0,
        highCarbohydrateThreshold = 30.0,
        hydrationThreshold = 0.10,
        thirstThreshold = 0.10,
        openedPenalty = 0.72,
        sealedPreservationMultiplier = 1.20,
    },
    liquidPricing = {},
    -- Vessel value is appended after the category band and before semantic
    -- modifiers.  These are dollar contributions, not percentage controls.
    vesselPricing = {
        enabled = true,
        baseValue = 0,
        capacityValue = 1.0,
        weightPenalty = 1.0,
        openedPenalty = 1.0,
        sealedBonus = 0,
        retainedBonus = 0,
        unknownValue = 1,
    },
    resourcePricing = {},
    miscPricing = {},
    weaponPricing = {},
    literaturePricing = {},
    clothingPricing = {
        summerMaxInsulation = 0.25,
        summerMaxWindResistance = 0.25,
        winterMinInsulation = 0.75,
        winterMinWindResistance = 0.75,
        rainMinWaterResistance = 0.50,
    },
    containerPricing = {},
    electronicsPricing = {},
    medicalPricing = {},
    buildingPricing = {},
    toolPricing = {},
    stock = {
        ultralightMax = 50,
        lightMax = 25,
        smallMax = 15,
        mediumMax = 10,
        heavyMax = 5,
        massiveMax = 2,
        maxCap = 100,
        defaultMinRatio = 0.20,
    }
}

local runtime = rootConfig.Runtime

local function mergeDefaults(target, source)
    for key, value in pairs(source) do
        if type(value) == "table" then
            target[key] = target[key] or {}
            mergeDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

mergeDefaults(runtime, defaults)

-- Clear the old hard-cap default if this file is hot-reloaded in a live
-- session. An upper bound is not part of the MarketSense price model.
runtime.pricing.maxPrice = nil

local function getSandboxVarsTable()
    if SandboxVars and type(SandboxVars.MarketSense) == "table" then
        return SandboxVars.MarketSense
    end
    return nil
end

function MarketSense.Config.reloadExported()
    -- Pricing defaults live in the Lua pricing modules and the static
    -- modifier data module. The generated pricing table is retained for
    -- audit/export tooling only; it must not become a runtime dependency or
    -- silently override the source-of-truth defaults after a cache refresh.
    return false
end

function MarketSense.Config.applySandboxOptions()
    local vars = getSandboxVarsTable()
    if vars then
        runtime.sandboxVars = vars
        if vars.PriceMultiplierPercent ~= nil then
            local percent = math.floor(tonumber(vars.PriceMultiplierPercent) or 0)
            percent = math.max(-100, math.min(1000, percent))
            runtime.pricing.baseMultiplierPercent = percent
            runtime.pricing.baseMultiplier = 1.0 + (percent / 100.0)
        elseif vars.PriceMultiplier ~= nil then
            -- Compatibility for worlds created with the old 1.0 = neutral
            -- decimal multiplier. New worlds use the integer-percent option.
            runtime.pricing.baseMultiplier = tonumber(vars.PriceMultiplier) or 1.0
            runtime.pricing.baseMultiplierPercent = math.floor(
                ((runtime.pricing.baseMultiplier - 1.0) * 100.0) + 0.5
            )
        end
        if vars.PriceGlobalValue ~= nil then
            runtime.pricing.globalValue = math.floor(tonumber(vars.PriceGlobalValue) or 0)
        end
        if vars.PriceContrastPercent ~= nil then
            local percent = math.floor(tonumber(vars.PriceContrastPercent) or 0)
            percent = math.max(0, math.min(50, percent))
            runtime.pricing.contrastPercent = percent
            runtime.pricing.contrastStrength = percent / 100.0
        elseif vars.PriceContrastStrength ~= nil then
            runtime.pricing.contrastStrength = math.max(0,
                math.min(0.50, tonumber(vars.PriceContrastStrength) or 0))
            runtime.pricing.contrastPercent = math.floor(
                (runtime.pricing.contrastStrength * 100.0) + 0.5
            )
        end
        if vars.PriceVariationEnabled ~= nil then
            runtime.pricing.variationEnabled = vars.PriceVariationEnabled == true
                or vars.PriceVariationEnabled == 1
                or vars.PriceVariationEnabled == "true"
        end
        if vars.PriceVariationPercent ~= nil then
            local percent = math.floor(tonumber(vars.PriceVariationPercent) or 0)
            percent = math.max(0, math.min(50, percent))
            runtime.pricing.variationPercent = percent
            runtime.pricing.variationStrength = percent / 100.0
        elseif vars.PriceVariationStrength ~= nil then
            runtime.pricing.variationStrength = math.max(0,
                math.min(0.50, tonumber(vars.PriceVariationStrength) or 0))
            runtime.pricing.variationPercent = math.floor(
                (runtime.pricing.variationStrength * 100.0) + 0.5
            )
        end
        if vars.PriceVariationSalt ~= nil then
            runtime.pricing.variationSalt = math.floor(tonumber(vars.PriceVariationSalt) or 1)
        end
        if vars.PriceVariationAbsoluteOverrides ~= nil then
            runtime.pricing.variationAbsoluteOverrides = vars.PriceVariationAbsoluteOverrides == true
                or vars.PriceVariationAbsoluteOverrides == 1
                or vars.PriceVariationAbsoluteOverrides == "true"
        end
        if vars.StockMultiplier ~= nil then
            runtime.stock.globalMultiplier = vars.StockMultiplier
        end

        local vesselPricing = runtime.vesselPricing or {}
        if vars.PriceVesselEnabled ~= nil then
            vesselPricing.enabled = vars.PriceVesselEnabled == true
                or vars.PriceVesselEnabled == 1
                or vars.PriceVesselEnabled == "true"
        end
        local vesselValueKeys = {
            { option = "PriceVesselBaseValue", field = "baseValue", min = -100, max = 100 },
            { option = "PriceVesselCapacityValue", field = "capacityValue", min = 0, max = 100 },
            { option = "PriceVesselWeightPenalty", field = "weightPenalty", min = 0, max = 100 },
            { option = "PriceVesselOpenedPenalty", field = "openedPenalty", min = 0, max = 100 },
            { option = "PriceVesselSealedBonus", field = "sealedBonus", min = -100, max = 100 },
            { option = "PriceVesselRetainedBonus", field = "retainedBonus", min = -100, max = 100 },
        }
        for _, entry in ipairs(vesselValueKeys) do
            if vars[entry.option] ~= nil then
                local value = math.floor(tonumber(vars[entry.option]) or 0)
                vesselPricing[entry.field] = math.max(entry.min, math.min(entry.max, value))
            end
        end
        runtime.vesselPricing = vesselPricing

        local bandKeys = {
            { category = "Food", min = "PriceCategoryFoodMin", max = "PriceCategoryFoodMax" },
            { category = "Beverage", min = "PriceCategoryBeverageMin", max = "PriceCategoryBeverageMax" },
            { category = "Liquid", min = "PriceCategoryLiquidMin", max = "PriceCategoryLiquidMax" },
            { category = "Weapon", min = "PriceCategoryWeaponMin", max = "PriceCategoryWeaponMax" },
            { category = "Medical", min = "PriceCategoryMedicalMin", max = "PriceCategoryMedicalMax" },
            { category = "Tool", min = "PriceCategoryToolMin", max = "PriceCategoryToolMax" },
            { category = "Container", min = "PriceCategoryContainerMin", max = "PriceCategoryContainerMax" },
            { category = "Clothing", min = "PriceCategoryClothingMin", max = "PriceCategoryClothingMax" },
            { category = "Electronics", min = "PriceCategoryElectronicsMin", max = "PriceCategoryElectronicsMax" },
            { category = "Literature", min = "PriceCategoryLiteratureMin", max = "PriceCategoryLiteratureMax" },
            { category = "Resource", min = "PriceCategoryResourceMin", max = "PriceCategoryResourceMax" },
            { category = "Building", min = "PriceCategoryBuildingMin", max = "PriceCategoryBuildingMax" },
            { category = "Misc", min = "PriceCategoryMiscMin", max = "PriceCategoryMiscMax" },
        }
        for _, entry in ipairs(bandKeys) do
            local band = runtime.pricing.categoryBands[entry.category]
                or { min = 1, max = 1, response = 1, exponent = 0.85 }
            if vars[entry.min] ~= nil then
                band.min = math.max(0, math.floor(tonumber(vars[entry.min]) or band.min))
            end
            if vars[entry.max] ~= nil then
                band.max = math.max(band.min, math.floor(tonumber(vars[entry.max]) or band.max))
            end
            runtime.pricing.categoryBands[entry.category] = band
        end

        -- Food descriptor thresholds are kept with food pricing so the
        -- classifier and the pricing/export diagnostics use one source of
        -- truth. Sandbox values override the exported defaults at reload.
        local foodPricing = runtime.foodPricing or {}
        local thresholdKeys = {
            { option = "PriceThemeHighCalorieThreshold", field = "highCalorieThreshold" },
            { option = "PriceThemeHighFatThreshold", field = "highFatThreshold" },
            { option = "PriceThemeHighProteinThreshold", field = "highProteinThreshold" },
            { option = "PriceThemeHighCarbohydrateThreshold", field = "highCarbohydrateThreshold" },
            { option = "PriceThemeHydrationThreshold", field = "hydrationThreshold" },
            { option = "PriceThemeThirstThreshold", field = "thirstThreshold" },
        }
        for _, entry in ipairs(thresholdKeys) do
            if vars[entry.option] ~= nil then
                local value = tonumber(vars[entry.option])
                if value ~= nil then
                    foodPricing[entry.field] = math.max(0, value)
                end
            end
        end
        local foodMultiplierKeys = {
            { option = "PriceFoodOpenedMultiplierPercent", field = "openedPenalty", min = 0, max = 150 },
            { option = "PriceFoodSealedPreservationPercent", field = "sealedPreservationMultiplier", min = 0, max = 200 },
        }
        for _, entry in ipairs(foodMultiplierKeys) do
            if vars[entry.option] ~= nil then
                local percent = math.floor(tonumber(vars[entry.option]) or 0)
                percent = math.max(entry.min, math.min(entry.max, percent))
                foodPricing[entry.field] = percent / 100.0
            end
        end
        runtime.foodPricing = foodPricing

        -- Seasonal clothing thresholds use the same exported pricing table
        -- as the classifier. Missing protection metadata remains unavailable
        -- and therefore never qualifies by numeric threshold alone.
        local clothingPricing = runtime.clothingPricing or {}
        local clothingThresholdKeys = {
            { option = "PriceThemeSummerMaxInsulation", field = "summerMaxInsulation" },
            { option = "PriceThemeSummerMaxWindResistance", field = "summerMaxWindResistance" },
            { option = "PriceThemeWinterMinInsulation", field = "winterMinInsulation" },
            { option = "PriceThemeWinterMinWindResistance", field = "winterMinWindResistance" },
            { option = "PriceThemeRainMinWaterResistance", field = "rainMinWaterResistance" },
        }
        for _, entry in ipairs(clothingThresholdKeys) do
            if vars[entry.option] ~= nil then
                local value = tonumber(vars[entry.option])
                if value ~= nil then
                    clothingPricing[entry.field] = math.max(0, value)
                end
            end
        end
        runtime.clothingPricing = clothingPricing
        runtime.stock.categoryMultipliers = nil
    else
        runtime.sandboxVars = nil
    end
    runtime.pricingRevision = (tonumber(runtime.pricingRevision) or 0) + 1
end

-- getSandboxTagMultiplier resolves multiplicative stock values. Price tag
-- additions are now owned by MS_MarketModifiers so they cannot be applied twice.
-- for a list of tags. Flat tokens are expanded using TOKEN_PARENTS from MS_TagMapper;
-- dot-notation descriptor tags (Rarity.*, Quality.*, Origin.*, Theme.*) keep path-walking.
function runtime.getSandboxTagMultiplier(mode, tags)
    if mode ~= "Stock" then return 0 end
    if not tags then return 1.0 end

    local vars = runtime.sandboxVars or getSandboxVarsTable()
    local tagList = type(tags) == "table" and tags or { tags }
    local totalMult = 1.0

    -- Resolve a single flat-or-dotted stock key against sandbox vars.
    local function accumulate(key)
        local optKey = "Stock" .. key:gsub("%.", "") .. "Mult"
        local mult = vars and vars[optKey]
        if type(mult) == "number" then
            totalMult = totalMult * mult
        end
    end

    for _, tag in ipairs(tagList) do
        local isDotted = string.find(tag, ".", 1, true) ~= nil
        if isDotted then
            -- Descriptor tag (Rarity.Rare, Quality.Luxury, etc.) — walk dot-path
            local path = ""
            for part in string.gmatch(tag, "[^%.]+") do
                path = path .. (path == "" and "" or ".") .. part
                accumulate(path)
            end
        else
            -- Flat token — accumulate the token itself, then expand via TOKEN_PARENTS
            accumulate(tag)
            local TagMapper = MarketSense.TagMapper
            if TagMapper and TagMapper.getParents then
                for _, parent in ipairs(TagMapper.getParents(tag)) do
                    accumulate(parent)
                end
            end
        end
    end

    return totalMult
end

MarketSense.Config.reloadExported()
MarketSense.Config.applySandboxOptions()

MarketSense.ItemRuntimeConfig = runtime
function MarketSense.IsItemRuntimeDebugEnabled()
    return MarketSense.ItemRuntimeConfig
        and MarketSense.ItemRuntimeConfig.debug == true
end

return runtime
