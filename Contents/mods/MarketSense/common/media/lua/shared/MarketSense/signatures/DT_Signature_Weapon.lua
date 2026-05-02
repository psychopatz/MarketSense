require "MarketSense/DT_Core"

DynamicTrading = DynamicTrading or {}
DynamicTrading.Signatures = DynamicTrading.Signatures or {}

local Core = DynamicTrading.Core
local Signature = {}

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
    local hasWeaponSignal = (ctx.maxDamage or 0) > 0
        or (ctx.maxRange or 0) > 0
        or Core.ctxContains(ctx, {
            "weapon", "ammo", "gun", "pistol", "rifle", "shotgun", "revolver",
            "knife", "blade", "machete", "sword", "katana", "axe", "hatchet",
            "bat", "club", "hammer", "crowbar", "grenade", "molotov", "bomb",
            "shell", "bullet", "cartridge", "magazine", "scope", "sling",
        })

    if not hasWeaponSignal then
        return { matched = false, confidence = 0 }
    end

    if ctx.ammoType ~= "" or Core.ctxContains(ctx, { "pistol", "rifle", "shotgun", "revolver", "firearm" }) then
        return success(0.96, "Weapon.Ranged.Firearm", {
            "Weapon.Ranged.Firearm",
        })
    end

    if Core.ctxContains(ctx, { "ammo", "bullet", "shell", "cartridge" }) then
        return success(0.93, "Weapon.Ranged.Ammo", {
            "Weapon.Ranged.Ammo",
        })
    end

    if Core.ctxContains(ctx, { "scope", "silencer", "sling", "stock", "laser" }) then
        return success(0.86, "Weapon.Part.Accessory", {
            "Weapon.Part.Accessory",
        })
    end

    if Core.ctxContains(ctx, { "grenade", "molotov", "bomb", "explosive" }) then
        return success(0.96, "Weapon.Explosive", {
            "Weapon.Explosive",
        })
    end

    if Core.ctxContains(ctx, { "axe", "hatchet" }) then
        return success(0.88, "Weapon.Melee.Axe", {
            "Weapon.Melee.Axe",
        })
    end

    if Core.ctxContains(ctx, { "knife", "blade", "machete", "sword", "katana" }) then
        return success(0.90, "Weapon.Melee.Blade", {
            "Weapon.Melee.Blade",
        })
    end

    if Core.ctxContains(ctx, { "bat", "club", "hammer", "pipe", "wrench", "crowbar" }) or (ctx.maxDamage or 0) > 0 then
        return success(0.78, "Weapon.Melee.Blunt", {
            "Weapon.Melee.Blunt",
        })
    end

    return { matched = false, confidence = 0 }
end

DynamicTrading.Signatures.Weapon = Signature
return Signature
