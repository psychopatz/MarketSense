require "MarketSense/MS_PropertyReader"
require "MarketSense/MS_TagUtils"
require "MarketSense/MS_HeuristicsDB"
require "MarketSense/signatures/tags/MS_TagMapper"
require "MarketSense/signatures/tags/MS_WeaponEvidence"
require "MarketSense/signatures/tags/MS_Classifier"
require "MarketSense/signatures/tags/MS_PostLabelResolver"
require "MarketSense/signatures/TagFilters/MS_filter_Quality"
require "MarketSense/signatures/TagFilters/MS_filter_Origin"
require "MarketSense/signatures/TagFilters/MS_filter_Rarity"
require "MarketSense/signatures/TagFilters/MS_filter_Theme"

MarketSense = MarketSense or {}
MarketSense.AutoTag = MarketSense.AutoTag or {}

local AutoTag    = MarketSense.AutoTag
local TagUtils   = MarketSense.TagUtils
local DB         = MarketSense.HeuristicsDB
local Classifier = MarketSense.Classifier
local PostLabelResolver = MarketSense.PostLabelResolver
local WeaponEvidence = MarketSense.WeaponEvidence

local function annotateWeaponEvidence(ctx, result)
    if WeaponEvidence and WeaponEvidence.annotate then
        return WeaponEvidence.annotate(ctx, result)
    end
    return result
end

local function addDescriptorTags(ctx, result)
    MarketSense.Filters.Quality.apply(ctx, result)
    MarketSense.Filters.Origin.apply(ctx, result)
    MarketSense.Filters.Rarity.apply(ctx, result)
    MarketSense.Filters.Theme.apply(ctx, result)

    result.tags         = TagUtils.unique(result.tags or {})
    result.expandedTags = TagUtils.expandHierarchy(result.tags)
    return result
end

function AutoTag.fallback(ctx)
    return TagUtils.normalizeResult({
        matched    = false,
        confidence = 0.05,
        category   = "Misc",
        primary    = "Misc",
        tags       = { "Misc" },
        details    = { reason = "No classifier matched." },
    })
end

function AutoTag.generate(fullTypeOrContext)
    local ctx = type(fullTypeOrContext) == "table" and fullTypeOrContext.fullType
        and fullTypeOrContext or MarketSense.PropertyReader.buildContext(fullTypeOrContext)

    -- 1. Per-item override in HeuristicsDB
    local itemOverride = DB.getItem(ctx.fullType)
    if itemOverride and type(itemOverride.tags) == "table" and #itemOverride.tags > 0 then
        return addDescriptorTags(ctx, annotateWeaponEvidence(ctx, TagUtils.normalizeResult({
            matched    = true,
            confidence = 1,
            category   = TagUtils.categoryFromPrimary(itemOverride.tags[1]),
            primary    = itemOverride.tags[1],
            tags       = itemOverride.tags,
            details    = { source = "item_override" },
        })))
    end

    -- 2. Classifier pipeline
    local clsResult = Classifier.classify(ctx)
    if clsResult and clsResult.matched then
        local normalized = TagUtils.normalizeResult(clsResult)
        if PostLabelResolver and type(PostLabelResolver.correct) == "function" then
            normalized = TagUtils.normalizeResult(PostLabelResolver.correct(ctx, normalized))
        end
        return addDescriptorTags(ctx, annotateWeaponEvidence(ctx, normalized))
    end

    -- 3. Fallback
    return addDescriptorTags(ctx, annotateWeaponEvidence(ctx, AutoTag.fallback(ctx)))
end

-- Compare all signatures (used by debug tools)
function AutoTag.compareSignatures(ctx)
    local results = {}
    for name, sig in pairs(MarketSense.Signatures or {}) do
        if type(sig.match) == "function" then
            local ok, r = pcall(sig.match, ctx)
            results[#results + 1] = {
                name = name,
                matched = ok and r and r.matched or false,
                confidence = ok and r and r.confidence or 0,
                result = ok and r or nil,
            }
        end
    end
    return { results = results }
end

return AutoTag
