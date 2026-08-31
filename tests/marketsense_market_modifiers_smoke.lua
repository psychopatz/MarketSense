local T = require "tests/support/test"
T.addPackagePaths()

local Config = require "MarketSense/MS_Config"
local Modifiers = require "MarketSense/Pricing/MS_MarketModifiers"
local TransformPricing = require "MarketSense/Pricing/MS_TransformPricing"
local DB = require "MarketSense/MS_HeuristicsDB"
local Cache = require "MarketSense/MS_RuntimeCache"

local pricing = MarketSense.ItemRuntimeConfig.pricing
pricing.variationEnabled = true
pricing.variationStrength = 0.10
pricing.contrastStrength = 0
pricing.variationSalt = 7
Config.sandboxVars = nil

WorldGenParams = {
    INSTANCE = {
        getSeedString = function() return "marketsense-seed-a" end,
    },
}

local function evaluate(fullType, tags, yieldStatus)
    local audit = {}
    local details = {
        fullType = fullType,
        category = "Food",
        tags = tags or { "FoodStaple" },
        expandedTags = tags or { "FoodStaple" },
        priceHeuristic = { anchor = 10, stateFactor = 1 },
        yieldResolution = yieldStatus and { status = yieldStatus } or nil,
    }
    local value, summary = Modifiers.apply({
        fullType = fullType,
        moduleName = "Base",
    }, details, 20, audit)
    return value, summary, audit
end

local first, firstSummary, firstAudit = evaluate("Base.SeededFood")
local second, secondSummary = evaluate("Base.SeededFood")
T.equal(first, second, "same save seed and item id produce the same variation")
T.equal(firstSummary.variationMultiplier, secondSummary.variationMultiplier,
    "variation multiplier is stable")
T.truthy(firstSummary.variationSource == "WorldGenParams.seedString",
    "variation reports the authoritative world seed source")
T.truthy(#firstAudit > 0, "modifier decisions are auditable")

WorldGenParams.INSTANCE.getSeedString = function() return "marketsense-seed-b" end
local differentSeed = evaluate("Base.SeededFood")
T.truthy(differentSeed ~= first, "changing the save seed changes the stable distribution")

pricing.variationEnabled = false
local noVariation = evaluate("Base.NoVariation")
T.equal(noVariation, 20, "variation can be disabled without changing the raw score")

Config.sandboxVars = {
    PriceRarityRareValue = 5,
    PriceRarityRareMult = 2,
    PriceThemeSwimwearValue = 7,
    PriceThemeSwimwearMult = 1.5,
}
local sandboxed = evaluate("Base.SandboxedFood", { "Rarity.Rare" })
T.equal(sandboxed, 50, "typed sandbox addition and multiplier apply once")
local seasonalSandboxed = evaluate("Base.SeasonalSwimwear", { "Theme.Swimwear" })
T.equal(seasonalSandboxed, 40.5,
    "new seasonal theme sandbox addition and multiplier apply")
Config.sandboxVars = nil

DB.registerItem("Base.ExactModifierTest", { price = 77, reason = "test exact" })
local exact, exactSummary = evaluate("Base.ExactModifierTest")
T.equal(exact, 20, "modifier layer leaves finalization of exact overrides to the balance path")
T.equal(exactSummary.overridePrice, 77, "exact override metadata is preserved")
T.truthy(exactSummary.absoluteOverride, "exact override is identified")
pricing.variationAbsoluteOverrides = true
pricing.variationEnabled = true
local variedExact, variedExactSummary = evaluate("Base.ExactModifierTest")
T.equal(variedExact, 20, "exact override still waits for balance finalization")
T.truthy(variedExactSummary.overridePrice ~= 77,
    "exact override variation is opt-in")
pricing.variationAbsoluteOverrides = false

-- A transform child contributes mechanical value only.  The package applies
-- its own semantic identity after the child is aggregated, so rarity/theme
-- additions must not leak into this intermediate score.
pricing.variationEnabled = false
local rawChildDetails = {
    fullType = "Base.RawChild",
    category = "Building",
    primary = "BuildingSurvivalTent",
    tags = { "BuildingSurvivalTent", "Rarity.Common", "Theme.Survival" },
    expandedTags = { "Building", "BuildingSurvival", "BuildingSurvivalTent",
        "Rarity.Common", "Theme.Survival" },
    priceHeuristic = { anchor = 10, stateFactor = 1 },
}
local rawChild, rawChildSummary = Modifiers.apply(
    { fullType = "Base.RawChild", moduleName = "Base" },
    rawChildDetails, 20, nil, true, { rawOnly = true }
)
T.equal(rawChild, 20, "raw-only transform child keeps mechanical score")
T.equal(rawChildSummary.tagAdd, 0, "raw-only child skips semantic tag additions")
T.equal(rawChildSummary.categoryAdd, 0, "raw-only child skips category additions")
T.truthy(rawChildSummary.rawOnly, "raw-only child stage is visible in the audit summary")

-- Verify the transform evaluator uses that intermediate stage, rather than
-- merely exposing an unused option on the modifier module.
local previousPricing = MarketSense.Pricing
local previousReader = MarketSense.PropertyReader
MarketSense.Pricing = {
    calculateDetails = function()
        return {
            rawScore = 20,
            category = "Building",
            primary = "BuildingSurvivalTent",
            tags = { "BuildingSurvivalTent", "Rarity.Common", "Theme.Survival" },
            expandedTags = { "Building", "BuildingSurvival", "BuildingSurvivalTent",
                "Rarity.Common", "Theme.Survival" },
            priceHeuristic = { model = "building_v2", anchor = 12 },
        }
    end,
}
MarketSense.PropertyReader = {
    buildContext = function(fullType)
        return { fullType = fullType, item = {} }
    end,
}
local transformed, transformedSummary = TransformPricing.evaluate(
    { fullType = "Base.RawBundle" },
    {
        yieldResolution = {
            status = "resolved",
            outputs = {
                { fullType = "Base.RawChild", quantity = 1, chance = 1, resolution = "exact" },
            },
        },
    },
    {}
)
MarketSense.Pricing = previousPricing
MarketSense.PropertyReader = previousReader
T.equal(transformed, 20, "transform evaluator aggregates raw child value")
T.equal(transformedSummary.contributions[1].unitPricingStage, "raw_mechanical",
    "transform audit identifies the raw mechanical child stage")

pricing.variationEnabled = true
local bundle, bundleSummary = evaluate("Base.AggregateBundle", nil, "resolved")
T.equal(bundleSummary.variationScope, "aggregate",
    "yield-derived items receive one aggregate variation scope")
T.truthy(bundle ~= 20, "aggregate bundle still receives deterministic variation")

Cache.clear()
Cache.setDetails("Base.CacheRevisionTest", { price = 12 })
local revision = MarketSense.ItemRuntimeConfig.pricingRevision
MarketSense.ItemRuntimeConfig.pricingRevision = revision + 1
T.falsy(Cache.getDetails("Base.CacheRevisionTest"),
    "sandbox pricing revision invalidates cached details")
MarketSense.ItemRuntimeConfig.pricingRevision = revision

T.finish("marketsense_market_modifiers_smoke")
