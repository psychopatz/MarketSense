-- Shared weapon evidence extracted from the item definition.
--
-- Weapon categories are an orthogonal fact in Project Zomboid: a kitchen
-- knife, garden fork, or umbrella can have combat behavior without being a
-- combat-first market item. Keep this record separate from the final
-- primary label so consumers can query both facts without changing PZ data.

require "MarketSense/MS_TagEvidence"

MarketSense = MarketSense or {}
MarketSense.WeaponEvidence = MarketSense.WeaponEvidence or {}

local Evidence = MarketSense.WeaponEvidence
local TagEvidence = MarketSense.TagEvidence

local function normalize(value)
    local text = string.lower(tostring(value or ""))
    text = string.gsub(text, "^.*[%.:]", "")
    text = string.gsub(text, "^weaponcategory", "")
    return string.gsub(text, "[^%w]", "")
end

local function hasTag(ctx, token)
    return TagEvidence.has(ctx, token)
end

local function contains(ctx, token)
    return string.find(ctx.idLower or "", token, 1, true) ~= nil
end

local function hasCategory(ctx, token)
    for _, value in ipairs(ctx.weaponCategories or {}) do
        if normalize(value) == normalize(token) then return true end
    end
    return false
end

local function addUnique(list, value)
    for _, existing in ipairs(list) do
        if existing == value then return end
    end
    list[#list + 1] = value
end

local function isWeaponLike(ctx)
    return ctx and (
        ctx.itemTypeToken == "weapon"
        or ctx.itemTypeToken == "weaponpart"
        or #((ctx.weaponCategories) or {}) > 0
        or (ctx.maxDamage or 0) > 0
        or (ctx.minDamage or 0) > 0
    )
end

function Evidence.analyze(ctx)
    if not isWeaponLike(ctx) then return nil end

    local class = nil
    local source = nil
    local confidence = 0

    if ctx.itemTypeToken == "weaponpart" or (ctx.displayCategoryToken or "") == "weaponpart" then
        class, source, confidence = "WeaponPart", "weapon_part_type", 0.94
    elseif hasTag(ctx, "firearm") then
        class, source, confidence = "Firearm", "weapon_firearm_tag", 0.97
    elseif hasCategory(ctx, "Axe") then
        class, source, confidence = "WeaponAxe", "weapon_category_axe", 0.96
    elseif hasCategory(ctx, "SmallBlunt") then
        class, source, confidence = "WeaponSmallBlunt", "weapon_category_smallblunt", 0.96
    elseif hasCategory(ctx, "Blunt") then
        class, source, confidence = "WeaponBlunt", "weapon_category_blunt", 0.96
    elseif hasCategory(ctx, "SmallBlade") then
        class, source, confidence = "WeaponSmallBlade", "weapon_category_smallblade", 0.96
    elseif hasCategory(ctx, "LongBlade") then
        class, source, confidence = "WeaponLongBlade", "weapon_category_longblade", 0.96
    elseif hasCategory(ctx, "Spear") then
        class, source, confidence = "WeaponSpear", "weapon_category_spear", 0.96
    elseif hasCategory(ctx, "Unarmed") then
        class, source, confidence = "WeaponUnarmed", "weapon_category_unarmed", 0.96
    elseif hasCategory(ctx, "Improvised") then
        class, source, confidence = "WeaponImprovised", "weapon_category_improvised", 0.92
    elseif hasTag(ctx, "fishingspear") then
        class, source, confidence = "WeaponSpear", "weapon_spear_tag", 0.88
    elseif contains(ctx, "spear") then
        class, source, confidence = "WeaponSpear", "weapon_spear_name", 0.82
    elseif (ctx.minDamage or 0) > 0 or (ctx.maxDamage or 0) > 0 then
        class, source, confidence = "WeaponBlunt", "weapon_damage_fallback", 0.75
    end

    if not class then return nil end

    local traits = {}
    if hasCategory(ctx, "Improvised") then
        addUnique(traits, "WeaponImprovised")
        -- Retain the old token as evidence for existing Market Sense rules;
        -- it is no longer used as the primary folder for improvised-only
        -- weapons.
        addUnique(traits, "WeaponCrafted")
    end

    local role = string.gsub(ctx.displayCategoryToken or "", "weapon$", "")
    if role == "" or role == "weapon" or role == "weaponpart"
        or role == "broken" or role == "hidden" then
        role = nil
    end
    if role == "weaponcrafted" then role = "crafted" end
    if role == "weaponimprovised" then role = "improvised" end

    return {
        mechanicalClass = class,
        mechanicalFamily = class == "Firearm" and "Ranged" or class == "WeaponPart" and "Part" or "Melee",
        traits = traits,
        marketRole = role,
        source = source,
        confidence = confidence,
        nativeCategories = ctx.weaponCategories or {},
    }
end

function Evidence.annotate(ctx, result)
    local evidence = Evidence.analyze(ctx)
    if not evidence then return result end
    result = result or {}
    result.details = result.details or {}
    result.details.weaponEvidence = evidence
    result.details.mechanicalClass = evidence.mechanicalClass
    result.details.mechanicalFamily = evidence.mechanicalFamily
    result.details.mechanicalTraits = evidence.traits
    result.details.marketRole = evidence.marketRole
    return result
end

return Evidence
