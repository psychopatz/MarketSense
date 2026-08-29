require "MarketSense/signatures/tags/MS_TagMapper"

MarketSense = MarketSense or {}
MarketSense.Signatures = MarketSense.Signatures or {}

local Signature = {}
local TagMapper = MarketSense.TagMapper

-- Exact overrides for vanilla edge cases that script fields do not
-- describe well enough for automatic classification.
local FULLTYPE_OVERRIDES = {
    ["base.beerpack"] = "BeverageBox",
    ["base.beercanpack"] = "BeverageBox",
    ["base.garbagebag_box"] = "ContainerBox",
    ["base.yeast"] = "FoodBaking",
    ["base.bakingsoda"] = "FoodBaking",
    ["base.peppermint"] = "FoodCandy",
    ["base.honey"] = "FoodNoExplicit",
    ["base.bunshotdog"] = "FoodPerishableBread",
    ["base.bunshamburger"] = "FoodPerishableBread",
    ["base.pepper"] = "FoodSpice",
    ["base.hottiez"] = "LiteratureAdult",
    ["base.hottiez_new"] = "LiteratureAdult",
    ["base.brochure"] = "LiteratureBrochure",
    ["base.comicbook"] = "LiteratureComic",
    ["base.comicbook_retail"] = "LiteratureComic",
    ["base.flier"] = "LiteratureFlier",
    ["base.flier_nolans"] = "LiteratureFlier",
    ["base.rpgmanual"] = "LiteratureRpgManual",
    ["base.twigsbundle"] = "MaterialBundled",
    ["base.zipties"] = "MaterialMaintenance",
    ["base.smokingpipe"] = "Smoking",
    ["base.canpipe"] = "Smoking",
}

function Signature.match(ctx)
    local token = FULLTYPE_OVERRIDES[ctx.fullLower or ""]
    if not token then
        return { matched = false, confidence = 0 }
    end
    return TagMapper.makeResult(token, 0.99, { source = "static_override" })
end

MarketSense.Signatures.StaticOverride = Signature
return Signature
