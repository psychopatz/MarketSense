require "MarketSense/MS_Core"
require "MarketSense/MS_PropertyReader_Signals"

MarketSense = MarketSense or {}

local Core = MarketSense.Core
local Signals = require "MarketSense/MS_PropertyReader_Signals"
local readNumber = Signals.readNumber
local readFluidCategories = Signals.readFluidCategories

local function read(target)
    local fluidContainer = Core.safeCall(target, "getFluidContainer", nil)
    local fluidType = ""
    local fluidCategory = ""
    local fluidTypeString = ""
    local fluidContainerName = ""
    local fluidCategories = {}
    local fluidAmount = 0
    local fluidCapacity = 0
    local fluidPrimaryAmount = 0
    local fluidFilledRatio = 0
    local fluidIsEmpty = true
    local fluidIsMixture = false
    local fluid = nil
    if fluidContainer then
        fluidContainerName = Core.safeString(fluidContainer, "getContainerName", "")
        fluidAmount = math.max(0, readNumber(fluidContainer, "getAmount") or 0)
        fluidCapacity = math.max(0, readNumber(fluidContainer, "getCapacity") or 0)
        fluidPrimaryAmount = math.max(0, readNumber(fluidContainer, "getPrimaryFluidAmount") or 0)
        fluidFilledRatio = math.max(0, math.min(1,
            readNumber(fluidContainer, "getFilledRatio") or 0))
        fluid = Core.safeCall(fluidContainer, "getPrimaryFluid", nil)
        fluidIsEmpty = Core.safeBoolean(fluidContainer, "isEmpty", fluid == nil)
        fluidIsMixture = Core.safeBoolean(fluidContainer, "isMixture", false)
        if fluid then
            fluidType       = tostring(Core.safeCall(fluid, "getFluidType", ""))
            fluidTypeString = Core.safeString(fluid, "getFluidTypeString", "")
            fluidCategories = readFluidCategories(fluid)
        end
    end
    local fluidCategoriesLower = {}
    for _, category in ipairs(fluidCategories) do
        fluidCategoriesLower[#fluidCategoriesLower + 1] = Core.lower(category)
        if fluidCategory == "" then fluidCategory = tostring(category) end
    end
    local isActualLiquid = fluid ~= nil
        and ((fluidType ~= "") or (fluidTypeString ~= ""))

    return {
        fluidContainer = fluidContainer,
        fluidType = fluidType,
        fluidCategory = fluidCategory,
        fluidTypeString = fluidTypeString,
        fluidContainerName = fluidContainerName,
        fluidCategories = fluidCategories,
        fluidCategoriesLower = fluidCategoriesLower,
        fluidAmount = fluidAmount,
        fluidCapacity = fluidCapacity,
        fluidPrimaryAmount = fluidPrimaryAmount,
        fluidFilledRatio = fluidFilledRatio,
        fluidIsEmpty = fluidIsEmpty,
        fluidIsMixture = fluidIsMixture,
        fluid = fluid,
        isActualLiquid = isActualLiquid,
    }
end

return { read = read }

