require "MarketSense/MS_ItemSignals"
require "MarketSense/signatures/tags/MS_TagMapper"

MarketSense = MarketSense or {}
MarketSense.Signatures = MarketSense.Signatures or {}

local Signature = {}
local Signals = MarketSense.ItemSignals
local TagMapper = MarketSense.TagMapper

function Signature.match(ctx)
    local evidence = Signals.buildingToken(ctx)
    if not evidence then
        return { matched = false, confidence = 0 }
    end
    return TagMapper.makeResult(evidence.token, evidence.confidence, {
        source = evidence.source,
    })
end

MarketSense.Signatures.Building = Signature
return Signature
