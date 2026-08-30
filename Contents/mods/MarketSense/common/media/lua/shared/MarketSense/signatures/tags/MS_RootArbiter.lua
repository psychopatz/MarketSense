require "MarketSense/signatures/tags/MS_TagMapper"
require "MarketSense/MS_TagEvidence"
require "MarketSense/MS_ItemSignals"

MarketSense = MarketSense or {}
MarketSense.RootArbiter = MarketSense.RootArbiter or {}

local RootArbiter = MarketSense.RootArbiter
local Signals = MarketSense.ItemSignals
local TagEvidence = MarketSense.TagEvidence

local function hasTag(ctx, token)
    return TagEvidence.has(ctx, token)
end

local function hasTagAlias(ctx, token)
    return hasTag(ctx, token) or hasTag(ctx, "base" .. token)
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

local function itemTypeIs(ctx, ...)
    local itemType = ctx and ctx.itemTypeToken or ""
    for _, token in ipairs({...}) do
        if itemType == token then
            return true
        end
    end
    return false
end

local function resolved(root, source, result)
    return {
        root = root,
        source = source,
        result = result,
    }
end

local function staticOverride(ctx)
    local sig = MarketSense.Signatures and MarketSense.Signatures.StaticOverride or nil
    if not sig or type(sig.match) ~= "function" then
        return nil
    end

    local ok, result = pcall(sig.match, ctx)
    if ok and result and result.matched then
        return resolved(result.category or MarketSense.TagMapper.categoryFromPrimary(result.primary), "root_static_override", result)
    end
    return nil
end

local function liquidRoot(ctx)
    -- A FluidContainer describes the vessel.  Only a non-empty primary fluid
    -- is eligible for the Liquid root; empty bottles, buckets, and cans still
    -- belong to ContainerLiquid.
    if ctx.isActualLiquid == true
        or (ctx.fluidTypeStringLower or "") ~= ""
        or (ctx.fluidTypeLower or "") ~= "" then
        return resolved("Liquid", "root_liquid")
    end
    return nil
end

local function materialRoot(ctx)
    local displayCategory = ctx.displayCategoryToken or ""
    local fluidCategory = ctx.fluidCategoryLower or ""
    local replaceOnDeplete = ctx.replaceOnDepleteLower or ""

    -- PZ uses MaterialWeapon for bars, stone, wood blanks and other craft
    -- stock that happens to inherit weapon fields.  The display category is
    -- the authoritative root signal; do not let damage/category metadata
    -- turn those resources into market weapons.
    if displayCategory == "material" or displayCategory == "materialweapon" then
        return resolved("Resource", "root_material_display")
    end

    if hasTagAlias(ctx, "paint") or displayCategory == "paint"
        or contains(replaceOnDeplete, "paintbucketempty") then
        return resolved("Resource", "root_material_paint")
    end

    if fluidCategory == "dyes" or fluidCategory == "hairdyes" then
        return resolved("Resource", "root_material_fluid")
    end

    if fluidCategory == "fuel" then
        return resolved("Resource", "root_fuel_fluid")
    end

    if (ctx.lootTypeLower or "") == "material" then
        return resolved("Resource", "root_material_loot")
    end

    return nil
end

local function ammoRoot(ctx)
    -- Ammo cases are inventory containers, not ammunition. They may carry an
    -- ammo tag, but their container type/capacity is the authoritative root.
    -- Keep this guard before the generic ammo signals because the stage is
    -- intentionally evaluated before containerRoot.
    if itemTypeIs(ctx, "container") then
        return nil
    end
    if (ctx.displayCategoryToken or "") == "ammo"
        or (ctx.ammoTypeLower or "") ~= ""
        or (ctx.magazineTypeLower or "") ~= ""
        or hasTag(ctx, "ammo")
        or hasTag(ctx, "ammocase") then
        return resolved("Weapon", "root_ammo")
    end
    return nil
end

local function medicalRoot(ctx)
    local displayCategory = ctx.displayCategoryToken or ""
    local lootType = ctx.lootTypeLower or ""
    if displayCategory == "firstaid" or displayCategory == "medical"
        or lootType == "medical" or lootType == "firstaid"
        or (tonumber(ctx.bandagePower) or 0) > 0
        or (tonumber(ctx.reduceInfectionPower) or 0) > 0 then
        return resolved("Medical", "root_medical")
    end
    return nil
end

local function foodRoot(ctx)
    -- Filled fluid containers have already been claimed by liquidRoot.  Do
    -- not let the old beverage compatibility path turn them back into Food.
    if ctx.isActualLiquid == true
        or (ctx.fluidTypeStringLower or "") ~= ""
        or (ctx.fluidTypeLower or "") ~= "" then
        return nil
    end

    local sig = MarketSense.Signatures and MarketSense.Signatures.Food or nil
    if sig and type(sig.validateAdmission) == "function" then
        local admission = sig.validateAdmission(ctx)
        if admission and admission.accepted == true then
            return resolved("Food", "root_food")
        end
    end

    return nil
end

local function electronicsRoot(ctx)
    if Signals and type(Signals.electronicsToken) == "function"
        and Signals.electronicsToken(ctx) then
        return resolved("Electronics", "root_electronics")
    end
    return nil
end

local function literatureRoot(ctx)
    local displayCategory = ctx.displayCategoryToken or ""
    if displayCategory == "literature"
        or displayCategory == "skillbook"
        or displayCategory == "cartography"
        or displayCategory == "reciperesource"
        or itemTypeIs(ctx, "literature")
        or itemTypeIs(ctx, "map")
        or ctx.isLiteratureInstance == true
        or (ctx.lootTypeLower or "") == "reciperesource"
        or (ctx.skillTrainedLower or "") ~= ""
        or #(ctx.learnedRecipes or {}) > 0 then
        return resolved("Literature", "root_literature")
    end
    return nil
end

local function apparelRoot(ctx)
    if (ctx.bodyLocationToken or "") ~= ""
        or (ctx.bloodClothingTypeToken or "") ~= ""
        or itemTypeIs(ctx, "clothing") then
        return resolved("Clothing", "root_apparel")
    end
    return nil
end

local function weaponRoot(ctx)
    if (tonumber(ctx.maxDamage) or 0) > 0
        or (ctx.weaponCategories and #ctx.weaponCategories > 0)
        or (ctx.lootTypeLower or "") == "weapon"
        or (ctx.displayCategoryToken or "") == "explosives"
        or (ctx.displayCategoryToken or "") == "weaponpart"
        or itemTypeIs(ctx, "weapon", "handweapon", "weaponpart") then
        return resolved("Weapon", "root_weapon")
    end
    return nil
end

local function toolRoot(ctx)
    local displayCategory = ctx.displayCategoryToken or ""
    local lootType = ctx.lootTypeLower or ""
    if displayCategory == "tool" or displayCategory == "tools"
        or lootType == "tool"
        or hasTagAlias(ctx, "smokable")
        or hasTagAlias(ctx, "cookware") then
        return resolved("Tool", "root_tool")
    end
    return nil
end

local function gardeningToolRoot(ctx)
    if (ctx.displayCategoryToken or "") ~= "gardening" then
        return nil
    end

    -- HandShovel and Scythe are exposed by PZ under Gardening, but their
    -- native weapon/sharpening fields describe tools rather than placeable
    -- garden stock.  Keep ordinary plants, packets and sprays in Building.
    if itemTypeIs(ctx, "weapon")
        or hasTagAlias(ctx, "sharpenable")
        or hasTagAlias(ctx, "scythe")
        or hasTagAlias(ctx, "digplow")
        or hasTagAlias(ctx, "takedirt") then
        return resolved("Tool", "root_gardening_tool")
    end
    return nil
end

local function containerRoot(ctx)
    if (ctx.displayCategoryToken or "") == "watercontainer"
        or itemTypeIs(ctx, "container")
        or (tonumber(ctx.capacity) or 0) > 0
        or (ctx.isFluidContainer == true and ctx.isActualLiquid ~= true)
        or (ctx.canStoreWater == true and ctx.isFluidContainer ~= true) then
        return resolved("Container", "root_container")
    end
    return nil
end

local function hollowBookRoot(ctx)
    if (ctx.displayCategoryToken or "") == "literature"
        and itemTypeIs(ctx, "container") then
        return resolved("Literature", "root_hollow_book")
    end
    if hasTag(ctx, "hollowbook") or hasTag(ctx, "fancybook") then
        return resolved("Literature", "root_hollow_book")
    end
    return nil
end

local function buildingRoot(ctx)
    local displayCategory = ctx.displayCategoryToken or ""
    local itemId = ctx.idLower or ""
    local displayName = ctx.displayNameLower or ""
    local lootType = ctx.lootTypeLower or ""
    local seedNamed = containsAny(itemId, { "bagseed", "seedpacket", "seed" })
        or containsAny(displayName, { "bag seed", "seed packet" })
    local seedEvidence = hasTagAlias(ctx, "seedpacket")
        or hasTagAlias(ctx, "seed")
        or contains(lootType, "seed")
        or (seedNamed and displayCategory == "drugs")
        or (seedNamed and (ctx.isCraftRecipeProduct == true)
            and containsAny(itemId, { "bagseed", "seedpacket" }))

    if displayCategory == "gardening" or hasTagAlias(ctx, "iscompostable")
        or seedEvidence then
        return resolved("Building", "root_building")
    end

    if Signals and type(Signals.buildingToken) == "function"
        and Signals.buildingToken(ctx) then
        return resolved("Building", "root_building")
    end
    return nil
end

local function mementoRoot(ctx)
    if hasTagAlias(ctx, "ismemento") or hasTagAlias(ctx, "plushie") then
        return resolved("Misc", "root_memento")
    end
    return nil
end

function RootArbiter.resolve(ctx)
    if not ctx then
        return resolved("Misc", "root_missing_context")
    end

    local stages = {
        staticOverride,
        liquidRoot,
        materialRoot,
        ammoRoot,
        medicalRoot,
        foodRoot,
        mementoRoot,
        hollowBookRoot,
        containerRoot,
        electronicsRoot,
        gardeningToolRoot,
        buildingRoot,
        literatureRoot,
        apparelRoot,
        weaponRoot,
        toolRoot,
    }

    for _, stage in ipairs(stages) do
        local decision = stage(ctx)
        if decision and decision.root then
            return decision
        end
    end

    return resolved("Misc", "root_fallback")
end

return RootArbiter
