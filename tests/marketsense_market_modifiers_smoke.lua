local T = require "tests/support/test"
T.addPackagePaths()

local Config = require "MarketSense/MS_Config"
local Modifiers = require "MarketSense/Pricing/MS_MarketModifiers"
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
}
local sandboxed = evaluate("Base.SandboxedFood", { "Rarity.Rare" })
T.equal(sandboxed, 50, "typed sandbox addition and multiplier apply once")
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
