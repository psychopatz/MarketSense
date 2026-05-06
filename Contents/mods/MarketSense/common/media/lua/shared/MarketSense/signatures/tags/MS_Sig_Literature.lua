require "MarketSense/signatures/tags/MS_TagMapper"

MarketSense = MarketSense or {}
MarketSense.Signatures = MarketSense.Signatures or {}

local Signature = {}
local TagMapper = MarketSense.TagMapper

local function hasTag(ctx, token)
    return ctx.normalizedTags and ctx.normalizedTags[token] == true
end
local function itemTypeIs(ctx, t)
    return (ctx.itemTypeToken or "") == t
end
local function displayIs(ctx, t)
    return (ctx.displayCategoryToken or "") == t
end

function Signature.match(ctx)
    if not itemTypeIs(ctx, "literature") and not hasTag(ctx, "hollowbook") then
        return { matched = false, confidence = 0 }
    end
    if displayIs(ctx, "gardening") or displayIs(ctx, "memento") then
        return { matched = false, confidence = 0 }
    end

    if ctx.canBeWrite then
        return TagMapper.makeResult("LiteratureOrJunk", 0.90, { source = "lit_writable" })
    end
    if ctx.learnedRecipes and #ctx.learnedRecipes > 0 then
        return TagMapper.makeResult("LiteratureRecipe", 0.94, { source = "lit_recipe" })
    end
    if hasTag(ctx, "uninteresting") then
        return TagMapper.makeResult("LiteratureOrJunk", 0.85, { source = "lit_uninteresting" })
    end
    if hasTag(ctx, "consumeonread") then
        return TagMapper.makeResult("LiteratureConsumable", 0.92, { source = "lit_consumable" })
    end
    if hasTag(ctx, "newspaper") then
        return TagMapper.makeResult("LiteratureNewspaper", 0.93, { source = "lit_newspaper" })
    end
    if hasTag(ctx, "picturebook") then
        return TagMapper.makeResult("LiteraturePictureBook", 0.92, { source = "lit_picturebook" })
    end
    if hasTag(ctx, "fancybook") then
        return TagMapper.makeResult("LiteratureFancyBook", 0.93, { source = "lit_fancybook" })
    end
    if hasTag(ctx, "softcover") then
        return TagMapper.makeResult("LiteratureSoftcover", 0.91, { source = "lit_softcover" })
    end
    if hasTag(ctx, "hardcover") or hasTag(ctx, "hollowbook") then
        return TagMapper.makeResult("LiteratureHardcover", 0.91, { source = "lit_hardcover" })
    end
    if hasTag(ctx, "magazine") then
        return TagMapper.makeResult("LiteratureMagazine", 0.91, { source = "lit_magazine" })
    end
    if (ctx.skillTrainedLower or "") ~= "" then
        return TagMapper.makeResult("SkillBook", 0.95, { source = "lit_skillbook" })
    end
    if (ctx.readTypeLower or "") == "photo" then
        return TagMapper.makeResult("LiteraturePhoto", 0.88, { source = "lit_photo" })
    end
    return TagMapper.makeResult("LiteratureOrJunk", 0.80, { source = "lit_generic" })
end

MarketSense.Signatures.Literature = Signature
return Signature
