require "MarketSense/signatures/tags/MS_TagMapper"

MarketSense = MarketSense or {}
MarketSense.Signatures = MarketSense.Signatures or {}

local Signature = {}
local TagMapper = MarketSense.TagMapper

function Signature.match(ctx)
    if (ctx.displayCategoryToken or "") ~= "ammo" then
        return { matched = false, confidence = 0 }
    end
    return TagMapper.makeResult("Ammo", 0.95, { source = "ammo_display" })
end

MarketSense.Signatures.Ammo = Signature
return Signature
