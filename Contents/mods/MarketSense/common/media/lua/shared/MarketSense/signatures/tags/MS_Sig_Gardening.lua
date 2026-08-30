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

local function contains(text, token)
    return string.find(tostring(text or ""), token, 1, true) ~= nil
end

local function containsAny(text, tokens)
    for _, token in ipairs(tokens or {}) do
        if contains(text, token) then
            return true
        end
    end
    return false
end

local function isSeedPacket(ctx)
    local displayCategory = ctx.displayCategoryToken or ""
    local itemId = ctx.idLower or ""
    local displayName = ctx.displayNameLower or ""
    local lootType = ctx.lootTypeLower or ""
    local seedNamed = containsAny(itemId, { "bagseed", "seedpacket", "seed" })
        or containsAny(displayName, { "bag seed", "seed packet" })

    return displayCategory == "gardening"
        or hasTag(ctx, "seedpacket")
        or hasTag(ctx, "seed")
        or contains(lootType, "seed")
        or (seedNamed and displayCategory == "drugs")
        or (seedNamed and ctx.isCraftRecipeProduct == true
            and containsAny(itemId, { "bagseed", "seedpacket" }))
end

local function isSeed(ctx)
    local displayCategory = ctx.displayCategoryToken or ""
    local itemId = ctx.idLower or ""
    return hasTag(ctx, "isseed")
        or hasTag(ctx, "seed")
        or (displayCategory == "gardening" and contains(itemId, "seed")
            and not containsAny(itemId, { "seedbag", "seedpacket" }))
end

local function isSpecificSeedPacket(ctx)
    local itemId = ctx.idLower or ""
    local displayName = ctx.displayNameLower or ""
    local lootType = ctx.lootTypeLower or ""
    return hasTag(ctx, "seedpacket")
        or lootType == "seedpacket"
        or containsAny(itemId, { "bagseed", "seedpacket" })
        or containsAny(displayName, { "bag seed", "seed packet" })
end

function Signature.match(ctx)
    if not isSeedPacket(ctx) then
        return { matched = false, confidence = 0 }
    end
    local itemId = ctx.idLower or ""
    local displayName = ctx.displayNameLower or ""

    if containsAny(itemId, { "gardeningspray", "pestcontrol", "insecticide", "molluscide" })
        or containsAny(displayName, { "garden spray", "pest control", "insecticide" }) then
        return TagMapper.makeResult("GardeningPestControl", 0.94, {
            source = "gardening_spray_name",
        })
    end
    if containsAny(itemId, { "animalfeed", "feedbag" })
        or hasTag(ctx, "farmingloot") and contains(itemId, "feed") then
        return TagMapper.makeResult("BuildingAgricultureLivestock", 0.94, {
            source = "gardening_livestock_feed_name_or_tag",
        })
    end
    if contains(itemId, "grassbag") or hasTag(ctx, "farmingloot") and contains(itemId, "grass") then
        return TagMapper.makeResult("GardeningCompostable", 0.88, {
            source = "gardening_grass_bag_name_or_tag",
        })
    end
    if containsAny(itemId, { "raisedplantbed", "brickplanter", "planter" }) then
        return TagMapper.makeResult("BuildingGardenPlanter", 0.92, {
            source = "gardening_planter_name",
        })
    end
    if containsAny(itemId, {
        "bonsaitree", "cactus", "castironplant", "chineseevergreen", "dragontree",
        "fern", "ficus", "snakeplant", "violetflowers", "birdbath",
    }) then
        return TagMapper.makeResult("BuildingGardenDecor", 0.90, {
            source = "gardening_plant_decor_name",
        })
    end
    if containsAny(itemId, { "poppypods", "sunflowerheaddried" }) then
        return TagMapper.makeResult("GardeningHarvest", 0.88, {
            source = "gardening_harvest_name",
        })
    end
    if hasTag(ctx, "iscompostable") or hasTag(ctx, "compostable") then
        return TagMapper.makeResult("GardeningCompostable", 0.90, { source = "gardening_compostable" })
    end
    if hasTag(ctx, "compost") or containsAny(ctx.idLower or "", { "compost", "compostable" }) then
        return TagMapper.makeResult("GardeningCompost", 0.92, { source = "gardening_compost" })
    end
    if hasTag(ctx, "fertilizer") or containsAny(ctx.idLower or "", { "fertilizer", "fertiliser" })
        or contains(ctx.tooltipLower, "fertilizer") then
        return TagMapper.makeResult("GardeningFertilizer", 0.92, { source = "gardening_fertilizer" })
    end
    if containsAny(ctx.idLower or "", { "slugrepellent", "pestcontrol", "insecticide", "molluscide" })
        or containsAny(ctx.displayNameLower or "", { "slug repellent", "pest control", "insecticide" }) then
        return TagMapper.makeResult("GardeningPestControl", 0.91, { source = "gardening_pest_control" })
    end
    if isSpecificSeedPacket(ctx) then
        return TagMapper.makeResult("GardeningSeedPacket", 0.92, { source = "gardening_seedpacket" })
    end
    if isSeed(ctx) or (ctx.lootTypeLower or ""):find("seed")
        or ((ctx.displayCategoryToken or "") == "drugs"
            and contains(ctx.idLower or "", "seed")) then
        return TagMapper.makeResult("GardeningSeed", 0.90, { source = "gardening_seed" })
    end
    return TagMapper.makeResult("Gardening", 0.85, { source = "gardening_display" })
end

MarketSense.Signatures.Gardening = Signature
return Signature
