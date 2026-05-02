require "MarketSense/DT_Core"

DynamicTrading = DynamicTrading or {}
DynamicTrading.Signatures = DynamicTrading.Signatures or {}

local Core = DynamicTrading.Core
local Signature = {}

local function success(confidence, primary, tags)
    return {
        matched = true,
        confidence = confidence,
        category = "Resource",
        primary = primary,
        tags = tags,
    }
end

function Signature.match(ctx)
    local matched = Core.ctxContains(ctx, {
        "material", "reciperesource", "gascan", "gasoline", "fuelcan", "jerrycan",
        "propane", "gastank", "charcoal", "coal", "firewood", "metal", "steel",
        "iron", "copper", "aluminum", "brass", "bronze", "lead", "silver", "gold",
        "ingot", "nail", "screw", "bolt", "nut", "rivet", "wire", "hinge", "pipe",
        "plank", "log", "lumber", "wood", "cloth", "fabric", "thread", "rope",
        "twine", "leather", "hide", "pelt", "glass", "shard", "stone", "concrete",
        "cement", "plaster", "brick", "gravel", "sand", "glue", "epoxy", "tape",
        "adhesive", "powder", "sulfur", "saltpeter", "dye",
    })

    if not matched then
        return { matched = false, confidence = 0 }
    end

    local primary = "Resource.Material.General"
    local tags = { "Resource.Craftable" }

    if Core.ctxContains(ctx, { "gascan", "gasoline", "fuelcan", "jerrycan" }) then
        primary = "Resource.Fuel.Gas"
    elseif Core.ctxContains(ctx, { "propane", "gastank" }) then
        primary = "Resource.Fuel.Liquid"
    elseif Core.ctxContains(ctx, { "charcoal", "coal", "firewood" }) then
        primary = "Resource.Fuel.Solid"
    elseif Core.ctxContains(ctx, { "gold", "silver", "metal", "steel", "iron", "copper", "aluminum", "brass", "bronze", "lead", "ingot" }) then
        primary = "Resource.Material.Metal"
        if Core.ctxContains(ctx, { "gold" }) then tags[#tags + 1] = "Resource.Material.MetalFamily.Gold" end
        if Core.ctxContains(ctx, { "silver" }) then tags[#tags + 1] = "Resource.Material.MetalFamily.Silver" end
        if Core.ctxContains(ctx, { "ingot" }) then tags[#tags + 1] = "Resource.Material.MetalForm.Ingot" end
        if Core.ctxContains(ctx, { "scrap" }) then tags[#tags + 1] = "Resource.Material.MetalForm.Scrap" end
        if Core.ctxContains(ctx, { "ore" }) then tags[#tags + 1] = "Resource.Material.MetalForm.Ore" end
    elseif Core.ctxContains(ctx, { "nail", "screw", "bolt", "nut", "rivet", "wire", "hinge", "pipe" }) then
        primary = "Resource.Material.Hardware"
    elseif Core.ctxContains(ctx, { "plank", "log", "lumber", "wood" }) then
        primary = "Resource.Material.Wood"
    elseif Core.ctxContains(ctx, { "cloth", "fabric", "thread", "rope", "twine" }) then
        primary = "Resource.Material.Textile"
    elseif Core.ctxContains(ctx, { "leather", "hide", "pelt" }) then
        primary = "Resource.Material.Leather"
    elseif Core.ctxContains(ctx, { "glass", "shard" }) then
        primary = "Resource.Material.Glass"
    elseif Core.ctxContains(ctx, { "stone", "concrete", "cement", "plaster", "brick", "gravel", "sand" }) then
        primary = "Resource.Material.Mineral"
    elseif Core.ctxContains(ctx, { "glue", "epoxy", "tape", "adhesive" }) then
        primary = "Resource.Material.Adhesive"
    elseif Core.ctxContains(ctx, { "powder", "sulfur", "saltpeter", "dye" }) then
        primary = "Resource.Material.Chemical"
    end

    tags[#tags + 1] = primary
    return success(0.84, primary, tags)
end

DynamicTrading.Signatures.Resource = Signature
return Signature
