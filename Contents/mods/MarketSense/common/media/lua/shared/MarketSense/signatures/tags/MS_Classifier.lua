-- MS_Classifier.lua
-- Thin pipeline orchestrator. Requires all individual tag signature files and
-- runs them in order, returning the first matched result.
-- Add new signatures here to extend coverage.

require "MarketSense/signatures/tags/MS_TagMapper"
require "MarketSense/signatures/tags/MS_Sig_StaticOverride"
require "MarketSense/signatures/tags/MS_Sig_Smoking"
require "MarketSense/signatures/tags/MS_Sig_Cooking"
require "MarketSense/signatures/tags/MS_Sig_Material"
require "MarketSense/signatures/tags/MS_Sig_Ammo"
require "MarketSense/signatures/tags/MS_Sig_Apparel"
require "MarketSense/signatures/tags/MS_Sig_Container"
require "MarketSense/signatures/tags/MS_Sig_Electronics"
require "MarketSense/signatures/tags/MS_Sig_Building"
require "MarketSense/signatures/tags/MS_Sig_Gardening"
require "MarketSense/signatures/tags/MS_Sig_Literature"
require "MarketSense/signatures/tags/MS_Sig_Tool"
require "MarketSense/signatures/tags/MS_Sig_Weapon"
require "MarketSense/signatures/tags/MS_Sig_Memento"
require "MarketSense/signatures/tags/MS_Sig_BoxesAndStacks"
require "MarketSense/signatures/tags/MS_Sig_CategoryOverride"
require "MarketSense/signatures/tags/MS_Sig_Medical"
require "MarketSense/signatures/tags/MS_Sig_Food"
require "MarketSense/signatures/tags/MS_Sig_Beverage"
require "MarketSense/signatures/tags/MS_RootArbiter"

MarketSense = MarketSense or {}
MarketSense.Classifier = MarketSense.Classifier or {}

local Classifier = MarketSense.Classifier

-- Root-specific pipelines keep broad signatures from stealing another root's
-- obvious stock, while preserving each category's own leaf classifier.
local ROOT_PIPELINES = {
    Food = {
        "Beverage",
        "Food",
        "BoxesAndStacks",
        "CategoryOverride",
    },
    Resource = {
        "Material",
        "BoxesAndStacks",
        "CategoryOverride",
    },
    Weapon = {
        "Ammo",
        "Weapon",
        "BoxesAndStacks",
        "CategoryOverride",
    },
    Container = {
        "Container",
        "BoxesAndStacks",
        "CategoryOverride",
    },
    Clothing = {
        "Apparel",
        "CategoryOverride",
    },
    Medical = {
        "Medical",
        "Food",
        "CategoryOverride",
    },
    Electronics = {
        "Electronics",
        "CategoryOverride",
    },
    Literature = {
        "Literature",
        "CategoryOverride",
    },
    Building = {
        "Gardening",
        "Building",
        "CategoryOverride",
    },
    Tool = {
        "Smoking",
        "Cooking",
        "Tool",
        "BoxesAndStacks",
        "CategoryOverride",
    },
    Misc = {
        "Memento",
        "CategoryOverride",
    },
}

local FALLBACK_PIPELINE = {
    "Material",
    "Ammo",
    "Medical",
    "Beverage",
    "Food",
    "Literature",
    "Apparel",
    "Weapon",
    "Smoking",
    "Cooking",
    "Tool",
    "Container",
    "Gardening",
    "Memento",
    "BoxesAndStacks",
    "CategoryOverride",
}

local function runPipeline(ctx, pipeline, rootDecision)
    for _, name in ipairs(pipeline or {}) do
        local sig = MarketSense.Signatures[name]
        if sig and type(sig.match) == "function" then
            local ok, result = pcall(sig.match, ctx)
            if ok and result and result.matched then
                result.signature = name
                result.rootDecision = rootDecision
                return result
            end
        end
    end
    return nil
end

function Classifier.classify(ctx)
    if not ctx then return nil end

    local rootDecision = MarketSense.RootArbiter and MarketSense.RootArbiter.resolve(ctx) or nil
    if rootDecision and rootDecision.result and rootDecision.result.matched then
        rootDecision.result.signature = "StaticOverride"
        rootDecision.result.rootDecision = rootDecision
        return rootDecision.result
    end

    local root = rootDecision and rootDecision.root or nil
    local result = runPipeline(ctx, ROOT_PIPELINES[root], rootDecision)
    if result then
        return result
    end

    result = runPipeline(ctx, FALLBACK_PIPELINE, rootDecision)
    if result then
        return result
    end

    local categoryToken = root and MarketSense.TagMapper and MarketSense.TagMapper.isKnown(root) and root or nil
    if categoryToken and MarketSense.TagMapper then
        local fallback = MarketSense.TagMapper.makeResult(categoryToken, 0.20, {
            source = rootDecision and rootDecision.source or "root_fallback",
            stage = "root_generic",
        })
        if fallback then
            fallback.signature = "RootArbiter"
            fallback.rootDecision = rootDecision
            return fallback
        end
    end

    return nil
end

return Classifier
