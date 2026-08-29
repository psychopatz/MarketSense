require "MarketSense/signatures/tags/MS_TagMapper"

MarketSense = MarketSense or {}
MarketSense.Signatures = MarketSense.Signatures or {}

local Signature = {}
local TagMapper = MarketSense.TagMapper

local DISPLAY_CATEGORY_MAP = {
    ammo = "Ammo",
    ammunition = "Ammo",
    beverage = "Beverage",
    cooking = "Cooking",
    cookingweapon = "Cooking",
    clothing = "Clothing",
    container = "Container",
    electronics = "Electronics",
    firstaid = "FirstAid",
    food = "Food",
    gardening = "Gardening",
    literature = "Literature",
    material = "Material",
    medical = "Medical",
    memento = "Memento",
    junk = "Junk",
    paint = "MaterialChemical",
    smoking = "Smoking",
    tool = "Tool",
    toolweapon = "Tool",
    weapon = "Weapon",
}

function Signature.match(ctx)
    local token = DISPLAY_CATEGORY_MAP[ctx.displayCategoryToken or ""]
    if not token then
        return { matched = false, confidence = 0 }
    end
    return TagMapper.makeResult(token, 0.70, { source = "category_override" })
end

MarketSense.Signatures.CategoryOverride = Signature
return Signature
