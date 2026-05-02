DynamicTrading = DynamicTrading or {}
DynamicTrading.Config = DynamicTrading.Config or {}

local rootConfig = DynamicTrading.Config
rootConfig.DynamicItemRuntime = rootConfig.DynamicItemRuntime or {}

local defaults = {
    debug = false,
    server = {
        buildCatalogOnBoot = false,
        allowLazyGeneration = true,
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

DynamicTrading.ItemRuntimeConfig = runtime

function DynamicTrading.IsItemRuntimeDebugEnabled()
    return DynamicTrading.ItemRuntimeConfig
        and DynamicTrading.ItemRuntimeConfig.debug == true
end

return runtime
