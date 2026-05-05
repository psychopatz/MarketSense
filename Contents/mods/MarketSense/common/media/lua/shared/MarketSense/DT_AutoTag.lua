require "MarketSense/DT_PropertyReader"
require "MarketSense/DT_TagUtils"
require "MarketSense/DT_HeuristicsDB"

DynamicTrading = DynamicTrading or {}
DynamicTrading.AutoTag = DynamicTrading.AutoTag or {}
DynamicTrading.Signatures = DynamicTrading.Signatures or {}

local AutoTag = DynamicTrading.AutoTag
local Core = DynamicTrading.Core
local TagUtils = DynamicTrading.TagUtils
local DB = DynamicTrading.HeuristicsDB

local ROOT_ORDER = {
    "Container",
    "Clothing",
    "Electronics",
    "Literature",
    "Weapon",
    "Food",
    "Medical",
    "Tool",
    "Resource",
    "Building",
}

local ORDER = {
    "Fishing",
    "Medical",
    "Weapon",
    "Food",
    "Container",
    "Clothing",
    "Electronics",
    "Tool",
    "Resource",
    "Literature",
    "Building",
}

local EXACT_PRIMARY_OVERRIDES = {
    ["Base.Bag_RifleCase"] = "Container.Stash.Case",
    ["Base.Bag_RifleCaseCloth"] = "Container.Stash.Case",
    ["Base.Bag_RifleCaseCloth2"] = "Container.Stash.Case",
    ["Base.Bag_RifleCaseClothCamo"] = "Container.Stash.Case",
    ["Base.Bag_RifleCaseGreen"] = "Container.Stash.Case",
    ["Base.Bag_RifleCaseGreen2"] = "Container.Stash.Case",
    ["Base.Bag_RifleCase_Police"] = "Container.Stash.Case",
    ["Base.Bag_RifleCase_Police2"] = "Container.Stash.Case",
    ["Base.Bag_RifleCase_Police3"] = "Container.Stash.Case",
    ["Base.Bag_ProtectiveCaseSmall_Pistol1"] = "Container.Stash.Case",
    ["Base.Bag_ProtectiveCaseSmall_Pistol2"] = "Container.Stash.Case",
    ["Base.Bag_ProtectiveCaseSmall_Pistol3"] = "Container.Stash.Case",
    ["Base.Bag_ProtectiveCaseSmall_Revolver1"] = "Container.Stash.Case",
    ["Base.Bag_ProtectiveCaseSmall_Revolver2"] = "Container.Stash.Case",
    ["Base.Bag_ProtectiveCaseSmall_Revolver3"] = "Container.Stash.Case",
    ["Base.Bag_ProtectiveCaseSmallMilitary_Pistol1"] = "Container.Stash.Case",
    ["Base.Bag_ProtectiveCaseBulkyAmmo_ShotgunShells"] = "Container.Stash.Case",
    ["Base.Bag_AmmoBox_ShotgunShells"] = "Container.Stash.Case",
    ["Base.Bag_ShotgunCaseGreen"] = "Container.Stash.Case",
    ["Base.Bag_ShotgunCaseCloth"] = "Container.Stash.Case",
    ["Base.Bag_ShotgunCaseCloth2"] = "Container.Stash.Case",
    ["Base.Bag_ShotgunCase_Police"] = "Container.Stash.Case",
    ["Base.RifleCase1"] = "Container.Stash.Case",
    ["Base.RifleCase2"] = "Container.Stash.Case",
    ["Base.RifleCase3"] = "Container.Stash.Case",
    ["Base.RifleCase4"] = "Container.Stash.Case",
    ["Base.ShotgunCase1"] = "Container.Stash.Case",
    ["Base.ShotgunCase2"] = "Container.Stash.Case",
    ["Base.PistolCase1"] = "Container.Stash.Case",
    ["Base.PistolCase2"] = "Container.Stash.Case",
    ["Base.PistolCase3"] = "Container.Stash.Case",
    ["Base.RevolverCase1"] = "Container.Stash.Case",
    ["Base.RevolverCase2"] = "Container.Stash.Case",
    ["Base.RevolverCase3"] = "Container.Stash.Case",
    ["Base.Magazine_Firearm"] = "Literature.Book",
    ["Base.Magazine_Firearm_New"] = "Literature.Book",
}

local CONTAINER_BODY_LOCATIONS = {
    ["base:back"] = true,
    ["base:satchel"] = true,
    ["base:fannypackfront"] = true,
    ["base:fannypackback"] = true,
    ["base:webbing"] = true,
    ["base:ammostrap"] = true,
    ["base:shoulderholster"] = true,
    ["base:ankleholster"] = true,
}

local CONTAINER_ID_PATTERNS = {
    "bag_", "backpack", "rucksack", "duffel", "satchel", "handbag", "purse", "briefcase", "cooler",
    "sack", "toolbox", "toolbag", "weaponbag", "medicalbag", "shotgunbag", "lunchbox", "cookiejar",
    "case", "riflecase", "shotguncase", "pistolcase", "revolvercase", "protectivecase", "ammobox",
}
local ELECTRONICS_ID_PATTERNS = {
    "radio", "walkie", "generator", "battery", "electronic", "tv", "television", "computer", "phone",
    "telephone", "camera", "flashlight", "penlight", "handtorch", "lightbulb", "alarm", "clock",
}
local ELECTRONICS_EXCLUDES = {
    ["candle"] = true,
    ["candlelit"] = true,
    ["lighter"] = true,
    ["lighterbbq"] = true,
    ["lighterdisposable"] = true,
    ["lighterfluid"] = true,
    ["propane_refill"] = true,
}
local LITERATURE_ID_PATTERNS = {
    "book", "magazine", "comic", "newspaper", "journal", "vhs", "cd", "cassette", "carddeck", "cards",
}
local WEAPON_ID_PATTERNS = {
    "axe", "hatchet", "knife", "blade", "machete", "sword", "katana", "bat", "club", "hammer", "crowbar",
    "wrench", "grenade", "bomb", "molotov", "pistol", "rifle", "shotgun", "revolver", "firearm",
}
local FOOD_ID_PATTERNS = {
    "food", "meat", "fish", "fruit", "vegetable", "drink", "beverage", "alcohol", "beer", "wine", "juice",
    "coffee", "tea", "milk", "soda", "water", "candy", "chocolate", "cookie", "cake", "soup", "stew",
    "cereal", "bread", "rice", "pasta", "can",
}
local MEDICAL_ID_PATTERNS = {
    "bandage", "bandaid", "pills", "antibiotics", "disinfectant", "alcoholwipe", "vitamin", "splint",
    "comfrey", "plantain", "ginseng", "garlic", "tobacco", "cigarette", "cigar",
}
local TOOL_ID_PATTERNS = {
    "tool", "hammer", "saw", "drill", "wrench", "screwdriver", "shovel", "rake", "hoe", "trowel",
    "pickaxe", "flashlight", "rope", "lock", "key", "crowbar", "tweezers", "forceps", "scalpel",
}
local RESOURCE_ID_PATTERNS = {
    "scrap", "sheet", "ingot", "nails", "nail", "screws", "wire", "plank", "log", "glue", "adhesive",
    "fuel", "charcoal", "propane", "paper", "cloth", "leather", "fabric", "fertilizer", "seed",
}
local BUILDING_ID_PATTERNS = {
    "mov_", "sink", "shower", "toilet", "fridge", "freezer", "oven", "stove", "microwave", "washer",
    "dryer", "dishwasher", "locker", "vending", "mattress", "chair", "table", "cabinet", "dresser",
    "shelf", "tent", "sleepingbag", "bedroll", "trap",
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

local function hasMeaningfulValue(value)
    local normalized = Core.lower(tostring(value or ""))
    return normalized ~= "" and normalized ~= "none" and normalized ~= "null" and normalized ~= "nil" and normalized ~= "n/a"
end

local function buildOverrideResult(primary)
    return TagUtils.normalizeResult({
        matched = true,
        confidence = 1,
        category = TagUtils.categoryFromPrimary(primary),
        primary = primary,
        tags = { primary },
        details = {
            source = "exact_override",
        },
    })
end

local function rootFallback(root)
    local primary = "Misc.General"
    if root == "Container" then
        primary = "Container.General"
    elseif root == "Clothing" then
        primary = "Clothing.General"
    elseif root == "Electronics" then
        primary = "Electronics.Gadget.General"
    elseif root == "Literature" then
        primary = "Literature.Book"
    elseif root == "Weapon" then
        primary = "Weapon.Melee.Blunt"
    elseif root == "Food" then
        primary = "Food.NonPerishable.General"
    elseif root == "Medical" then
        primary = "Medical.Healthcare"
    elseif root == "Tool" then
        primary = "Tool.General"
    elseif root == "Resource" then
        primary = "Resource.Material.General"
    elseif root == "Building" then
        primary = "Building.Moveable"
    end
    return TagUtils.normalizeResult({
        matched = true,
        confidence = 0.4,
        category = root,
        primary = primary,
        tags = { primary },
        details = {
            source = "root_fallback",
            root = root,
        },
    })
end

local function isContainerRoot(ctx)
    local displayCategory = tostring(ctx.displayCategoryLower or "")
    local bodyLocation = tostring(ctx.bodyLocationLower or "")
    local canBeEquipped = tostring(ctx.canBeEquippedLower or "")
    local itemTypeLower = tostring(ctx.itemTypeLower or "")
    local itemLower = tostring(ctx.idLower or "")
    local hasStructure = (tonumber(ctx.capacity) or 0) > 0
        or (tonumber(ctx.weightReduction) or 0) > 0
        or ctx.canStoreWater
        or ctx.hasFluidContainer
        or itemTypeLower == "base:container"
        or itemTypeLower == "container"
        or displayCategory == "container"
        or displayCategory == "bag"
        or tostring(ctx.acceptItemFunctionLower or "") ~= ""

    local wearableBag = CONTAINER_BODY_LOCATIONS[bodyLocation] or CONTAINER_BODY_LOCATIONS[canBeEquipped]
    local cookwareLiquid = (ctx.canStoreWater or ctx.hasFluidContainer)
        and (displayCategory == "cooking" or displayCategory == "cookingweapon")
        and containsAny(itemLower, { "saucepan", "cookingpot", "pot", "kettle" })

    return not cookwareLiquid and (hasStructure or wearableBag or containsAny(itemLower, CONTAINER_ID_PATTERNS))
end

local function isClothingRoot(ctx)
    local bodyLocation = tostring(ctx.bodyLocationLower or "")
    local displayCategory = tostring(ctx.displayCategoryLower or "")
    local itemTypeLower = tostring(ctx.itemTypeLower or "")
    if bodyLocation == "base:wound" or bodyLocation == "base:bandage" or bodyLocation == "base:zeddmg"
        or bodyLocation == "wound" or bodyLocation == "bandage" or bodyLocation == "zeddmg" then
        return false
    end
    return bodyLocation ~= ""
        or displayCategory == "clothing"
        or displayCategory == "accessory"
        or displayCategory == "protectivegear"
        or itemTypeLower == "clothing"
        or itemTypeLower == "base:clothing"
        or itemTypeLower == "base:alarmclockclothing"
end

local function isElectronicsRoot(ctx)
    local itemLower = tostring(ctx.idLower or "")
    local displayCategory = tostring(ctx.displayCategoryLower or "")
    local itemTypeLower = tostring(ctx.itemTypeLower or "")
    if ELECTRONICS_EXCLUDES[itemLower] then
        return false
    end
    return itemTypeLower == "base:radio"
        or itemTypeLower == "radio"
        or displayCategory == "communications"
        or displayCategory == "electronics"
        or displayCategory == "lightsource"
        or containsAny(itemLower, ELECTRONICS_ID_PATTERNS)
end

local function isLiteratureRoot(ctx)
    local itemLower = tostring(ctx.idLower or "")
    local displayCategory = tostring(ctx.displayCategoryLower or "")
    local itemTypeLower = tostring(ctx.itemTypeLower or "")
    if itemTypeLower == "base:container" or itemTypeLower == "container" then
        return false
    end
    if hasMeaningfulValue(ctx.ammoTypeLower) or itemTypeLower == "weapon" or itemTypeLower == "base:weapon" then
        return false
    end
    return itemTypeLower == "literature"
        or itemTypeLower == "base:literature"
        or itemTypeLower == "base:map"
        or displayCategory == "literature"
        or displayCategory == "book"
        or displayCategory == "media"
        or displayCategory == "writing"
        or (ctx.skillTrainedLower or "") ~= ""
        or (#(ctx.learnedRecipes or {}) > 0)
        or containsAny(itemLower, LITERATURE_ID_PATTERNS)
end

local function isWeaponRoot(ctx)
    local itemLower = tostring(ctx.idLower or "")
    local displayCategory = tostring(ctx.displayCategoryLower or "")
    local itemTypeLower = tostring(ctx.itemTypeLower or "")
    if string.sub(itemLower, 1, 7) == "zeddmg_" then
        return false
    end
    if itemTypeLower == "base:container" or itemTypeLower == "container" or displayCategory == "container" or displayCategory == "bag" then
        return false
    end
    if itemTypeLower == "literature" or itemTypeLower == "base:literature" or displayCategory == "literature" then
        return false
    end
    return not hasScriptTag(ctx, { ["base:nomaintenancexp"] = true })
        and (itemTypeLower == "weapon"
        or itemTypeLower == "base:weapon"
        or displayCategory == "weapon"
        or displayCategory == "ammo"
        or displayCategory == "weaponpart"
        or displayCategory == "explosives"
        or hasMeaningfulValue(ctx.ammoTypeLower)
        or hasMeaningfulValue(ctx.magazineTypeLower)
        or hasMeaningfulValue(ctx.partTypeLower)
        or hasMeaningfulValue(ctx.mountOnLower)
        or (tonumber(ctx.minDamage) or 0) > 0
        or (tonumber(ctx.maxDamage) or 0) > 0
        or containsAny(itemLower, WEAPON_ID_PATTERNS))
end

local function isFoodRoot(ctx)
    local itemLower = tostring(ctx.idLower or "")
    local displayCategory = tostring(ctx.displayCategoryLower or "")
    local itemTypeLower = tostring(ctx.itemTypeLower or "")
    return (tonumber(ctx.hunger) or 0) > 0
        or (tonumber(ctx.thirst) or 0) > 0
        or (tonumber(ctx.calories) or 0) > 0
        or (tonumber(ctx.daysFresh) or 0) > 0
        or (tonumber(ctx.daysRotten) or 0) > 0
        or ctx.isCookable
        or itemTypeLower == "food"
        or itemTypeLower == "base:food"
        or itemTypeLower == "eat"
        or itemTypeLower == "eatsmall"
        or displayCategory == "food"
        or containsAny(itemLower, FOOD_ID_PATTERNS)
end

local function isMedicalRoot(ctx)
    local itemLower = tostring(ctx.idLower or "")
    local displayCategory = tostring(ctx.displayCategoryLower or "")
    if displayCategory == "firstaidweapon" then
        return false
    end
    return (tonumber(ctx.bandagePower) or 0) > 0
        or (tonumber(ctx.reduceInfectionPower) or 0) > 0
        or (tonumber(ctx.alcoholPower) or 0) > 0
        or displayCategory == "firstaid"
        or displayCategory == "bandage"
        or containsAny(itemLower, MEDICAL_ID_PATTERNS)
end

local function isToolRoot(ctx)
    local itemLower = tostring(ctx.idLower or "")
    local displayCategory = tostring(ctx.displayCategoryLower or "")
    local itemTypeLower = tostring(ctx.itemTypeLower or "")
    if (tonumber(ctx.capacity) or 0) > 0 or (tonumber(ctx.weightReduction) or 0) > 0 then
        return false
    end
    return displayCategory == "tool"
        or displayCategory == "toolweapon"
        or displayCategory == "cooking"
        or displayCategory == "cookingweapon"
        or displayCategory == "firstaidweapon"
        or itemTypeLower == "drainable"
        or containsAny(itemLower, TOOL_ID_PATTERNS)
end

local function isResourceRoot(ctx)
    local itemLower = tostring(ctx.idLower or "")
    local displayCategory = tostring(ctx.displayCategoryLower or "")
    return displayCategory == "material"
        or displayCategory == "reciperesource"
        or displayCategory == "materialweapon"
        or (tonumber(ctx.fuelValue) or 0) > 0
        or containsAny(itemLower, RESOURCE_ID_PATTERNS)
end

local function isBuildingRoot(ctx)
    local itemLower = tostring(ctx.idLower or "")
    local displayCategory = tostring(ctx.displayCategoryLower or "")
    return ctx.isMoveable
        or displayCategory == "furniture"
        or displayCategory == "vehiclemaintenance"
        or displayCategory == "gardening"
        or displayCategory == "camping"
        or displayCategory == "trapping"
        or displayCategory == "household"
        or containsAny(itemLower, BUILDING_ID_PATTERNS)
end

local function detectRootCandidates(ctx)
    local candidates = {}
    for _, root in ipairs(ROOT_ORDER) do
        local matched = false
        if root == "Container" then
            matched = isContainerRoot(ctx)
        elseif root == "Clothing" then
            matched = isClothingRoot(ctx)
        elseif root == "Electronics" then
            matched = isElectronicsRoot(ctx)
        elseif root == "Literature" then
            matched = isLiteratureRoot(ctx)
        elseif root == "Weapon" then
            matched = isWeaponRoot(ctx)
        elseif root == "Food" then
            matched = isFoodRoot(ctx)
        elseif root == "Medical" then
            matched = isMedicalRoot(ctx)
        elseif root == "Tool" then
            matched = isToolRoot(ctx)
        elseif root == "Resource" then
            matched = isResourceRoot(ctx)
        elseif root == "Building" then
            matched = isBuildingRoot(ctx)
        end

        if matched then
            candidates[#candidates + 1] = root
        end
    end
    return candidates
end

local function resolveRoot(ctx)
    local overridePrimary = EXACT_PRIMARY_OVERRIDES[tostring(ctx.fullType or "")]
    if overridePrimary then
        return TagUtils.categoryFromPrimary(overridePrimary), overridePrimary, true
    end

    local candidates = detectRootCandidates(ctx)
    return candidates[1], nil, false
end

local function addTag(tags, tag)
    if tag and tag ~= "" and not TagUtils.hasTag(tags, tag) then
        tags[#tags + 1] = tag
    end
end

local function addDescriptorTags(ctx, result)
    local tags = TagUtils.unique(result.tags or {})

    if not TagUtils.tagStarts(tags, "Origin") then
        if ctx.moduleName == "Base" then
            addTag(tags, "Origin.Vanilla")
        else
            -- Ensure modId is clean (no spaces/dots) for tagging
            local cleanId = ctx.sourceModId or "Modded"
            cleanId = cleanId:gsub("[%s%.%-]", "")
            
            -- If modId is still just "Base" or "Unknown", try to use component from fullType
            if (cleanId == "Base" or cleanId == "Unknown") and ctx.moduleName ~= "Base" then
                cleanId = ctx.moduleName:gsub("[%s%.%-]", "")
            end
            
            addTag(tags, "Origin." .. cleanId)
        end
    end

    if not TagUtils.tagStarts(tags, "Rarity") then
        if Core.ctxContains(ctx, { "legendary", "artifact", "unique", "rare_item" }) then
            addTag(tags, "Rarity.Legendary")
        elseif Core.ctxContains(ctx, { "katana", "machete", "generator", "military", "diamond", "gold", "hitech", "vintage" }) then
            addTag(tags, "Rarity.Rare")
        elseif Core.ctxContains(ctx, { "pistol", "rifle", "shotgun", "revolver", "backpack", "radio", "walkie", "medical", "reinforced", "industrial" }) then
            addTag(tags, "Rarity.Uncommon")
        else
            addTag(tags, "Rarity.Common")
        end
    end

    if not TagUtils.tagStarts(tags, "Quality") then
        if Core.ctxContains(ctx, { "broken", "trash", "junk", "worn", "rusty", "damaged", "dirty" }) then
            addTag(tags, "Quality.Waste")
        elseif Core.ctxContains(ctx, { "gold", "diamond", "luxury", "premium", "whiskey", "wine", "pristine", "masterwork" }) then
            addTag(tags, "Quality.Luxury")
        elseif Core.ctxContains(ctx, { "sterile", "medical", "surgical" }) and not Core.ctxContains(ctx, { "unsterile", "used" }) then
            addTag(tags, "Quality.Sterile")
        else
            addTag(tags, "Quality.Standard")
        end
    end

    result.tags = TagUtils.unique(tags)
    result.expandedTags = TagUtils.expandHierarchy(result.tags)
    return result
end

function AutoTag.fallback(ctx)
    return TagUtils.normalizeResult({
        matched = false,
        confidence = 0.05,
        category = "Misc",
        primary = "Misc.General",
        tags = {
            "Misc.General"
        },
        details = {
            reason = "No signature matched."
        }
    })
end

function AutoTag.compareSignatures(fullTypeOrContext)
    local ctx = type(fullTypeOrContext) == "table" and fullTypeOrContext.fullType
        and fullTypeOrContext or DynamicTrading.PropertyReader.buildContext(fullTypeOrContext)

    local preferredRoot, preferredPrimary, isExactOverride = resolveRoot(ctx)
    local preferredResult = preferredPrimary and buildOverrideResult(preferredPrimary) or nil
    local best = nil
    local results = {}

    for _, name in ipairs(ORDER) do
        local signature = DynamicTrading.Signatures[name]
        if signature and type(signature.match) == "function" then
            local ok, rawResult = pcall(signature.match, ctx)
            local result = ok and TagUtils.normalizeResult(rawResult) or {
                matched = false,
                confidence = 0,
                category = "Misc",
                primary = "Misc.General",
                tags = { "Misc.General" },
                expandedTags = { "Misc.General", "Misc" },
                details = {
                    error = ok and nil or tostring(rawResult)
                }
            }

            result.signature = name
            results[#results + 1] = result

            if preferredRoot and result.matched and (result.category == preferredRoot or name == preferredRoot) and not preferredResult then
                preferredResult = result
            end
            if result.matched and (not best or result.confidence > best.confidence) then
                best = result
            end
        end
    end

    if preferredRoot and not preferredResult and not isExactOverride then
        preferredResult = rootFallback(preferredRoot)
    end

    return {
        ctx = ctx,
        preferredRoot = preferredRoot,
        preferredResult = preferredResult,
        best = best,
        results = results,
    }
end

function AutoTag.generate(fullTypeOrContext)
    local ctx = type(fullTypeOrContext) == "table" and fullTypeOrContext.fullType
        and fullTypeOrContext or DynamicTrading.PropertyReader.buildContext(fullTypeOrContext)

    local itemOverride = DB.getItem(ctx.fullType)
    if itemOverride and type(itemOverride.tags) == "table" and #itemOverride.tags > 0 then
        return addDescriptorTags(ctx, TagUtils.normalizeResult({
            matched = true,
            confidence = 1,
            category = TagUtils.categoryFromPrimary(itemOverride.tags[1]),
            primary = itemOverride.tags[1],
            tags = itemOverride.tags,
            details = {
                source = "item_override"
            }
        }))
    end

    local comparison = AutoTag.compareSignatures(ctx)
    local best = comparison.preferredResult or comparison.best or AutoTag.fallback(ctx)
    return addDescriptorTags(ctx, TagUtils.normalizeResult(best))
end

return AutoTag
