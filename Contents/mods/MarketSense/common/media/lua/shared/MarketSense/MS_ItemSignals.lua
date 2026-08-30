-- Shared evidence signals for roots that PZ represents with broad item types.
-- These are intentionally conservative: a name match only becomes a
-- classification when it is paired with an engine/display/placement signal.

require "MarketSense/MS_TagEvidence"

MarketSense = MarketSense or {}
MarketSense.ItemSignals = MarketSense.ItemSignals or {}

local Signals = MarketSense.ItemSignals
local TagEvidence = MarketSense.TagEvidence

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function contains(text, token)
    return string.find(lower(text), lower(token), 1, true) ~= nil
end

local function containsAny(text, tokens)
    for _, token in ipairs(tokens or {}) do
        if contains(text, token) then
            return true
        end
    end
    return false
end

local function joined(fields)
    local values = {}
    for _, value in ipairs(fields or {}) do
        values[#values + 1] = lower(value)
    end
    return table.concat(values, " ")
end

function Signals.hasTag(ctx, token)
    return TagEvidence.has(ctx, token)
end

function Signals.isMoveable(ctx)
    return ctx and ((ctx.itemTypeToken or "") == "moveable" or ctx.isMoveable == true) or false
end

function Signals.text(ctx)
    return joined({
        ctx and ctx.fullLower,
        ctx and ctx.idLower,
        ctx and ctx.displayNameLower,
        ctx and ctx.iconLower,
        ctx and ctx.worldStaticModelLower,
        ctx and ctx.worldObjectSpriteLower,
        ctx and ctx.descriptionLower,
        ctx and ctx.tooltipLower,
    })
end

local function visualText(ctx)
    return joined({
        ctx and ctx.idLower,
        ctx and ctx.displayNameLower,
        ctx and ctx.iconLower,
        ctx and ctx.worldStaticModelLower,
        ctx and ctx.worldObjectSpriteLower,
    })
end

local function hasCapability(ctx, token)
    return ctx and ctx.capabilitySet and ctx.capabilitySet[token] == true or false
end

local function worldEvidence(ctx)
    return ctx and ctx.worldObjectEvidence or nil
end

function Signals.electronicsToken(ctx)
    if not ctx or (ctx.displayCategoryToken or "") == "memento" then
        return nil
    end

    local displayCategory = ctx.displayCategoryToken or ""
    local itemType = ctx.itemTypeToken or ""
    local text = Signals.text(ctx)
    local visual = visualText(ctx)
    local moveable = Signals.isMoveable(ctx)
    if displayCategory == "weaponpart" or itemType == "weaponpart" then
        return nil
    end
    local behaviorElectronic = hasCapability(ctx, "electric_appliance")
    local hasElectronicAdmission = displayCategory == "electronics"
        or displayCategory == "communications"
        or itemType == "radio"
        or itemType == "alarmclock"
        or Signals.hasTag(ctx, "flashlight")
        or (displayCategory == "lightsource" and containsAny(visual, { "flashlight", "penlight" }))
        or (moveable and containsAny(text, {
            "computer", "phone", "speaker", "microphone", "projector",
            "satellite", "tvcamera", "amplifier",
        }))
        or behaviorElectronic

    if not hasElectronicAdmission then
        return nil
    end

    if containsAny(text, { "generator" }) then
        return { token = "ElectronicsGenerator", confidence = 0.96, source = "electronics_generator" }
    end
    if hasCapability(ctx, "wash_clothing") or hasCapability(ctx, "dry_clothing") then
        return { token = "ElectronicsLaundry", confidence = 0.99, source = "electronics_world_laundry" }
    end
    if hasCapability(ctx, "time_display") then
        return { token = "ElectronicsClock", confidence = 0.95, source = "electronics_world_clock" }
    end
    if hasCapability(ctx, "electric_appliance") then
        return { token = "ElectronicsAppliance", confidence = 0.90, source = "electronics_world_appliance" }
    end
    if Signals.hasTag(ctx, "flashlight")
        or (displayCategory == "lightsource" and containsAny(visual, { "flashlight", "penlight" })) then
        return { token = "ElectronicsFlashlight", confidence = 0.94, source = "electronics_flashlight" }
    end
    if containsAny(text, { "battery" }) then
        return { token = "ElectronicsBattery", confidence = 0.95, source = "electronics_battery" }
    end
    if containsAny(text, { "transmitter" }) then
        return { token = "ElectronicsTransmitter", confidence = 0.95, source = "electronics_transmitter" }
    end
    if containsAny(text, { "hairdryer", "hair_dryer", "hairiron", "hair_iron", "flatiron" }) then
        return { token = "ElectronicsPersonal", confidence = 0.93, source = "electronics_personal_appliance_name" }
    end
    if containsAny(text, {
        "remote", "timer", "trigger", "motionsensor", "motion_sensor",
        "homealarm", "home_alarm", "scanner", "keyduplicator",
    }) then
        return { token = "ElectronicsControl", confidence = 0.93, source = "electronics_control_name" }
    end
    if containsAny(text, { "electricwire", "electric_wire", "electronicsscrap", "powerbar" }) then
        return { token = "ElectronicsPower", confidence = 0.91, source = "electronics_power_component_name" }
    end
    if displayCategory == "electronics" and containsAny(text, { "lightbulb", "light_bulb", "bulb" }) then
        return { token = "ElectronicsLight", confidence = 0.96, source = "electronics_lightbulb" }
    end

    if containsAny(text, { "videogame", "video_game", "arcade", "jukebox", "pinball" }) then
        return { token = "ElectronicsEntertainment", confidence = 0.91, source = "electronics_entertainment_name" }
    end

    -- TVs are often declared as base:radio by the PZ scripts. Require a
    -- television visual/name signal so TVCamera does not become a television.
    if containsAny(visual, { "television", "tvblack", "tvwidescreen", "tvantique", "tvwide" }) then
        return { token = "ElectronicsTelevision", confidence = 0.97, source = "electronics_television" }
    end

    if containsAny(text, {
        "hamradio", "manpackradio", "walkietalkie", "walkie_talkie",
        "twoway", "two_way", "cordlessphone", "telephone", "cellphone",
        "pager", "phone",
    }) then
        return { token = "ElectronicsCommunicator", confidence = 0.91, source = "electronics_communicator" }
    end

    if itemType == "radio" or displayCategory == "communications" then
        return { token = "ElectronicsRadio", confidence = 0.92, source = "electronics_radio_type" }
    end

    if containsAny(text, {
        "amplifier", "earbuds", "headphone", "microphone", "speaker",
        "radioreceiver", "receiver",
    }) then
        return { token = "ElectronicsAudio", confidence = 0.91, source = "electronics_audio_name" }
    end

    return { token = "Electronics", confidence = 0.82, source = "electronics_display_or_runtime" }
end

function Signals.buildingToken(ctx)
    if not ctx or (ctx.displayCategoryToken or "") == "memento" then
        return nil
    end

    local displayCategory = ctx.displayCategoryToken or ""
    local text = Signals.text(ctx)
    local visual = visualText(ctx)
    local moveable = Signals.isMoveable(ctx)
    local world = worldEvidence(ctx)
    local placeable = displayCategory == "furniture"
        or displayCategory == "lighting" or displayCategory == "curtains"
        or displayCategory == "camping"
    -- A valid world-object sprite is stronger than a missing or broad display
    -- category.  This is what lets workshop items reuse the same signatures.
    if not placeable and not (moveable and world and world.available and displayCategory == "") then
        return nil
    end

    -- PropertyContainer semantics are evaluated before visual/name fallbacks.
    -- Specific uses win over generic IsTable.  PZ marks some hay stacks and
    -- mannequin displays as table-like for placement, but those are not
    -- market tables.
    if hasCapability(ctx, "store_laundry") then
        return { token = "BuildingFurnitureLaundry", confidence = 0.95, source = "building_world_laundry_storage" }
    end
    if hasCapability(ctx, "exercise") then
        return { token = "BuildingRecreationFitness", confidence = 0.98, source = "building_world_fitness" }
    end
    if hasCapability(ctx, "play_drum") then
        return { token = "BuildingRecreationDrum", confidence = 0.98, source = "building_world_drum" }
    end
    if hasCapability(ctx, "medical_transport") then
        return { token = "BuildingMedicalGurney", confidence = 0.98, source = "building_world_medical_gurney" }
    end
    if hasCapability(ctx, "blood_collection") then
        return { token = "BuildingMedicalBloodbag", confidence = 0.98, source = "building_world_medical_bloodbag" }
    end
    if hasCapability(ctx, "forge_heat") then
        return { token = "BuildingCraftingForge", confidence = 0.96, source = "building_world_forge" }
    end
    if hasCapability(ctx, "masonry_processing") then
        return { token = "BuildingCraftingMasonry", confidence = 0.96, source = "building_world_masonry" }
    end
    if hasCapability(ctx, "traffic_control") then
        return { token = "BuildingInfrastructureTraffic", confidence = 0.97, source = "building_world_traffic" }
    end
    if hasCapability(ctx, "material_logistics") then
        return { token = "BuildingLogisticsPallet", confidence = 0.94, source = "building_world_logistics" }
    end
    if hasCapability(ctx, "body_storage") then
        return { token = "BuildingFuneralCoffin", confidence = 0.98, source = "building_world_coffin" }
    end
    if hasCapability(ctx, "livestock_feed") then
        return { token = "BuildingAgricultureHay", confidence = 0.95, source = "building_world_hay" }
    end
    if hasCapability(ctx, "livestock_supplement") then
        return { token = "BuildingAgricultureLivestock", confidence = 0.95, source = "building_world_livestock" }
    end
    if hasCapability(ctx, "crop_protection") then
        return { token = "BuildingAgricultureScarecrow", confidence = 0.98, source = "building_item_scarecrow" }
    end
    if hasCapability(ctx, "garden_decor") then
        return { token = "BuildingGardenDecor", confidence = 0.95, source = "building_world_garden_decor" }
    end
    if hasCapability(ctx, "display_skeleton") then
        return { token = "BuildingDisplaySkeleton", confidence = 0.98, source = "building_item_skeleton" }
    end
    if hasCapability(ctx, "wall_map") then
        return { token = "BuildingWallDecorMap", confidence = 0.95, source = "building_world_wall_map" }
    end
    if hasCapability(ctx, "wall_certificate") then
        return { token = "BuildingWallDecorCertificate", confidence = 0.95, source = "building_world_wall_certificate" }
    end
    if hasCapability(ctx, "wall_noticeboard") then
        return { token = "BuildingWallDecorNoticeboard", confidence = 0.95, source = "building_world_wall_noticeboard" }
    end
    if hasCapability(ctx, "sleep_surface") then
        return { token = "BuildingFurnitureBed", confidence = 0.93, source = "building_world_bed_type" }
    end
    if hasCapability(ctx, "counter_surface") then
        return { token = "BuildingFurnitureCounter", confidence = 0.99, source = "building_world_counter" }
    end
    if hasCapability(ctx, "storage_surface") then
        return { token = "BuildingFurnitureStorage", confidence = 0.98, source = "building_world_storage" }
    end
    if hasCapability(ctx, "table_surface") then
        return { token = "BuildingFurnitureTable", confidence = 0.99, source = "building_world_table" }
    end

    -- Moveable definitions frequently expose only a sprite and a broad
    -- Furniture display category.  These names are stable object identities,
    -- so they refine the generic Moveable result without inventing a new
    -- world capability.
    if containsAny(visual, { "arcade", "jukebox", "pinball", "popcornmachine" }) then
        return { token = "BuildingRecreation", confidence = 0.90, source = "building_moveable_recreation_name" }
    end
    if containsAny(visual, {
        "vendingmachine", "hotdogmachine", "sodamachine", "waterdispenser",
        "napkindispenser", "toweldispenser",
    }) then
        return { token = "BuildingFixtureAppliance", confidence = 0.88, source = "building_moveable_appliance_name" }
    end
    if containsAny(visual, { "firehydrant", "turnstile", "mailbox", "publicmailbox" }) then
        return { token = "BuildingInfrastructureTraffic", confidence = 0.88, source = "building_moveable_infrastructure_name" }
    end
    if containsAny(visual, { "doghouse", "birdbath", "planter", "plantbed" }) then
        return { token = "BuildingGardenDecor", confidence = 0.88, source = "building_moveable_garden_name" }
    end
    if containsAny(visual, {
        "securityterminal", "securitywallmonitor", "microscope", "cashregister",
        "scalemedical",
    }) then
        return { token = "BuildingDisplay", confidence = 0.84, source = "building_moveable_display_name" }
    end
    if containsAny(visual, {
        "garbagebin", "garbage_bin", "recyclebin", "publicgarbagebin",
        "wheeliebin", "shelving", "shelves", "shoppingbasket", "standingvault",
        "comicsshop", "oakshelves",
    }) then
        return { token = "BuildingFurnitureStorage", confidence = 0.88, source = "building_moveable_storage_name" }
    end
    if containsAny(visual, { "clothesstand", "pegboard" }) then
        return { token = "BuildingFurnitureStorage", confidence = 0.86, source = "building_moveable_storage_fixture" }
    end
    if containsAny(visual, { "counter", "cashregister" }) then
        return { token = "BuildingFurnitureCounter", confidence = 0.86, source = "building_moveable_counter_name" }
    end
    if contains(visual, "keyduplicator") then
        return { token = "BuildingCrafting", confidence = 0.82, source = "building_moveable_crafting_name" }
    end
    if containsAny(visual, { "gravearched", "graveround", "gravesquare", "graveworn", "mirror" }) then
        return { token = "BuildingFurnitureDecor", confidence = 0.86, source = "building_moveable_decor_name" }
    end

    if containsAny(visual, { "mattress", "gymnmat", "gymmat" })
        or contains(text, "tooltip_item_mattress") then
        return { token = "BuildingFurnitureBed", confidence = 0.95, source = "building_furniture_bedding" }
    end
    if Signals.hasTag(ctx, "tentbed")
        or containsAny(visual, { "sleepingbag", "sleeping_bag" })
        or contains(text, "needspackedsleepingbag") then
        return { token = "BuildingSurvivalSleepingBag", confidence = 0.97, source = "building_survival_sleeping_bag" }
    end
    if (displayCategory == "camping" and contains(text, "needspackedtent"))
        or containsAny(visual, {
            "_tent", "tent_", "tentkit", "campingtent", "tentblue", "tentbrown",
            "tentgreen", "tentyellow", "tentcraft",
        })
        or contains(text, "needspackedtent") then
        return { token = "BuildingSurvivalTent", confidence = 0.96, source = "building_survival_tent" }
    end
    if displayCategory == "lighting"
        or containsAny(visual, { "lighting_", "_lamp", "lamp_", "_light", "light_" }) then
        return { token = "BuildingFixtureLighting", confidence = 0.94, source = "building_fixture_lighting" }
    end

    if containsAny(text, { "sink", "toilet", "urinal", "shower", "bathtub", "bath_tub" }) then
        return { token = "BuildingFixturePlumbing", confidence = 0.93, source = "building_fixture_plumbing" }
    end
    if containsAny(text, {
        "aircondition", "air_condition", "stove", "oven", "fridge", "freezer",
        "washer", "dryer", "microwave", "coffeemaker", "coffee_maker", "espresso",
        "toaster", "bbq", "brazier",
    }) then
        return { token = "BuildingFixtureAppliance", confidence = 0.92, source = "building_fixture_appliance" }
    end
    if containsAny(text, {
        "locker", "cabinet", "cupboard", "shelf", "shelves", "shelving", "bookcase", "dresser",
        "wardrobe", "storage", "chest", "binround", "cardboardbox", "crate",
    }) then
        return { token = "BuildingFurnitureStorage", confidence = 0.90, source = "building_furniture_storage" }
    end
    if containsAny(text, { "mattress", "bed", "cot", "futon" }) then
        return { token = "BuildingFurnitureBed", confidence = 0.91, source = "building_furniture_bed" }
    end
    if containsAny(text, { "chair", "stool", "seat", "sofa", "couch" }) then
        return { token = "BuildingFurnitureChair", confidence = 0.91, source = "building_furniture_seating" }
    end
    if displayCategory == "curtains" or containsAny(text, {
        "painting", "poster", "flag", "sign", "trophy", "mannequin", "window",
    }) then
        return { token = "BuildingFurnitureDecor", confidence = 0.86, source = "building_furniture_decor" }
    end
    if moveable then
        return { token = "BuildingMoveable", confidence = 0.78, source = "building_moveable_type" }
    end
    if displayCategory == "furniture" then
        return { token = "BuildingFurniture", confidence = 0.78, source = "building_furniture_display" }
    end
    return nil
end

return Signals
