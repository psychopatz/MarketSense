require "MarketSense/signatures/tags/MS_TagMapper"

MarketSense = MarketSense or {}
MarketSense.Signatures = MarketSense.Signatures or {}

local Signature = {}
local TagMapper = MarketSense.TagMapper

local MAT_TAG_MAP = {
    charcoal="MaterialFireSource",
    ingot="MaterialMetalworking", ironmaterial="MaterialMetalworking",
    metalpiece="MaterialMetalworking", piercedingot="MaterialMetalworking",
    smeltableironlarge="MaterialMetalworking", smeltableironmedium="MaterialMetalworking",
    smeltableironsmall="MaterialMetalworking", smeltablesteellarge="MaterialMetalworking",
    smeltablesteelmedium="MaterialMetalworking", smeltablesteelsmall="MaterialMetalworking",
    steelmaterial="MaterialMetalworking",
    leathercrudelarge="MaterialButchering", leathercrudemedium="MaterialButchering",
    leathercrudesmall="MaterialButchering",
    binding="MaterialMaintenance", epoxy="MaterialMaintenance",
    fiberglasstrap="MaterialMaintenance", glue="MaterialMaintenance",
    tape="MaterialMaintenance",
    thread="MaterialTailoring", heavythread="MaterialTailoring",
}

local function hasTag(ctx, token)
    return ctx.normalizedTags and ctx.normalizedTags[token] == true
end

function Signature.match(ctx)
    if (ctx.lootTypeLower or "") ~= "material" then
        return { matched = false, confidence = 0 }
    end

    for token, cat in pairs(MAT_TAG_MAP) do
        if hasTag(ctx, token) then
            return TagMapper.makeResult(cat, 0.90, { source = "material_tag", tag = token })
        end
    end

    -- Name / model heuristics
    local name  = string.lower(ctx.displayName or ctx.typeName or "")
    local model = ctx.worldStaticModelLower or ""
    local sprite = ctx.worldObjectSpriteLower or ""
    if name:find("ingot") or sprite:find("crafting_ore_") or
        (hasTag(ctx, "hasmetal") and (name:find("bar") or name:find("sheet") or name:find("scrap") or name:find("fragment"))) then
        return TagMapper.makeResult("MaterialMetalworking", 0.85, { source = "material_name" })
    end
    if model:find("rolledhide") or model:find("fabricroll") then
        return TagMapper.makeResult("MaterialTailoring", 0.85, { source = "material_model" })
    end
    if model:find("unfired") or model:find("clay") then
        return TagMapper.makeResult("Material", 0.85, { source = "material_pottery" })
    end

    return TagMapper.makeResult("Material", 0.78, { source = "material_generic" })
end

MarketSense.Signatures.Material = Signature
return Signature
