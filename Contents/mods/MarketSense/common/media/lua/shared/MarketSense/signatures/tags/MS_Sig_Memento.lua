require "MarketSense/signatures/tags/MS_TagMapper"
require "MarketSense/MS_TagEvidence"

MarketSense = MarketSense or {}
MarketSense.Signatures = MarketSense.Signatures or {}

local Signature = {}
local TagMapper = MarketSense.TagMapper
local TagEvidence = MarketSense.TagEvidence

local function hasTag(ctx, token)
    return TagEvidence.has(ctx, token)
end
local function itemTypeIs(ctx, t)
    return (ctx.itemTypeToken or "") == t
end

function Signature.match(ctx)
    if hasTag(ctx, "ismemento") and not itemTypeIs(ctx, "container") then
        return TagMapper.makeResult("Memento", 0.90, { source = "memento_tag" })
    end
    return { matched = false, confidence = 0 }
end

MarketSense.Signatures.Memento = Signature
return Signature
