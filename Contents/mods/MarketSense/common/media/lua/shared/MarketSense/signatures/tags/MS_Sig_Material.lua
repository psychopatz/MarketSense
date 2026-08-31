require "MarketSense/signatures/tags/MS_TagMapper"
require "MarketSense/MS_TagEvidence"

MarketSense = MarketSense or {}
MarketSense.Signatures = MarketSense.Signatures or {}

local Signature = {}
local TagMapper = MarketSense.TagMapper
local TagEvidence = MarketSense.TagEvidence

-- These are semantic buckets for MarketSense and future consumers. They do
-- not change the native Project Zomboid item category.
local MAT_TAG_MAP = {
    charcoal="MaterialFireSource",
    ingot="MaterialMetalworking", ironmaterial="MaterialMetalworking",
    barstock="MaterialMetalworking", barstockhalf="MaterialMetalworking",
    toolhead="MaterialMetalworking",
    metalpiece="MaterialMetalworking", piercedingot="MaterialMetalworking",
    hammerstone="MaterialStone",
    smeltableironlarge="MaterialMetalworking", smeltableironmedium="MaterialMetalworking",
    smeltableironsmall="MaterialMetalworking", smeltablesteellarge="MaterialMetalworking",
    smeltablesteelmedium="MaterialMetalworking", smeltablesteelsmall="MaterialMetalworking",
    steelmaterial="MaterialMetalworking",
    leathercrudelarge="MaterialButchering", leathercrudemedium="MaterialButchering",
    leathercrudesmall="MaterialButchering",
    binding="MaterialMaintenance", epoxy="MaterialMaintenance",
    fiberglasstrap="MaterialMaintenance", glue="MaterialMaintenance",
    tape="MaterialMaintenance",
    thread="MaterialTailoring", heavythread="MaterialTailoring", rope="MaterialTailoring",
    burlap="MaterialTailoring", button="MaterialTailoring", sheet="MaterialTailoring",
    woodhandle="MaterialCarpentry",
}

local function hasTag(ctx, token)
    return TagEvidence.has(ctx, token)
end

local function hasTagAlias(ctx, token)
    return hasTag(ctx, token) or hasTag(ctx, "base" .. token)
end

local function hasAnyTagAlias(ctx, tokens)
    for _, token in ipairs(tokens or {}) do
        if hasTagAlias(ctx, token) then return true end
    end
    return false
end

local function contains(text, token)
    return string.find(tostring(text or ""), token, 1, true) ~= nil
end

local function containsAny(text, tokens)
    for _, token in ipairs(tokens or {}) do
        if contains(text, token) then return true end
    end
    return false
end

local function materialResult(token, confidence, source)
    return TagMapper.makeResult(token, confidence, { source = source })
end

local function evidenceText(ctx)
    -- FullType covers mod items whose display name is localized or missing.
    -- WorldStaticModel is the script's bridge to a placeable asset.
    return table.concat({
        ctx.fullLower or "",
        ctx.idLower or "",
        ctx.displayNameLower or "",
        ctx.descriptionLower or "",
        ctx.iconLower or "",
        ctx.worldStaticModelLower or "",
        ctx.worldObjectSpriteLower or "",
        ctx.doubleClickRecipeLower or "",
        ctx.replaceOnDepleteLower or "",
    }, " ")
end

function Signature.match(ctx)
    local displayCategory = ctx.displayCategoryToken or ""
    local fluidCategory = ctx.fluidCategoryLower or ""
    local replaceOnDeplete = ctx.replaceOnDepleteLower or ""

    -- These anchors are valid even when the script uses a broad category.
    if hasTagAlias(ctx, "paint")
        or displayCategory == "paint"
        or contains(replaceOnDeplete, "paintbucketempty") then
        return materialResult("MaterialChemical", 0.98, "material_paint_anchor")
    end

    if fluidCategory == "dyes" or fluidCategory == "hairdyes" then
        return materialResult("MaterialChemical", 0.96, "material_fluid_category")
    end

    if fluidCategory == "fuel" then
        return materialResult("ResourceFuel", 0.96, "material_fluid_category")
    end

    if displayCategory == "corpse" or hasTagAlias(ctx, "animalcorpse") then
        return materialResult("MaterialButchering", 0.96, "material_animal_corpse")
    end

    if (ctx.lootTypeLower or "") ~= "material"
        and displayCategory ~= "material"
        and displayCategory ~= "materialweapon"
        and displayCategory ~= "corpse"
        and not hasTagAlias(ctx, "animalcorpse") then
        return { matched = false, confidence = 0 }
    end

    local token, category = TagEvidence.best(ctx, MAT_TAG_MAP)
    if token then
        return materialResult(category, 0.90, "material_tag_" .. token)
    end

    local text = evidenceText(ctx)
    local model = ctx.worldStaticModelLower or ""
    local sprite = ctx.worldObjectSpriteLower or ""

    if containsAny(text, {
        "tissue", "toiletpaper", "papertowel", "paper towel", "paperroll",
    }) then
        return materialResult("MaterialPaper", 0.92, "material_paper_evidence")
    end

    if containsAny(text, {
        "ducttape", "adhesivetape", "fiberglasstape", "scotchtape", "tape",
    }) then
        return materialResult("MaterialMaintenance", 0.89, "material_maintenance_evidence")
    end

    -- Construction precedes pottery: ClayTile/ClayBrick and clay shingles
    -- are building inputs, not finished pottery.
    if hasAnyTagAlias(ctx, { "wallpaper", "wallpaperpaste", "plaster", "concrete" })
        or containsAny(text, {
            "wallpaper", "plaster", "concrete", "cement", "quicklime",
            "sandbag", "gravelbag", "dirtbag", "claybag", "barricadecube",
            "claybrick", "claytile", "clayshingle", "shingle",
        }) then
        return materialResult("MaterialConstruction", 0.92, "material_construction_evidence")
    end

    -- Do not use isfirefuel alone: PZ marks sheets, tarps and yarn as
    -- burnable, but those are tailoring materials rather than firewood.
    if hasAnyTagAlias(ctx, { "charcoal", "log" })
        or containsAny(text, { "firewood", "charcoal", "coke", "twigs", "logstack", "tirepiece" }) then
        return materialResult("MaterialFireSource", 0.91, "material_fire_source_evidence")
    end

    if hasAnyTagAlias(ctx, { "glass", "glasspanel" })
        or containsAny(text, {
            "glasspanel", "lanternglass", "glassblowing", "glassblower",
            "moldglass", "glasssheet", "glass",
        }) then
        return materialResult("MaterialGlass", 0.90, "material_glass_evidence")
    end

    if hasAnyTagAlias(ctx, { "stone", "limestone", "flintpiece" })
        or containsAny(text, {
            "limestone", "chippedstone", "flint", "stoneblock", "stonewheel",
            "sharpenedstone", "stoneblade", "stoneaxehead", "stonemaulhead",
            "flatstone", "largestone",
        }) then
        return materialResult("MaterialStone", 0.90, "material_stone_evidence")
    end

    -- Hardware is before the broad metalworking rule: nails, wire and
    -- hinges can carry base:hasmetal without being smelting inputs.
    if containsAny(text, {
        "nails", "screws", "wire", "hinge", "doorknob", "buckle",
        "paperclip", "nutsbolts", "blowerfan", "metalbracket",
    }) then
        return materialResult("MaterialHardware", 0.88, "material_hardware_evidence")
    end

    if hasAnyTagAlias(ctx, {
        "ironore", "ironsource", "copperore", "coppersource", "aluminum",
        "hasmetal",
    }) and containsAny(text, {
        "ore", "ingot", "ironbloom", "hematite", "malachite", "metalbar",
        "metalsheet", "sheetmetal", "metalscrap", "metalfragment", "scrap",
        "fragment", "coppersheet", "ironbar", "steelbar", "smelt", "crucible",
        "anvil", "bellows", "weldingrod", "swordblade", "blade",
    }) then
        return materialResult("MaterialMetalworking", 0.88, "material_metalworking_evidence")
    end
    if containsAny(text, {
        "ironore", "copperore", "aluminum", "ironbloom", "hematite", "malachite",
        "ingot", "metalsheet", "sheetmetal", "coppersheet", "ironbar", "steelbar",
        "scrap", "weldingrod", "bellows", "swordblade", "ceramiccrucible", "anvil",
    }) then
        return materialResult("MaterialMetalworking", 0.86, "material_metalworking_name")
    end

    if containsAny(text, {
        "clay", "ceramic", "mortar", "teacup", "claypot", "clayjar",
        "claybowl", "claymug", "claypipe", "clayplate",
    }) or contains(model, "unfired") then
        return materialResult("MaterialPottery", 0.86, "material_pottery_evidence")
    end

    if hasAnyTagAlias(ctx, { "thread", "heavythread", "rope", "burlap" })
        or containsAny(text, {
            "fabric", "denim", "rippedsheet", "cheesecloth", "wool", "yarn",
            "flax", "hemp", "string", "rope", "tarp", "pillow", "dogbane",
            "burlap", "leatherstrips", "cloth",
        }) or contains(model, "rolledhide") or contains(model, "fabricroll") then
        return materialResult("MaterialTailoring", 0.86, "material_tailoring_evidence")
    end

    if containsAny(text, {
        "packframe", "woodenmold", "woodmold", "woodhandle", "largeplank",
        "smallplank", "drawer",
    }) then
        return materialResult("MaterialCarpentry", 0.85, "material_carpentry_evidence")
    end

    if hasAnyTagAlias(ctx, { "wood" })
        or containsAny(text, { "wood", "plank" }) then
        return materialResult("MaterialWood", 0.84, "material_wood_evidence")
    end

    if containsAny(text, { "gunpowder", "sparklers", "industrialdye", "dye" }) then
        return materialResult("MaterialChemical", 0.86, "material_chemical_evidence")
    end

    -- Bundles/stacks are useful only after their domain is known. For example,
    -- FirewoodBundle is already classified as a fire source above.
    if containsAny(text, { "bundle", "stack" }) then
        return materialResult("MaterialBundled", 0.83, "material_bundle_evidence")
    end

    -- Keep the old generic cues for unusual mod materials, below the
    -- evidence-backed branches.
    if contains(text, "ingot") or contains(sprite, "crafting_ore_") then
        return materialResult("MaterialMetalworking", 0.85, "material_name")
    end
    if contains(text, "leatherfurtanned")
        or hasAnyTagAlias(ctx, { "leatherfurtannedsmall", "leatherfurtannedmedium", "leatherfurtannedlarge" }) then
        return materialResult("MaterialTailoring", 0.86, "material_tanned_hide")
    end
    if contains(text, "hide") or contains(text, "leather") then
        return materialResult("MaterialButchering", 0.82, "material_hide_name")
    end

    return materialResult("Material", 0.78, "material_generic")
end

MarketSense.Signatures.Material = Signature
return Signature
