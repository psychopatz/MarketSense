require "MarketSense/DT_Core"

DynamicTrading = DynamicTrading or {}
DynamicTrading.Signatures = DynamicTrading.Signatures or {}

local Core = DynamicTrading.Core
local Signature = {}

local MATERIAL_DISPLAY_CATS = { ["material"] = true, ["reciperesource"] = true, ["materialweapon"] = true }
local FURNITURE_DISPLAY_CATS = { ["furniture"] = true }
local VEHICLE_DISPLAY_CATS = { ["vehiclemaintenance"] = true }
local GARDEN_DISPLAY_CATS = { ["gardening"] = true }
local SURVIVAL_DISPLAY_CATS = { ["camping"] = true }
local TRAPPING_DISPLAY_CATS = { ["trapping"] = true }
local FIXTURE_DISPLAY_CATS = { ["household"] = true }

local MATERIAL_ID = {
    "plank", "lumber", "timber", "log", "beam", "nail", "nails", "screw", "screws", "bolt", "nut", "rivet",
    "wire", "barbedwire", "sheet", "metalsheet", "steelsheet", "rebar", "rod", "bar", "concrete", "cement", "brick",
    "cinder", "grout", "tile", "drywall", "sheetrock", "glasspanel", "glassshard", "insulation", "caulk", "ducttape", "glue",
}
local FIXTURE_ID = {
    "valve", "pipe", "plumbingpipe", "doorknob", "doorhinge", "hinge", "hasp", "padlock", "drawer", "cabinethandle",
    "lightbulb", "lightswitch", "electricwire", "electricbox", "powerboxpart", "homealarm",
}
local FURNITURE_ID = { "mattress", "rug", "curtain", "blind", "lamp", "lantern", "shelf", "rack", "cabinet", "frame", "pictureframe" }
local VEHICLE_PART_ID = { "enginedoor", "engineparts", "frontwindow", "lugwrench", "jack", "tirepatch", "tirerepair", "brakefluid", "coolant" }
local SEED_ID = { "seed", "bagseed", "seedpacket", "seedpouch", "bulb", "sapling", "sprout", "cutting" }
local GARDEN_ID = { "fertilizer", "compost", "peatmoss", "planter", "trough", "herb", "croprow" }
local SURVIVAL_ID = { "sleepingbag", "tent", "bedroll" }

local MOVEABLE_FIXTURE_ID = {
    "sink", "shower", "toilet", "urinal", "waterdispenser", "fridge", "freezer", "oven", "stove", "microwave", "washer",
    "dryer", "dishwasher", "locker", "vendingmachine", "toaster", "phone",
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

local function getFixtureSubtype(itemLower)
    if containsAny(itemLower, { "sink", "shower", "toilet", "urinal", "pipe", "valve", "plumbing" }) then return "Plumbing" end
    if containsAny(itemLower, { "fridge", "freezer", "oven", "stove", "microwave", "washer", "dryer", "dishwasher", "toaster", "vending" }) then return "Appliance" end
    if containsAny(itemLower, { "phone", "alarm" }) then return "Communication" end
    if containsAny(itemLower, { "lightbulb", "lightswitch", "electricwire", "electricbox", "powerbox" }) then return "Electrical" end
    if containsAny(itemLower, { "doorknob", "hinge", "hasp", "padlock", "cabinethandle", "drawer" }) then return "Hardware" end
    if containsAny(itemLower, { "locker" }) then return "Storage" end
    return "General"
end

local function getFurnitureSubtype(itemLower)
    if string.find(itemLower, "bench", 1, true) ~= nil and string.find(itemLower, "benchgrinder", 1, true) == nil then return "Bench" end
    if containsAny(itemLower, { "chair", "stool" }) then return "Chair" end
    if containsAny(itemLower, { "counter" }) then return "Counter" end
    if containsAny(itemLower, { "table" }) then return "Table" end
    if containsAny(itemLower, { "cabinet", "drawers", "dresser", "shelf", "bookcase", "wardrobe", "crate", "mailbox" }) then return "Storage" end
    if containsAny(itemLower, { "mattress", "bed", "futon", "coffin" }) then return "Bed" end
    if containsAny(itemLower, { "curtain", "lamp", "clock", "mirror", "poster", "painting", "sign", "flag", "frame", "skull", "antlers", "vase", "neon" }) then return "Decor" end
    return "General"
end

local function success(confidence, primary, tags)
    return {
        matched = true,
        confidence = confidence,
        category = "Building",
        primary = primary,
        tags = tags,
    }
end

function Signature.match(ctx)
    local itemLower = tostring(ctx.idLower or "")
    local displayCategory = tostring(ctx.displayCategoryLower or "")

    if (tonumber(ctx.minDamage) or 0) >= 0.5 or (tonumber(ctx.maxDamage) or 0) >= 0.5 then
        return { matched = false, confidence = 0 }
    end
    if (ctx.itemTypeLower or "") == "weapon" or (ctx.itemTypeLower or "") == "base:weapon" then
        return { matched = false, confidence = 0 }
    end
    if (ctx.bodyLocationLower or "") ~= "" then
        return { matched = false, confidence = 0 }
    end
    if (tonumber(ctx.hunger) or 0) > 0 or (tonumber(ctx.thirst) or 0) > 0 then
        return { matched = false, confidence = 0 }
    end
    if displayCategory == "lightsource" or displayCategory == "firesource" or displayCategory == "electronics" then
        return { matched = false, confidence = 0 }
    end
    if string.find(itemLower, "battery", 1, true) ~= nil then
        return { matched = false, confidence = 0 }
    end
    if (ctx.ammoTypeLower or "") ~= "" then
        return { matched = false, confidence = 0 }
    end

    local primary = "Building.Material"
    local tags = {}

    if ctx.isMoveable or string.sub(itemLower, 1, 4) == "mov_" then
        if GARDEN_DISPLAY_CATS[displayCategory] then
            primary = "Building.Garden"
            return success(0.90, primary, { primary })
        end
        if containsAny(itemLower, MOVEABLE_FIXTURE_ID) then
            primary = "Building.Fixture." .. getFixtureSubtype(itemLower)
            return success(0.91, primary, { primary })
        end
        local furnSubtype = getFurnitureSubtype(itemLower)
        if furnSubtype ~= "General" then
            primary = "Building.Furniture." .. furnSubtype
            return success(0.90, primary, { primary })
        end
        primary = "Building.Moveable"
        return success(0.95, primary, { primary })
    end

    if TRAPPING_DISPLAY_CATS[displayCategory] then
        primary = "Building.Survival.Trap"
        return success(0.88, primary, { primary })
    end

    if SURVIVAL_DISPLAY_CATS[displayCategory] and containsAny(itemLower, SURVIVAL_ID) then
        primary = "Building.Survival"
        return success(0.86, primary, { primary })
    end

    if MATERIAL_DISPLAY_CATS[displayCategory] then
        primary = "Building.Material"
        return success(0.90, primary, { primary })
    end
    if FURNITURE_DISPLAY_CATS[displayCategory] then
        primary = "Building.Furniture." .. getFurnitureSubtype(itemLower)
        return success(0.85, primary, { primary })
    end
    if VEHICLE_DISPLAY_CATS[displayCategory] then
        primary = "Building.Vehicle"
        return success(0.85, primary, { primary })
    end
    if GARDEN_DISPLAY_CATS[displayCategory] then
        if containsAny(itemLower, SEED_ID) then
            primary = "Building.Garden.Seed"
            return success(0.88, primary, { primary })
        end
        primary = "Building.Garden"
        return success(0.85, primary, { primary })
    end
    if FIXTURE_DISPLAY_CATS[displayCategory] then
        primary = "Building.Fixture." .. getFixtureSubtype(itemLower)
        return success(0.80, primary, { primary })
    end

    if containsAny(itemLower, MATERIAL_ID) then
        primary = "Building.Material"
        return success(0.80, primary, { primary })
    end
    if containsAny(itemLower, FIXTURE_ID) then
        primary = "Building.Fixture." .. getFixtureSubtype(itemLower)
        return success(0.78, primary, { primary })
    end
    if containsAny(itemLower, VEHICLE_PART_ID) then
        primary = "Building.Vehicle"
        return success(0.78, primary, { primary })
    end
    if containsAny(itemLower, SEED_ID) then
        primary = "Building.Garden.Seed"
        return success(0.78, primary, { primary })
    end
    if containsAny(itemLower, GARDEN_ID) then
        primary = "Building.Garden"
        return success(0.75, primary, { primary })
    end
    if containsAny(itemLower, FURNITURE_ID) then
        primary = "Building.Furniture." .. getFurnitureSubtype(itemLower)
        return success(0.72, primary, { primary })
    end

    if Core.ctxContains(ctx, { "steelmaterial", "hasmetal", "toolhead", "glass" }) then
        primary = "Building.Material"
        return success(0.70, primary, { primary })
    end

    return { matched = false, confidence = 0 }
end

DynamicTrading.Signatures.Building = Signature
return Signature
