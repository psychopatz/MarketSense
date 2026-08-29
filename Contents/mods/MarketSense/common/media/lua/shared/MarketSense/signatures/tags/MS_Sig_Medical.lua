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
local function displayIs(ctx, t)
    return (ctx.displayCategoryToken or "") == t
end

function Signature.match(ctx)
    if displayIs(ctx, "firstaid") or displayIs(ctx, "bandage") or displayIs(ctx, "medical") then
        return TagMapper.makeResult("FirstAid", 0.92, { source = "medical_display" })
    end
    if (tonumber(ctx.bandagePower) or 0) > 0
        or (tonumber(ctx.reduceInfectionPower) or 0) > 0
        or (tonumber(ctx.alcoholPower) or 0) > 0 then
        return TagMapper.makeResult("FirstAid", 0.87, { source = "medical_props" })
    end
    return { matched = false, confidence = 0 }
end

MarketSense.Signatures.Medical = Signature
return Signature
