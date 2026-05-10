MarketSense = MarketSense or {}
MarketSense.Config = MarketSense.Config or {}

local rootConfig = MarketSense.Config
rootConfig.DynamicItemRuntime = rootConfig.DynamicItemRuntime or {}

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
        maxPrice = 1000000000,
        baseMultiplier = 1.0,
        openedPenalty = 0.72,
    },
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

local runtime = rootConfig.DynamicItemRuntime

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

local function getSandboxVarsTable()
    if SandboxVars and type(SandboxVars.MarketSense) == "table" then
        return SandboxVars.MarketSense
    end
    return nil
end

function MarketSense.Config.reloadExported()
    if package and package.loaded then
        package.loaded["DT/MarketSense/Pricing/MS_PricingConfig_Data"] = nil
    end

    local ok, exported = pcall(require, "DT/MarketSense/Pricing/MS_PricingConfig_Data")
    if ok and type(exported) == "table" then
        if exported.global then
            runtime.pricing.minPrice = exported.global.min_price or runtime.pricing.minPrice
            runtime.pricing.maxPrice = exported.global.max_price or runtime.pricing.maxPrice
            runtime.pricing.baseMultiplier = exported.global.base_multiplier or runtime.pricing.baseMultiplier
            runtime.pricing.openedPenalty = exported.global.opened_penalty or runtime.pricing.openedPenalty

            runtime.stock.ultralightMax = exported.global.stock_ultralight_max or runtime.stock.ultralightMax
            runtime.stock.lightMax = exported.global.stock_light_max or runtime.stock.lightMax
            runtime.stock.smallMax = exported.global.stock_small_max or runtime.stock.smallMax
            runtime.stock.mediumMax = exported.global.stock_medium_max or runtime.stock.mediumMax
            runtime.stock.heavyMax = exported.global.stock_heavy_max or runtime.stock.heavyMax
            runtime.stock.massiveMax = exported.global.stock_massive_max or runtime.stock.massiveMax
            runtime.stock.maxCap = exported.global.stock_max_cap or runtime.stock.maxCap
            runtime.stock.defaultMinRatio = exported.global.stock_default_min_ratio or runtime.stock.defaultMinRatio
        end
        runtime.categories = exported.categories or {}
        runtime.rarityAdditions = exported.rarity_additions or {}
        runtime.qualityAdditions = exported.quality_additions or {}
        runtime.themeAdditions = exported.theme_additions or {}
        runtime.originAdditions = exported.origin_additions or {}
        runtime.tagPriceAdditions = exported.tag_price_additions or {}
        runtime.global = exported.global or {}
    end
end

function MarketSense.Config.applySandboxOptions()
    local vars = getSandboxVarsTable()
    if vars then
        runtime.sandboxVars = vars
        runtime.pricing.baseMultiplier = vars.PriceMultiplier or runtime.pricing.baseMultiplier
        runtime.pricing.globalValue = vars.PriceGlobalValue or 0
        runtime.stock.globalMultiplier = vars.StockMultiplier or 1.0
        runtime.stock.categoryMultipliers = nil
    else
        runtime.sandboxVars = nil
    end
end

-- getSandboxTagMultiplier resolves additive (Price) or multiplicative (Stock) values
-- for a list of tags. Flat tokens are expanded using TOKEN_PARENTS from MS_TagMapper;
-- dot-notation descriptor tags (Rarity.*, Quality.*, Origin.*, Theme.*) keep path-walking.
function runtime.getSandboxTagMultiplier(mode, tags)
    if not tags then
        return mode == "Price" and 0 or 1.0
    end

    local vars = runtime.sandboxVars or getSandboxVarsTable()
    local tagList = type(tags) == "table" and tags or { tags }
    local totalMult = 1.0
    local totalAdd = 0

    -- Resolve a single flat-or-dotted key against sandbox vars and tagPriceAdditions
    local function accumulate(key)
        if mode == "Price" then
            local optKey = "Price" .. key:gsub("%.", "") .. "Value"
            local val = vars and vars[optKey]
            if val == nil then
                val = runtime.tagPriceAdditions and runtime.tagPriceAdditions[key]
            end
            if type(val) == "number" then
                totalAdd = totalAdd + val
            end
        else
            local optKey = "Stock" .. key:gsub("%.", "") .. "Mult"
            local mult = vars and vars[optKey]
            if type(mult) == "number" then
                totalMult = totalMult * mult
            end
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

    return mode == "Price" and totalAdd or totalMult
end

MarketSense.Config.reloadExported()
MarketSense.Config.applySandboxOptions()

MarketSense.ItemRuntimeConfig = runtime

-- DynamicTrading compatibility alias (for DT framework checks)
DynamicTrading = DynamicTrading or {}
DynamicTrading.ItemRuntimeConfig = MarketSense.ItemRuntimeConfig

function DynamicTrading.IsItemRuntimeDebugEnabled()
    return MarketSense.ItemRuntimeConfig
        and MarketSense.ItemRuntimeConfig.debug == true
end

return runtime
