require "MarketSense/signatures/tags/MS_TagMapper"
require "MarketSense/MS_TagEvidence"

MarketSense = MarketSense or {}
MarketSense.Signatures = MarketSense.Signatures or {}

local Signature = {}
local TagMapper = MarketSense.TagMapper
local TagEvidence = MarketSense.TagEvidence

local TOOL_TAG_MAP = {
    ballpeenhammer="Tool", boltcutters="Tool", clubhammer="Tool",
    hammer="Tool", pipewrench="Tool", pliers="Tool",
    scissors="Tool", screwdriver="Tool", sledgehammer="Tool",
    crudetongs="ToolBlacksmith", drillmetal="ToolBlacksmith", file="ToolBlacksmith",
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
    handscythe="ToolGardening", scythe="ToolGardening",
    whetstone="ToolMaintenance",
    masonchisel="ToolMasonry", masonstrowel="ToolMasonry",
    lugwrench="ToolMechanics", wrench="ToolMechanics",
    claytool="ToolPottery",
    awl="ToolTailoring", knittingneedles="ToolTailoring",
    sewingneedle="ToolTailoring", thimble="ToolTailoring",
    blowtorch="ToolWelding",
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

    if disp == "vehiclemaintenance" then
        return TagMapper.makeResult("ToolMechanics", 0.82, { source = "tool_vehiclemaint" })
    end
    return TagMapper.makeResult("Tool", 0.80, { source = "tool_generic" })
end

MarketSense.Signatures.Tool = Signature
return Signature
