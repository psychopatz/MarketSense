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

function Signature.match(ctx)
    if hasTag(ctx, "smokable") then
        return TagMapper.makeResult("Smoking", 0.92, { source = "smoking_tag" })
    end
    return { matched = false, confidence = 0 }
end

MarketSense.Signatures.Smoking = Signature
return Signature
