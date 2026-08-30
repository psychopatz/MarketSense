require "MarketSense/signatures/tags/MS_TagMapper"
require "MarketSense/MS_TagEvidence"

MarketSense = MarketSense or {}
MarketSense.Signatures = MarketSense.Signatures or {}

local Signature = {}
local TagMapper = MarketSense.TagMapper
local TagEvidence = MarketSense.TagEvidence

local AMMO_CONTAINER_TAGS = {
    "ammocase","reloadfastbullets","reloadfastmagazines","reloadfastshells"
}

local function hasTag(ctx, token)
    return TagEvidence.has(ctx, token)
end
local function hasAnyTag(ctx, list)
    for _, t in ipairs(list) do if hasTag(ctx, t) then return true end end
    return false
end
local function itemTypeIs(ctx, t)
    return (ctx.itemTypeToken or "") == t
end
local function contains(text, token)
    return string.find(tostring(text or ""), token, 1, true) ~= nil
end

local function containsAny(text, tokens)
    for _, token in ipairs(tokens or {}) do
        if contains(text, token) then return true end
    end
    return false
end

local function slotIs(ctx, slot)
    local bodyLocation = ctx.bodyLocationToken or ""
    local canBeEquipped = ctx.canBeEquippedLower or ""
    return bodyLocation == slot
        or canBeEquipped == slot
        or canBeEquipped == "base:" .. slot
end

local function bagEvidence(ctx)
    return (ctx.idLower or "") .. " "
        .. (ctx.displayNameLower or "") .. " "
        .. (ctx.descriptionLower or "") .. " "
        .. (ctx.iconLower or "") .. " "
        .. (ctx.worldStaticModelLower or "")
end

local function bagResult(ctx, text)
    local displayCategory = ctx.displayCategoryToken or ""
    local isBagCategory = displayCategory == "bag"
    local isBack = slotIs(ctx, "back")
    local isSatchel = slotIs(ctx, "satchel")
    local isFanny = slotIs(ctx, "fannypackfront") or slotIs(ctx, "fannypackback")
    local isBandolier = slotIs(ctx, "webbing")
    local isWornBag = isBack or isSatchel or isFanny or isBandolier

    -- DisplayCategory=Bag is the base-game signal for hand-carried bags,
    -- while the body/equip slots are the stronger signal for worn variants.
    if not isBagCategory and not isWornBag then
        return nil
    end

    if isFanny or contains(text, "fannypack") then
        return TagMapper.makeResult("ContainerBagFanny", 0.97, {
            source = isFanny and "container_bag_body_fanny" or "container_bag_name_fanny",
        })
    end
    if isSatchel or contains(text, "satchel") then
        return TagMapper.makeResult("ContainerBagSatchel", 0.97, {
            source = isSatchel and "container_bag_body_satchel" or "container_bag_name_satchel",
        })
    end
    if isBandolier then
        return TagMapper.makeResult("ContainerBagBandolier", 0.97, {
            source = "container_bag_body_webbing",
        })
    end
    if contains(text, "duffel") or hasTag(ctx, "duffelbag") then
        return TagMapper.makeResult("ContainerBagDuffel", 0.95, {
            source = contains(text, "duffel") and "container_bag_duffel_evidence"
                or "container_bag_duffel_tag",
        })
    end
    if isBack or contains(text, "backpack") or contains(text, "hikingbag")
        or contains(text, "schoolbag") or contains(text, "framepack")
        or contains(text, "alicepack") then
        return TagMapper.makeResult("ContainerBagBackpack", 0.95, {
            source = isBack and "container_bag_body_back" or "container_bag_name_backpack",
        })
    end

    if isBagCategory then
        return TagMapper.makeResult("ContainerBag", 0.88, {
            source = "container_bag_display_category",
        })
    end
    return nil
end

function Signature.match(ctx)
    local waterContainer = (ctx.displayCategoryToken or "") == "watercontainer"
        or ctx.canStoreWater == true
    local emptyFluidContainer = ctx.isFluidContainer == true
        and ctx.isActualLiquid ~= true
        and (ctx.fluidTypeStringLower or "") == ""
        and (ctx.fluidTypeLower or "") == ""
    if not itemTypeIs(ctx, "container") and not waterContainer and not emptyFluidContainer then
        return { matched = false, confidence = 0 }
    end
    if hasTag(ctx, "hollowbook") or hasTag(ctx, "fancybook")
        or (ctx.displayCategoryToken or "") == "literature" then
        return { matched = false, confidence = 0 }
    end

    if hasTag(ctx, "keyring") then
        return TagMapper.makeResult("KeyRing", 0.98, { source = "container_keyring" })
    end

    local bl = ctx.bodyLocationToken or ""
    local hasBag = bl ~= "" or (ctx.bloodClothingTypeToken or ""):find("bag") ~= nil

    -- Keep the old semantic precedence: an ammo case is still an ammo case,
    -- even when the base script also labels it as a Bag.
    if hasBag and hasAnyTag(ctx, AMMO_CONTAINER_TAGS) then
        return TagMapper.makeResult("ContainerWearableAmmo", 0.93, {
            source = "container_wearable_ammo",
        })
    elseif hasTag(ctx, "ismemento") then
        return TagMapper.makeResult("MementoOrContainer", 0.85, { source = "container_memento" })
    elseif hasTag(ctx, "ammocase") then
        return TagMapper.makeResult("ContainerAmmo", 0.93, { source = "container_ammo" })
    end

    local text = bagEvidence(ctx)
    local bag = bagResult(ctx, text)
    if bag then
        return bag
    end

    -- These are inventory containers with stable native names/models but no
    -- wearable bag slot.  Keep liquid and ammo precedence above these family
    -- labels; the names only refine otherwise generic Container rows.
    if containsAny(text, { "firstaidkit", "firstaid_", "firstaid" }) then
        return TagMapper.makeResult("ContainerMedicalKit", 0.94, {
            source = "container_medical_kit_name",
        })
    end
    if contains(text, "cooler") then
        return TagMapper.makeResult("ContainerCooler", 0.94, {
            source = "container_cooler_name",
        })
    end
    if contains(text, "toolroll") then
        return TagMapper.makeResult("ContainerToolRoll", 0.94, {
            source = "container_tool_roll_name",
        })
    end
    if containsAny(text, { "seedbag", "wheatseedsack", "seed_sack" }) then
        return TagMapper.makeResult("ContainerSeedBag", 0.94, {
            source = "container_seed_bag_name",
        })
    end
    if containsAny(text, { "wallet", "handbag", "purse" }) then
        return TagMapper.makeResult("ContainerWallet", 0.92, {
            source = "container_personal_wallet_name",
        })
    end
    if containsAny(text, { "lunchbag", "photoalbum", "oldphotoalbum", "cookiejar" }) then
        return TagMapper.makeResult("ContainerPersonal", 0.88, {
            source = "container_personal_storage_name",
        })
    end
    if contains(text, "parcel") then
        return TagMapper.makeResult("ContainerParcel", 0.93, {
            source = "container_parcel_name",
        })
    end
    if containsAny(text, { "present", "gift" }) then
        return TagMapper.makeResult("ContainerGift", 0.91, {
            source = "container_gift_name",
        })
    end
    if containsAny(text, {
        "bag", "sack", "tote", "grocery", "paperbag", "plasticbag",
        "garbagebag", "laundry", "dicebag", "gembag", "wheatsack",
    }) then
        return TagMapper.makeResult("ContainerBagUtility", 0.86, {
            source = "container_bag_utility_name",
        })
    end
    if containsAny(text, { "dicebag", "gembag", "photoalbum", "cookiejar", "jar" }) then
        return TagMapper.makeResult("ContainerUtility", 0.84, {
            source = "container_utility_name",
        })
    end

    if hasBag then
        return TagMapper.makeResult("ContainerWearable", 0.93, { source = "container_wearable" })
    elseif waterContainer then
        return TagMapper.makeResult("ContainerLiquid", 0.91, { source = "container_water" })
    elseif ctx.isFluidContainer then
        if (ctx.fluidTypeStringLower or "") ~= ""
            or (ctx.fluidTypeLower or "") ~= ""
            or (ctx.fluidCategoryLower or "") ~= "" then
            return { matched = false, confidence = 0 }
        end
        return TagMapper.makeResult("ContainerLiquid", 0.88, { source = "container_liquid" })
    end

    if contains(text, "box") or contains(text, "crate") or contains(text, "case") then
        return TagMapper.makeResult("ContainerBox", 0.85, { source = "container_box" })
    end

    return TagMapper.makeResult("Container", 0.80, { source = "container_generic" })
end

MarketSense.Signatures.Container = Signature
return Signature
