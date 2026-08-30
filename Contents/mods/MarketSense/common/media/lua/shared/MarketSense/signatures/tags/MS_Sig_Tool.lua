require "MarketSense/signatures/tags/MS_TagMapper"
require "MarketSense/MS_TagEvidence"

MarketSense = MarketSense or {}
MarketSense.Signatures = MarketSense.Signatures or {}

local Signature = {}
local TagMapper = MarketSense.TagMapper
local TagEvidence = MarketSense.TagEvidence

local TOOL_TAG_MAP = {
    ballpeenhammer="Tool", boltcutters="Tool", clubhammer="Tool",
    hammer="Tool", pipewrench="Tool", pliers="ToolMaintenance",
    scissors="ToolMaintenance", screwdriver="Tool", sledgehammer="Tool",
    anvil="ToolBlacksmith", bellows="ToolBlacksmith", crudetongs="ToolBlacksmith",
    drillmetal="ToolBlacksmith", file="ToolBlacksmith",
    headingtool="ToolBlacksmith", lightmetalsnips="ToolBlacksmith",
    metalworkingchisel="ToolBlacksmith", metalworkingpliers="ToolBlacksmith",
    metalworkingpunch="ToolBlacksmith", metalsaw="ToolBlacksmith",
    sheetmetalsnips="ToolBlacksmith", smallfiles="ToolBlacksmith",
    smallpunch="ToolBlacksmith", smallsaw="ToolBlacksmith",
    smithinghammer="ToolBlacksmith", tongs="ToolBlacksmith", visegrips="ToolBlacksmith",
    fleshingtool="ToolButchering",
    carpentrychisel="ToolCarpentry", crudesaw="ToolCarpentry",
    drillwood="ToolCarpentry", drillwoodpoor="ToolCarpentry", saw="ToolCarpentry",
    knappingtool="ToolFlintKnapping",
    handscythe="ToolGardening", scythe="ToolFarming", digplow="ToolGardening",
    takedirt="ToolGardening", digworms="ToolGardening", clearashes="ToolGardening",
    whetstone="ToolMaintenance",
    masonchisel="ToolMasonry", masonstrowel="ToolMasonry",
    lugwrench="ToolMechanics", wrench="ToolMechanics",
    claytool="ToolPottery",
    awl="ToolTailoring", knittingneedles="ToolTailoring",
    sewingneedle="ToolTailoring", thimble="ToolTailoring",
    blowtorch="ToolWelding", plastertrowel="ToolConstruction",
    shear="ToolFarming",
}

local TOOL_DISP_CATS = {
    tool=true, toolweapon=true,
    firstaidweapon=true, vehiclemaintenance=true,
}

local function hasTag(ctx, token)
    return TagEvidence.has(ctx, token)
end
local function itemTypeIs(ctx, t)
    return (ctx.itemTypeToken or "") == t
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

local function evidenceText(ctx)
    return table.concat({
        ctx.idLower or "", ctx.displayNameLower or "", ctx.iconLower or "",
        ctx.descriptionLower or "", ctx.tooltipLower or "",
        ctx.worldStaticModelLower or "", ctx.worldObjectSpriteLower or "",
    }, " ")
end

function Signature.match(ctx)
    local disp = ctx.displayCategoryToken or ""
    local isTool = TOOL_DISP_CATS[disp]
        or hasTag(ctx, "sharpenable")
        or (itemTypeIs(ctx, "weapon") and not hasTag(ctx, "firearm") and not hasTag(ctx, "nomaintenancexp"))

    if not isTool then return { matched = false, confidence = 0 } end
    if disp == "vehiclemaintenance" and (ctx.mechanicType or 0) > 0 then
        return { matched = false, confidence = 0 }
    end

    local token, cat = TagEvidence.best(ctx, TOOL_TAG_MAP)
    if token then
        return TagMapper.makeResult(cat, 0.90, { source = "tool_tag", tag = token })
    end

    local text = evidenceText(ctx)
    local namedTools = {
        { { "caliper", "loupe", "measuringtape", "measure" }, "ToolMeasurement", "tool_measurement_name" },
        { { "anvil", "bellows", "benchvise", "crudevise", "blacksmith" }, "ToolBlacksmith", "tool_blacksmith_name" },
        { { "clay", "pottery", "mold", "mould", "brush_glaze" }, "ToolPottery", "tool_pottery_name" },
        { { "plastertrowel", "trowel", "paintbrush", "paint_brush" }, "ToolConstruction", "tool_construction_name" },
        { { "blowtorch", "blow_torch" }, "ToolWelding", "tool_welding_name" },
        { { "steelwool", "straightrazor", "razor", "scissors", "scalpel", "rubberhose" }, "ToolMaintenance", "tool_maintenance_name" },
        { { "oilpress" }, "ToolFarming", "tool_farming_name" },
        { { "bullhorn", "funnel", "heavychain", "chain_hook", "hook" }, "ToolUtility", "tool_utility_name" },
    }
    for _, entry in ipairs(namedTools) do
        if containsAny(text, entry[1]) then
            return TagMapper.makeResult(entry[2], 0.88, {
                source = entry[3],
                evidence = text,
            })
        end
    end
    if contains(text, "tobacco") then
        return TagMapper.makeResult("Smoking", 0.88, {
            source = "tool_tobacco_name",
            evidence = text,
        })
    end

    if disp == "vehiclemaintenance" then
        return TagMapper.makeResult("ToolMechanics", 0.82, { source = "tool_vehiclemaint" })
    end
    return TagMapper.makeResult("Tool", 0.80, { source = "tool_generic" })
end

MarketSense.Signatures.Tool = Signature
return Signature
