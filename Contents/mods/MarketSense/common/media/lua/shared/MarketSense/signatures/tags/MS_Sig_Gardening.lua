require "MarketSense/signatures/tags/MS_TagMapper"

MarketSense = MarketSense or {}
MarketSense.Signatures = MarketSense.Signatures or {}

local Signature = {}
local TagMapper = MarketSense.TagMapper

local function hasTag(ctx, token)
    return ctx.normalizedTags and ctx.normalizedTags[token] == true
end

function Signature.match(ctx)
    if (ctx.displayCategoryToken or "") ~= "gardening" then
        return { matched = false, confidence = 0 }
    end
    if hasTag(ctx, "iscompostable") or hasTag(ctx, "compostable") then
        return TagMapper.makeResult("GardeningCompostable", 0.90, { source = "gardening_compostable" })
    end
    if hasTag(ctx, "seed") or (ctx.lootTypeLower or ""):find("seed") then
        if (ctx.lootTypeLower or "") == "seedpacket" or hasTag(ctx, "seedpacket") then
            return TagMapper.makeResult("GardeningSeedPacket", 0.92, { source = "gardening_seedpacket" })
        end
        return TagMapper.makeResult("GardeningSeed", 0.90, { source = "gardening_seed" })
    end
    return TagMapper.makeResult("Gardening", 0.85, { source = "gardening_display" })
end

MarketSense.Signatures.Gardening = Signature
return Signature
