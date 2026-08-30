require "MarketSense/MS_Config"
require "MarketSense/Pricing/MS_LiquidPricing"
require "MarketSense/Pricing/MS_ResourcePricing"
require "MarketSense/Pricing/MS_MiscPricing"
require "MarketSense/Pricing/MS_FoodPricing"
require "MarketSense/Pricing/MS_ContainerPricing"
require "MarketSense/Pricing/MS_ElectronicsPricing"
require "MarketSense/Pricing/MS_MedicalPricing"
require "MarketSense/Pricing/MS_BuildingPricing"
require "MarketSense/Pricing/MS_WeaponPricing"
require "MarketSense/Pricing/MS_LiteraturePricing"
require "MarketSense/Pricing/MS_ClothingPricing"
require "MarketSense/Pricing/MS_ToolRecipeDemand"
require "MarketSense/Pricing/MS_ToolPricing"
require "MarketSense/MS_Core"
require "MarketSense/Pricing/MS_PricingUtils"

MarketSense = MarketSense or {}
MarketSense.Pricing = MarketSense.Pricing or {}

local Pricing = MarketSense.Pricing
local Config = MarketSense.ItemRuntimeConfig
local Utils = require "MarketSense/Pricing/MS_PricingUtils"
local LiquidPricing = MarketSense.LiquidPricing
local ResourcePricing = MarketSense.ResourcePricing
local MiscPricing = MarketSense.MiscPricing
local FoodPricing = MarketSense.FoodPricing
local ContainerPricing = MarketSense.ContainerPricing
local ElectronicsPricing = MarketSense.ElectronicsPricing
local MedicalPricing = MarketSense.MedicalPricing
local BuildingPricing = MarketSense.BuildingPricing
local WeaponPricing = MarketSense.WeaponPricing
local LiteraturePricing = MarketSense.LiteraturePricing
local ClothingPricing = MarketSense.ClothingPricing
local ToolPricing = MarketSense.ToolPricing
local CATEGORY_BASE_SCORES = Utils.CATEGORY_BASE_SCORES
local isFoodCategory = Utils.isFoodCategory

function Pricing.calculateRawScore(ctx, details)
    ctx = ctx or {}
    details = details or {}
    local category = details.category or "Misc"
    local cc = Config.categories and Config.categories[category] or {}
    local base = cc.base or CATEGORY_BASE_SCORES[category] or CATEGORY_BASE_SCORES.Misc
    local weightPenalty = (ctx.weight or 0) * (cc.weight_penalty or 2.4)
    local score

    if isFoodCategory(category) then
        score = FoodPricing.calculate(ctx, details)
    elseif category == "Liquid" then
        score = LiquidPricing.calculate(ctx, details)
    elseif category == "Medical" then
        score = MedicalPricing.calculate(ctx, details)
    elseif category == "Building" then
        score = BuildingPricing.calculate(ctx, details)
    elseif category == "Weapon" then
        score = WeaponPricing.calculate(ctx, details)
    elseif category == "Literature" then
        score = LiteraturePricing.calculate(ctx, details)
    elseif category == "Tool" then
        score = ToolPricing.calculate(ctx, details)
    elseif category == "Container" then
        score = ContainerPricing.calculate(ctx, details)
    elseif category == "Clothing" then
        score = ClothingPricing.calculate(ctx, details)
    elseif category == "Electronics" then
        score = ElectronicsPricing.calculate(ctx, details)
    elseif category == "Resource" then
        score = ResourcePricing.calculate(ctx, details)
    elseif category == "Misc" then
        score, details.priceHeuristic = MiscPricing.calculate(ctx, details, base)
    else
        score = base - weightPenalty
    end

    return math.max(score, Config.pricing.minPrice or 1)
end

return Pricing
