require "MarketSense/DT_Core"

DynamicTrading = DynamicTrading or {}
DynamicTrading.Signatures = DynamicTrading.Signatures or {}

local Core = DynamicTrading.Core
local Signature = {}

local EXPLOSIVE_ID_PATTERNS = { "aerosol", "grenade", "explosive", "bomb", "molotov", "pipebomb", "smokebomb" }
local AXE_ID_PATTERNS = { "axe", "hatchet", "pickaxe" }
local BLADE_ID_PATTERNS = { "blade", "knife", "machete", "sword", "katana", "scalpel", "cleaver" }
local BLUNT_ID_PATTERNS = { "bat", "club", "hammer", "pipe", "wrench", "crowbar", "mallet", "nightstick", "mace" }
local MAGAZINE_ID_PATTERNS = { "clip", "magazine", "drum" }
local COOKWARE_WEAPON_PATTERNS = {
    "bakingpan", "bakingtray", "fryingpan", "gridlepan", "griddlepan",
    "saucepan", "cookingpot", "roastingpan", "kettle",
}
local COOKWARE_SCRIPT_TAGS = { ["base:cookable"] = true, ["base:canopener"] = true }

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

local function hasMeaningfulValue(value)
    local normalized = Core.lower(tostring(value or ""))
    return normalized ~= "" and normalized ~= "none" and normalized ~= "null" and normalized ~= "nil" and normalized ~= "n/a"
end

local function success(confidence, primary, tags, details)
    return {
        matched = true,
        confidence = confidence,
        category = "Weapon",
        primary = primary,
        tags = tags,
        details = details or {},
    }
end

function Signature.match(ctx)
    local itemLower = tostring(ctx.idLower or "")
    local displayCategory = tostring(ctx.displayCategoryLower or "")
    local itemTypeLower = tostring(ctx.itemTypeLower or "")
    local hasDamage = (ctx.minDamage or 0) > 0 or (ctx.maxDamage or 0) > 0
    local hasAmmoType = hasMeaningfulValue(ctx.ammoTypeLower)
    local hasMagazineType = hasMeaningfulValue(ctx.magazineTypeLower)
    local hasPartMount = hasMeaningfulValue(ctx.mountOnLower) or hasMeaningfulValue(ctx.partTypeLower)
    local isMagazineTag = hasScriptTag(ctx, { ["base:riflemagazine"] = true, ["base:pistolmagazine"] = true })
    local isMagazineName = (containsAny(itemLower, MAGAZINE_ID_PATTERNS) and not containsAny(itemLower, { "magnesium" })) or isMagazineTag
    local isWeaponType = itemTypeLower == "weapon" or itemTypeLower == "base:weapon"

    local cookwareContext = (displayCategory == "cooking" or displayCategory == "cookingweapon")
        and (
            containsAny(itemLower, COOKWARE_WEAPON_PATTERNS)
            or hasScriptTag(ctx, COOKWARE_SCRIPT_TAGS)
            or ctx.isCookable
            or ctx.hasPourType
            or ctx.hasEatType
        )

    if displayCategory == "firstaidweapon" or cookwareContext then
        return { matched = false, confidence = 0 }
    end

    if displayCategory == "weaponpart" or hasPartMount then
        return success(0.95, "Weapon.Part.Accessory", {
            "Weapon.Part.Accessory",
        }, {
            subtype = "Part.Accessory",
            display_category = displayCategory,
        })
    end

    if displayCategory == "ammo" then
        if hasMagazineType or (hasAmmoType and ((ctx.canStackLower or "") == "false" or isMagazineName)) then
            return success(0.95, "Weapon.Part.Ammo", {
                "Weapon.Part.Ammo",
            }, {
                subtype = "Part.Ammo",
                display_category = displayCategory,
            })
        end

        return success(0.90, "Weapon.Ranged.Ammo", {
            "Weapon.Ranged.Ammo",
        }, {
            subtype = "Ranged.Ammo",
            display_category = displayCategory,
        })
    end

    if hasAmmoType and not isWeaponType and not hasDamage then
        if hasMagazineType or (ctx.canStackLower or "") == "false" or isMagazineName then
            return success(0.92, "Weapon.Part.Ammo", {
                "Weapon.Part.Ammo",
            }, {
                subtype = "Part.Ammo",
            })
        end

        return success(0.88, "Weapon.Ranged.Ammo", {
            "Weapon.Ranged.Ammo",
        }, {
            subtype = "Ranged.Ammo",
        })
    end

    if containsAny(itemLower, EXPLOSIVE_ID_PATTERNS) then
        return success(0.95, "Weapon.Explosive", {
            "Weapon.Explosive",
        }, {
            subtype = "Explosive",
        })
    end

    if not (isWeaponType or hasDamage) then
        return { matched = false, confidence = 0 }
    end

    if hasAmmoType
        or (ctx.rangedTokenLower or "") == "true"
        or (ctx.aimedFirearmTokenLower or "") == "true"
        or Core.ctxContains(ctx, { "pistol", "rifle", "shotgun", "revolver", "firearm" })
        or TagUtils.hasTag(ctx.tags, "Firearm") then

        local subtype = "Ranged.Firearm"
        local primary = "Weapon.Ranged.Firearm"

        if ctx.ammoTypeLower:contains("shell") or ctx.idLower:contains("shotgun") then
            primary = "Weapon.Ranged.Shotgun"
            subtype = "Ranged.Shotgun"
        elseif ctx.isTwoHandWeapon then
            primary = "Weapon.Ranged.Rifle"
            subtype = "Ranged.Rifle"
        else
            primary = "Weapon.Ranged.Handgun"
            subtype = "Ranged.Handgun"
        end

        return success(0.96, primary, {
            primary,
        }, {
            subtype = subtype,
        })
    end

    if containsAny(itemLower, AXE_ID_PATTERNS) then
        return success(0.88, "Weapon.Melee.Axe", {
            "Weapon.Melee.Axe",
        }, {
            subtype = "Melee.Axe",
        })
    end

    if containsAny(itemLower, BLADE_ID_PATTERNS) then
        return success(0.90, "Weapon.Melee.Blade", {
            "Weapon.Melee.Blade",
        }, {
            subtype = "Melee.Blade",
        })
    end

    local categories = ctx.weaponCategories or {}
    local hasCat = function(c)
        for _, cat in ipairs(categories) do
            if Core.lower(cat) == Core.lower(c) then return true end
        end
        return false
    end

    if hasCat("Axe") then
        return success(0.98, "Weapon.Melee.Axe", { "Weapon.Melee.Axe" }, { engine_cat = "Axe" })
    end
    if hasCat("Blunt") then
        return success(0.98, "Weapon.Melee.Blunt", { "Weapon.Melee.Blunt" }, { engine_cat = "Blunt" })
    end
    if hasCat("SmallBlunt") then
        return success(0.98, "Weapon.Melee.Blunt", { "Weapon.Melee.Blunt" }, { engine_cat = "SmallBlunt" })
    end
    if hasCat("LongBlade") or hasCat("SmallBlade") then
        return success(0.98, "Weapon.Melee.Blade", { "Weapon.Melee.Blade" }, { engine_cat = "Blade" })
    end
    if hasCat("Spear") then
        return success(0.98, "Weapon.Melee.Spear", { "Weapon.Melee.Spear" }, { engine_cat = "Spear" })
    end

    if containsAny(itemLower, BLUNT_ID_PATTERNS) or hasDamage then
        return success(0.78, "Weapon.Melee.Blunt", {
            "Weapon.Melee.Blunt",
        }, {
            subtype = "Melee.Blunt",
        })
    end

    return { matched = false, confidence = 0 }
end

DynamicTrading.Signatures.Weapon = Signature
return Signature
