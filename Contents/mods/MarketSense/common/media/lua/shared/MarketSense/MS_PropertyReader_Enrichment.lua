require "MarketSense/MS_WorldObjectEvidence"
require "MarketSense/MS_ItemCapabilities"

MarketSense = MarketSense or {}

local Enrichment = {}
local WorldObjectEvidence = MarketSense.WorldObjectEvidence
local ItemCapabilities = MarketSense.ItemCapabilities

function Enrichment.apply(context)
    -- WorldObjectSprite is the bridge between an item script and the actual
    -- placeable object. Read its PZ PropertyContainer once and derive a
    -- reusable capability record. These are interface facts only; they do
    -- not mutate the item's native PZ categories or pricing inputs.
    context.worldObjectEvidence = WorldObjectEvidence.read(context.worldObjectSprite)
    context.capabilities = ItemCapabilities.analyze(context)
    context.capabilitySet = context.capabilities.capabilitySet
    context.capabilityRequirements = context.capabilities.requirements
    context.capabilityRequirementSet = context.capabilities.requirementSet
    context.capabilityEvidence = context.capabilities.evidence
    return context
end

MarketSense.PropertyReaderEnrichment = Enrichment

return Enrichment
