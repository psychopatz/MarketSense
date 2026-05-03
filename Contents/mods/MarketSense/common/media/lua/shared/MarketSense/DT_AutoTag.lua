require "MarketSense/DT_PropertyReader"
require "MarketSense/DT_TagUtils"
require "MarketSense/DT_HeuristicsDB"

DynamicTrading = DynamicTrading or {}
DynamicTrading.AutoTag = DynamicTrading.AutoTag or {}
DynamicTrading.Signatures = DynamicTrading.Signatures or {}

local AutoTag = DynamicTrading.AutoTag
local Core = DynamicTrading.Core
local TagUtils = DynamicTrading.TagUtils
local DB = DynamicTrading.HeuristicsDB

local ORDER = {
    "Fishing",
    "Medical",
    "Weapon",
    "Food",
    "Container",
    "Clothing",
    "Electronics",
    "Tool",
    "Resource",
    "Literature",
    "Building",
}

local function addTag(tags, tag)
    if tag and tag ~= "" and not TagUtils.hasTag(tags, tag) then
        tags[#tags + 1] = tag
    end
end

local function addDescriptorTags(ctx, result)
    local tags = TagUtils.unique(result.tags or {})

    if not TagUtils.tagStarts(tags, "Origin") then
        if ctx.moduleName == "Base" then
            addTag(tags, "Origin.Vanilla")
        else
            -- Ensure modId is clean (no spaces/dots) for tagging
            local cleanId = ctx.sourceModId or "Modded"
            cleanId = cleanId:gsub("[%s%.]", "")
            addTag(tags, "Origin." .. cleanId)
        end
    end

    if not TagUtils.tagStarts(tags, "Rarity") then
        if Core.ctxContains(ctx, { "legendary", "artifact" }) then
            addTag(tags, "Rarity.Legendary")
        elseif Core.ctxContains(ctx, { "katana", "machete", "generator", "military", "diamond", "gold" }) then
            addTag(tags, "Rarity.Rare")
        elseif Core.ctxContains(ctx, { "pistol", "rifle", "shotgun", "revolver", "backpack", "radio", "walkie", "medical" }) then
            addTag(tags, "Rarity.Uncommon")
        else
            addTag(tags, "Rarity.Common")
        end
    end

    if not TagUtils.tagStarts(tags, "Quality") then
        if Core.ctxContains(ctx, { "broken", "trash", "junk", "worn" }) then
            addTag(tags, "Quality.Waste")
        elseif Core.ctxContains(ctx, { "gold", "diamond", "luxury", "premium", "whiskey", "wine" }) then
            addTag(tags, "Quality.Luxury")
        elseif Core.ctxContains(ctx, { "sterile" }) and not Core.ctxContains(ctx, { "unsterile" }) then
            addTag(tags, "Quality.Sterile")
        else
            addTag(tags, "Quality.Standard")
        end
    end

    result.tags = TagUtils.unique(tags)
    result.expandedTags = TagUtils.expandHierarchy(result.tags)
    return result
end

function AutoTag.fallback(ctx)
    return TagUtils.normalizeResult({
        matched = false,
        confidence = 0.05,
        category = "Misc",
        primary = "Misc.General",
        tags = {
            "Misc.General"
        },
        details = {
            reason = "No signature matched."
        }
    })
end

function AutoTag.compareSignatures(fullTypeOrContext)
    local ctx = type(fullTypeOrContext) == "table" and fullTypeOrContext.fullType
        and fullTypeOrContext or DynamicTrading.PropertyReader.buildContext(fullTypeOrContext)

    local best = nil
    local results = {}

    for _, name in ipairs(ORDER) do
        local signature = DynamicTrading.Signatures[name]
        if signature and type(signature.match) == "function" then
            local ok, rawResult = pcall(signature.match, ctx)
            local result = ok and TagUtils.normalizeResult(rawResult) or {
                matched = false,
                confidence = 0,
                category = "Misc",
                primary = "Misc.General",
                tags = { "Misc.General" },
                expandedTags = { "Misc.General", "Misc" },
                details = {
                    error = ok and nil or tostring(rawResult)
                }
            }

            result.signature = name
            results[#results + 1] = result

            if result.matched and (not best or result.confidence > best.confidence) then
                best = result
            end
        end
    end

    return {
        ctx = ctx,
        best = best,
        results = results,
    }
end

function AutoTag.generate(fullTypeOrContext)
    local ctx = type(fullTypeOrContext) == "table" and fullTypeOrContext.fullType
        and fullTypeOrContext or DynamicTrading.PropertyReader.buildContext(fullTypeOrContext)

    local itemOverride = DB.getItem(ctx.fullType)
    if itemOverride and type(itemOverride.tags) == "table" and #itemOverride.tags > 0 then
        return addDescriptorTags(ctx, TagUtils.normalizeResult({
            matched = true,
            confidence = 1,
            category = TagUtils.categoryFromPrimary(itemOverride.tags[1]),
            primary = itemOverride.tags[1],
            tags = itemOverride.tags,
            details = {
                source = "item_override"
            }
        }))
    end

    local comparison = AutoTag.compareSignatures(ctx)
    local best = comparison.best or AutoTag.fallback(ctx)
    return addDescriptorTags(ctx, TagUtils.normalizeResult(best))
end

return AutoTag
