require "MarketSense/DT_Core"

DynamicTrading = DynamicTrading or {}
DynamicTrading.Signatures = DynamicTrading.Signatures or {}

local Core = DynamicTrading.Core
local Signature = {}

local RESOURCE_DISPLAY_CATEGORIES = { ["material"] = true, ["reciperesource"] = true }
local NON_RESOURCE_DISPLAY_CATEGORIES = {
    ["food"] = true,
    ["firstaid"] = true,
    ["literature"] = true,
    ["skillbook"] = true,
    ["cartography"] = true,
    ["electronics"] = true,
    ["camping"] = true,
    ["trapping"] = true,
    ["furniture"] = true,
    ["household"] = true,
    ["vehiclemaintenance"] = true,
}

local PART_PATTERNS = { "axehead", "hatchethead", "hammerhead", "macehead", "spearhead", "knifeblade", "swordblade", "macheteblade", "toolhead" }
local LIQUID_FUEL_PATTERNS = { "gasoline", "petrol", "diesel", "kerosene", "lighterfluid", "starterfluid", "bbqstarterfluid", "gascan", "fuelcan", "jerrycan" }
local GAS_FUEL_PATTERNS = { "propane", "gastank" }
local SOLID_FUEL_PATTERNS = { "charcoal", "coal", "firewood", "kindling" }
local AMMO_MATERIAL_PATTERNS = { "gunpowder", "blackpowder", "primer", "wad", "pellet", "shotshell", "casing", "bullettip" }
local METAL_PATTERNS = { "metal", "steel", "iron", "copper", "aluminum", "aluminium", "brass", "bronze", "lead", "silver", "gold", "ingot", "rebar" }
local HARDWARE_PATTERNS = { "nail", "screw", "bolt", "nut", "rivet", "wire", "barbedwire", "chain", "hinge", "pipe", "valve", "handle", "latch" }
local WOOD_PATTERNS = { "wood", "plank", "log", "lumber", "timber", "beam", "twig", "branch", "firewood" }
local TEXTILE_PATTERNS = { "fabric", "cloth", "denim", "burlap", "thread", "yarn", "twine", "rope", "string", "canvas", "linen", "wool", "cotton", "strips" }
local LEATHER_PATTERNS = { "leather", "hide", "pelt", "fur" }
local GLASS_PATTERNS = { "glass", "shard", "lens" }
local MINERAL_PATTERNS = { "ore", "stone", "clay", "gravel", "sand", "limestone", "chalk", "rock", "flint", "brick", "concrete", "cement", "plaster", "mortar" }
local CERAMIC_PATTERNS = { "ceramic", "crucible" }
local ADHESIVE_PATTERNS = { "glue", "epoxy", "tape", "paste", "caulk", "resin", "adhesive" }
local CHEMICAL_PATTERNS = { "lye", "sulfur", "saltpeter", "pigment", "dye", "flux", "powder", "oxygen" }
local PAPER_PATTERNS = { "paper", "cardboard", "label", "roll" }
local PACKAGING_PATTERNS = { "box", "bag", "sack", "bundle", "carton", "package", "parcel", "wrapper" }

local RESOURCE_TAG_HINTS = {
    ["base:hasmetal"] = true,
    ["base:steelmaterial"] = true,
    ["base:toolhead"] = true,
    ["base:glass"] = true,
    ["base:glue"] = true,
    ["base:epoxy"] = true,
    ["base:tape"] = true,
    ["base:binding"] = true,
    ["base:simpleweaponbinding"] = true,
    ["base:ingot"] = true,
}

local function containsAny(text, patterns)
    local source = tostring(text or "")
    if source == "" then
        return false
    end
    for _, pattern in ipairs(patterns or {}) do
        if string.find(source, pattern, 1, true) then
            return true
        end
    end
    return false
end

local function hasScriptTag(ctx, expected)
    for _, tag in ipairs(ctx.tags or {}) do
        if expected[Core.lower(tag)] then
            return true
        end
    end
    return false
end

local function getResourceSubtype(itemLower, displayCategory, ctx)
    if containsAny(itemLower, PART_PATTERNS) or hasScriptTag(ctx, { ["base:toolhead"] = true }) then
        return "Parts"
    end
    if containsAny(itemLower, LIQUID_FUEL_PATTERNS) then
        return "Fuel.Liquid"
    end
    if containsAny(itemLower, GAS_FUEL_PATTERNS) then
        return "Fuel.Gas"
    end
    if containsAny(itemLower, SOLID_FUEL_PATTERNS) then
        return "Fuel.Solid"
    end
    if containsAny(itemLower, AMMO_MATERIAL_PATTERNS) then
        return "Material.Ammo"
    end
    if containsAny(itemLower, ADHESIVE_PATTERNS) or hasScriptTag(ctx, { ["base:glue"] = true, ["base:epoxy"] = true, ["base:tape"] = true }) then
        return "Material.Adhesive"
    end
    if containsAny(itemLower, CERAMIC_PATTERNS) then
        return "Material.Ceramic"
    end
    if containsAny(itemLower, LEATHER_PATTERNS) then
        return "Material.Leather"
    end
    if containsAny(itemLower, TEXTILE_PATTERNS) then
        return "Material.Textile"
    end
    if containsAny(itemLower, HARDWARE_PATTERNS) then
        return "Material.Hardware"
    end
    if containsAny(itemLower, MINERAL_PATTERNS) then
        return "Material.Mineral"
    end
    if containsAny(itemLower, GLASS_PATTERNS) or hasScriptTag(ctx, { ["base:glass"] = true }) then
        return "Material.Glass"
    end
    if containsAny(itemLower, METAL_PATTERNS) or hasScriptTag(ctx, { ["base:hasmetal"] = true, ["base:ingot"] = true, ["base:steelmaterial"] = true }) then
        return "Material.Metal"
    end
    if containsAny(itemLower, WOOD_PATTERNS) then
        return "Material.Wood"
    end
    if containsAny(itemLower, CHEMICAL_PATTERNS) then
        return "Material.Chemical"
    end
    if containsAny(itemLower, PAPER_PATTERNS) or (displayCategory == "reciperesource" and (string.find(itemLower, "paper", 1, true) ~= nil or string.find(itemLower, "card", 1, true) ~= nil)) then
        return "Material.Paper"
    end
    if string.sub(itemLower, -6) == "_empty" or string.find(itemLower, "bagseed", 1, true) ~= nil or containsAny(itemLower, PACKAGING_PATTERNS) then
        return "Material.Packaging"
    end
    return "Material.General"
end

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
    local itemLower = tostring(ctx.idLower or "")
    local displayCategory = tostring(ctx.displayCategoryLower or "")
    local hasWeaponDamage = (tonumber(ctx.minDamage) or 0) >= 0.5 or (tonumber(ctx.maxDamage) or 0) >= 0.5

    local isMaterialDisplay = RESOURCE_DISPLAY_CATEGORIES[displayCategory] == true
    local isWeaponPart = containsAny(itemLower, PART_PATTERNS) or hasScriptTag(ctx, { ["base:toolhead"] = true })
    local isFuelResource = containsAny(itemLower, LIQUID_FUEL_PATTERNS) or containsAny(itemLower, GAS_FUEL_PATTERNS) or containsAny(itemLower, SOLID_FUEL_PATTERNS)
    local hasResourceTags = hasScriptTag(ctx, RESOURCE_TAG_HINTS)

    if hasWeaponDamage and not (isMaterialDisplay or isWeaponPart) then
        return { matched = false, confidence = 0 }
    end
    if (ctx.bodyLocationLower or "") ~= "" then
        return { matched = false, confidence = 0 }
    end
    if (ctx.itemTypeLower or "") == "base:container" and not isMaterialDisplay then
        return { matched = false, confidence = 0 }
    end
    if (ctx.itemTypeLower or "") == "base:literature" and displayCategory ~= "reciperesource" then
        return { matched = false, confidence = 0 }
    end
    if NON_RESOURCE_DISPLAY_CATEGORIES[displayCategory] and not isMaterialDisplay and not isWeaponPart and not isFuelResource then
        return { matched = false, confidence = 0 }
    end

    local subtype = getResourceSubtype(itemLower, displayCategory, ctx)
    local looksLikeResource = isMaterialDisplay or hasResourceTags or isWeaponPart or isFuelResource or subtype ~= "Material.General" or ((tonumber(ctx.useDelta) or 0) > 0 and displayCategory == "material")
    if not looksLikeResource then
        return { matched = false, confidence = 0 }
    end

    local evidence = 0
    if isMaterialDisplay then evidence = evidence + (displayCategory == "material" and 0.55 or 0.45) end
    if hasResourceTags then evidence = evidence + 0.25 end
    if isWeaponPart then evidence = evidence + 0.35 end
    if isFuelResource then evidence = evidence + 0.3 end
    if (tonumber(ctx.useDelta) or 0) > 0 and (isMaterialDisplay or subtype == "Material.Adhesive" or subtype == "Material.Chemical" or subtype == "Material.Ammo") then
        evidence = evidence + 0.2
    end
    if subtype ~= "Material.General" then evidence = evidence + 0.25 end

    local confidence = math.min(1.0, evidence)
    if confidence < 0.45 then
        return { matched = false, confidence = confidence }
    end

    local primary = "Resource." .. subtype
    local tags = { primary, "Resource.Craftable" }
    return success(confidence, primary, tags)
end

DynamicTrading.Signatures.Resource = Signature
return Signature
