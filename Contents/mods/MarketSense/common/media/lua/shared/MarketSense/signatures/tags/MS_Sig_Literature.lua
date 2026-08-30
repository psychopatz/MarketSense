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
local function displayIs(ctx, t)
    return (ctx.displayCategoryToken or "") == t
end

local function contains(text, token)
    return string.find(tostring(text or ""), token, 1, true) ~= nil
end
local function teachesSkillXp(ctx)
    local skill = ctx.skillTrainedLower or ""
    if skill ~= "" and skill ~= "none" and skill ~= "nil" then
        return true
    end
    return (tonumber(ctx.lvlSkillTrained) or -1) >= 0
        or (tonumber(ctx.maxLevelTrained) or -1) >= 0
end

function Signature.match(ctx)
    local learnsRecipe = ctx.learnedRecipes and #ctx.learnedRecipes > 0
    local trainsSkill = teachesSkillXp(ctx)
    local displayCategory = ctx.displayCategoryToken or ""
    local isMap = (ctx.itemTypeToken or "") == "map" or displayCategory == "cartography"
    local isSkillBook = displayCategory == "skillbook"

    local isLiteratureDisplay = displayCategory == "literature"
    local isHollowBook = hasTag(ctx, "hollowbook") or hasTag(ctx, "fancybook")
        or (isLiteratureDisplay and itemTypeIs(ctx, "container"))

    if not itemTypeIs(ctx, "literature") and not isHollowBook
        and not learnsRecipe and not trainsSkill and not isMap and not isSkillBook then
        return { matched = false, confidence = 0 }
    end
    if displayIs(ctx, "gardening") or displayIs(ctx, "memento") then
        return { matched = false, confidence = 0 }
    end

    if isHollowBook then
        local itemId = ctx.idLower or ""
        if hasTag(ctx, "fancybook") or contains(itemId, "hollowfancybook") then
            return TagMapper.makeResult("LiteratureFancyBook", 0.94, {
                source = "lit_hollow_fancy_book",
            })
        end
        local variants = {
            { "handgun", "LiteratureHollowBookHandgun" },
            { "kids", "LiteratureHollowBookKids" },
            { "prison", "LiteratureHollowBookPrison" },
            { "valuables", "LiteratureHollowBookValuables" },
            { "whiskey", "LiteratureHollowBookWhiskey" },
        }
        for _, variant in ipairs(variants) do
            if contains(itemId, variant[1]) then
                return TagMapper.makeResult(variant[2], 0.95, {
                    source = "lit_hollow_book_variant",
                    variant = variant[1],
                })
            end
        end
        return TagMapper.makeResult("LiteratureHollowBook", 0.94, {
            source = "lit_hollow_book_tag_or_display",
        })
    end

    if ctx.canBeWrite then
        return TagMapper.makeResult("LiteratureOrJunk", 0.90, { source = "lit_writable" })
    end
    if learnsRecipe then
        return TagMapper.makeResult("LiteratureRecipe", 0.94, { source = "lit_recipe" })
    end
    if trainsSkill then
        return TagMapper.makeResult("SkillBook", 0.95, { source = "lit_skillbook", skill = ctx.skillTrainedLower })
    end
    if isSkillBook then
        return TagMapper.makeResult("SkillBook", 0.93, { source = "lit_skillbook_display" })
    end
    if isMap then
        return TagMapper.makeResult("LiteratureMap", 0.92, { source = "lit_map" })
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
    if (ctx.readTypeLower or "") == "photo" then
        return TagMapper.makeResult("LiteraturePhoto", 0.88, { source = "lit_photo" })
    end
    return TagMapper.makeResult("LiteratureOrJunk", 0.80, { source = "lit_generic" })
end

MarketSense.Signatures.Literature = Signature
return Signature
