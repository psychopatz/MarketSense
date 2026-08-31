require "MarketSense/MS_Config"
require "MarketSense/MS_Core"
require "MarketSense/MS_TagUtils"
require "MarketSense/MS_Stock"
require "MarketSense/signatures/tags/MS_TagMapper"
require "MarketSense/ItemsRegistry/MS_ItemsRegistry_Text"

MarketSense = MarketSense or {}
local Domain = {}
local Core = MarketSense.Core
local TagUtils = MarketSense.TagUtils
local Pricing = MarketSense.Pricing
local Stock = MarketSense.Stock
local Config = MarketSense.ItemRuntimeConfig
local Mapping = MarketSense.TagMapper
local Text = require "MarketSense/ItemsRegistry/MS_ItemsRegistry_Text"

Domain.CATEGORY_ORDER = {
    Food = 1,
    Weapon = 2,
    Resource = 3,
    Tool = 4,
    Container = 5,
    Clothing = 6,
    Medical = 7,
    Electronics = 8,
    Literature = 9,
    Building = 10,
    Misc = 11,
}

Domain.DESCRIPTOR_ROOTS = {
    Origin = true,
    Quality = true,
    Rarity = true,
    Theme = true,
}

function Domain.getPrimaryTag(tags)
    for _, tag in ipairs(tags or {}) do
        local root = string.match(tostring(tag), "^([^%.]+)")
        if root and not Domain.DESCRIPTOR_ROOTS[root] then
            return tag
        end
    end
    return tostring(tags and tags[1] or "Misc")
end

function Domain.getBasePrice(ctx, tagInfo)
    local catalogPrice = Pricing.calculateCatalogPrice
        and Pricing.calculateCatalogPrice(ctx, tagInfo, false) or nil
    if catalogPrice ~= nil then
        return math.max(Config.pricing.minPrice or 1, Core.round(catalogPrice))
    end
    local rawScore = Pricing.calculateRawScore(ctx, tagInfo)
    return math.max(Config.pricing.minPrice or 1, Core.round(Core.priceClamp(rawScore)))
end

function Domain.getBaseStock(ctx)
    local maxValue = math.max(0, tonumber(Stock.baseMaxForWeight(ctx and ctx.weight or 0)) or 0)
    local minRatio = tonumber(Config.stock.defaultMinRatio) or 0.2
    local minValue = math.floor(maxValue * minRatio)
    return {
        min = math.max(0, minValue),
        max = maxValue,
    }
end

function Domain.shouldSkipSyntheticContext(ctx)
    if type(ctx) ~= "table" then
        return false, nil
    end

    local fullType = tostring(ctx.fullType or "")
    local itemLower = tostring(ctx.idLower or "")
    local displayCategory = tostring(ctx.displayCategoryLower or "")
    local bodyLocation = tostring(ctx.bodyLocationLower or "")

    if string.sub(fullType, 1, 12) == "Base.ZedDmg_" or string.sub(itemLower, 1, 7) == "zeddmg_" then
        return true, "zeddmg"
    end
    if displayCategory == "zeddmg" then
        return true, "display:zeddmg"
    end
    if bodyLocation == "base:zeddmg" or bodyLocation == "base:wound" or bodyLocation == "base:bandage" then
        return true, "body_location"
    end
    if not ctx.instanceCreated and (ctx.isFoodInstance or ctx.isFluidContainer) then
        return true, "missing_instance"
    end

    return false, nil
end

function Domain.toFileEntry(primary, tags)
    local definition = Mapping.getDefinition(primary or Domain.getPrimaryTag(tags))
    return {
        category = definition.root,
        subcategory = definition.subcategory,
        leaf = definition.leaf,
        root = definition.root,
        primaryPrefix = definition.primaryPrefix,
        path = definition.path,
    }
end

function Domain.buildSourceManifestHash(itemsByFullType, activeState)
    local parts = {}

    for fullType, entry in pairs(itemsByFullType or {}) do
        local stockRange = entry and entry.stockRange or {}
        parts[#parts + 1] = table.concat({
            tostring(fullType or ""),
            tostring(entry and entry.origin or ""),
            tostring(entry and entry.primary or ""),
            tostring(entry and entry.basePrice or ""),
            tostring(stockRange and stockRange.min or ""),
            tostring(stockRange and stockRange.max or ""),
            Text.join(entry and entry.tags or {}, "|"),
        }, "|")
    end

    table.sort(parts)

    if activeState and activeState.gameVersion then
        parts[#parts + 1] = "game|" .. tostring(activeState.gameVersion)
    end

    if activeState and activeState.activeModsHash then
        parts[#parts + 1] = "mods|" .. tostring(activeState.activeModsHash)
    end

    return Text.stableHash(parts)
end

return Domain
