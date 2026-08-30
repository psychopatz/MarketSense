require "MarketSense/signatures/tags/MS_TagMapper"
require "MarketSense/MS_TagEvidence"

MarketSense = MarketSense or {}
MarketSense.Signatures = MarketSense.Signatures or {}

local Signature = {}
local TagMapper = MarketSense.TagMapper
local TagEvidence = MarketSense.TagEvidence

local WEAPON_COMBO_CATS = {
    animalpart=true, cooking=true, firstaid=true, fishing=true,
    gardening=true, household=true, instrument=true, junk=true,
    material=true, sports=true, vehiclemaintenance=true,
    tool=true, toolblacksmith=true, toolbutchering=true, toolcarpentry=true,
    toolflintknapping=true, toolgardening=true, toolmaintenance=true,
    toolmasonry=true, toolmechanics=true, toolpottery=true, tooltailoring=true,
    toolwelding=true,
}

local function itemTypeIs(ctx, ...)
    local t = ctx.itemTypeToken or ""
    for _, v in ipairs({...}) do if t == v then return true end end
    return false
end

local function hasTag(ctx, token)
    return TagEvidence.has(ctx, token)
end

local function idContains(ctx, sub)
    return string.find(ctx.idLower or "", sub, 1, true) ~= nil
end

local function normalizeWeaponToken(value)
    local token = string.lower(tostring(value or ""))
    -- Accept both Java enum text (WeaponCategory.Spear) and item-script
    -- category text (base:spear), then ignore separators.
    token = string.gsub(token, "^.*[%.:]", "")
    token = string.gsub(token, "^weaponcategory", "")
    return string.gsub(token, "[^%w]", "")
end

local function weaponCatIs(ctx, ...)
    for _, wc in ipairs(ctx.weaponCategories or {}) do
        local wcl = normalizeWeaponToken(wc)
        for _, v in ipairs({...}) do
            if wcl == normalizeWeaponToken(v) then return true end
        end
    end
    return false
end

function Signature.match(ctx)
    if itemTypeIs(ctx, "weaponpart") or (ctx.displayCategoryToken or "") == "weaponpart" then
        return TagMapper.makeResult("WeaponPart", 0.94, { source = "weapon_part_type" })
    end
    if not itemTypeIs(ctx, "weapon") then return { matched = false, confidence = 0 } end
    -- BareHands intentionally has no maintenance XP but is still an
    -- explicit native weapon category. Handle it before the generic
    -- maintenance-XP exclusion so it gets its own melee leaf.
    if weaponCatIs(ctx, "Unarmed") then
        return TagMapper.makeResult("WeaponUnarmed", 0.96, { source = "weapon_melee_unarmed" })
    end
    -- Firearm
    if hasTag(ctx, "firearm") then
        local ammoLower = ctx.ammoTypeLower or ""
        if ctx.isTwoHandWeapon then
            if ammoLower:find("shell") or ammoLower:find("slug") or idContains(ctx, "shotgun") then
                return TagMapper.makeResult("FirearmShotgun", 0.97, { source = "firearm_shotgun" })
            end
            return TagMapper.makeResult("FirearmRifle", 0.97, { source = "firearm_rifle" })
        end
        return TagMapper.makeResult("FirearmHandgun", 0.97, { source = "firearm_handgun" })
    end

    if (ctx.displayCategoryToken or "") == "brokenweapon" then
        return TagMapper.makeResult("BrokenWeapon", 0.99, { source = "broken_weapon" })
    end

    -- Melee by weapon category enum
    local cat = nil
    if weaponCatIs(ctx, "Axe") then cat = "WeaponAxe"
    elseif weaponCatIs(ctx, "SmallBlunt") then cat = "WeaponSmallBlunt"
    elseif weaponCatIs(ctx, "Blunt") then cat = "WeaponBlunt"
    elseif weaponCatIs(ctx, "SmallBlade") then cat = "WeaponSmallBlade"
    elseif weaponCatIs(ctx, "LongBlade") then cat = "WeaponLongBlade"
    elseif weaponCatIs(ctx, "Spear") then cat = "WeaponSpear"
    elseif weaponCatIs(ctx, "Improvised") then cat = "WeaponImprovised"
    end

    if cat then
        local orig = ctx.displayCategoryToken or ""
        if orig ~= "" and WEAPON_COMBO_CATS[orig] then
            return TagMapper.makeResult(cat, 0.90, { source = "weapon_melee_combo", orig = orig })
        end
        return TagMapper.makeResult(cat, 0.96, { source = "weapon_melee" })
    end

    -- Native weapon categories are authoritative even when PZ suppresses
    -- maintenance XP (common for improvised or specialty weapons).  The
    -- material-root gate handles MaterialWeapon stock before this signature;
    -- this guard only rejects uncategorized weapon-shaped definitions.
    if hasTag(ctx, "nomaintenancexp") then return { matched = false, confidence = 0 } end

    -- Some Workshop weapons omit Categories but retain a strong spear signal.
    -- Keep this below authoritative categories so a mod can use a custom
    -- display category without losing the weapon's actual melee subtype.
    if hasTag(ctx, "fishingspear") then
        return TagMapper.makeResult("WeaponSpear", 0.88, { source = "weapon_melee_spear_tag" })
    end
    if idContains(ctx, "spear") then
        return TagMapper.makeResult("WeaponSpear", 0.82, { source = "weapon_melee_spear_name" })
    end

    if (ctx.minDamage or 0) > 0 or (ctx.maxDamage or 0) > 0 then
        return TagMapper.makeResult("WeaponBlunt", 0.75, { source = "weapon_damage_fallback" })
    end

    return { matched = false, confidence = 0 }
end

MarketSense.Signatures.Weapon = Signature
return Signature
