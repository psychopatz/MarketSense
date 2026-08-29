-- Semantic capabilities derived from world-object evidence.
--
-- These are interface facts for MarketSense and future consumers.  They do
-- not alter PZ item categories and they do not change pricing by themselves.
-- A mod can therefore reuse the same behavior signature without matching a
-- vanilla item name.

MarketSense = MarketSense or {}
MarketSense.ItemCapabilities = MarketSense.ItemCapabilities or {}

local Capabilities = MarketSense.ItemCapabilities

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function contains(text, token)
    return string.find(lower(text), lower(token), 1, true) ~= nil
end

local function containsAny(text, tokens)
    for _, token in ipairs(tokens or {}) do
        if contains(text, token) then return true end
    end
    return false
end

local function containsWord(text, token)
    local value = lower(text)
    local word = lower(token)
    return value == word
        or contains(value, " " .. word)
        or contains(value, word .. " ")
end

local function containsWordAny(text, tokens)
    for _, token in ipairs(tokens or {}) do
        if containsWord(text, token) then return true end
    end
    return false
end

local function addUnique(list, seen, value)
    if value and value ~= "" and not seen[value] then
        seen[value] = true
        list[#list + 1] = value
    end
end

local function property(evidence, name)
    return evidence and evidence.properties and evidence.properties[name]
end

local function analyze(ctx)
    local world = ctx and ctx.worldObjectEvidence or nil
    local sprite = lower(world and world.sprite)
    local objectClass = lower(world and world.objectClass)
    local customName = lower(world and world.customName)
    local groupName = lower(world and world.groupName)
    local containerType = lower(world and world.containerType)
    local material = lower(world and world.material or property(world, "Material"))
    local material2 = lower(world and world.material2 or property(world, "Material2"))
    local material3 = lower(world and world.material3 or property(world, "Material3"))
    local itemId = lower(ctx and ctx.idLower)

    local capabilities, requirements, evidence = {}, {}, {}
    local capabilitySet, requirementSet, evidenceSet = {}, {}, {}
    local function addCapability(name, source)
        addUnique(capabilities, capabilitySet, name)
        addUnique(evidence, evidenceSet, source)
    end
    local function addRequirement(name, source)
        addUnique(requirements, requirementSet, name)
        addUnique(evidence, evidenceSet, source)
    end

    local electricMaterial = contains(material3, "electric")
        or contains(material2, "electric") or contains(material, "electric")
    local basicDryerContainer = containerType == "clothingdryerbasic"
    local laundryObject = not basicDryerContainer and (
        containsAny(objectClass, { "clothingwasher", "combinationwasherdryer", "clothingdryer" })
        or containsWordAny(customName, { "washer", "dryer" })
        or containsAny(containerType, { "clothingwasher", "clothingdryer" }))

    if laundryObject then
        if containsAny(objectClass .. " " .. customName .. " " .. containerType, { "washer", "combination" }) then
            addCapability("wash_clothing", "world.laundry.washer")
        end
        if containsAny(objectClass .. " " .. customName .. " " .. containerType, { "dryer" }) then
            addCapability("dry_clothing", "world.laundry.dryer")
        end
        if electricMaterial or containsAny(objectClass, { "washer", "dryer" }) then
            addCapability("electric_appliance", "world.material.electric")
            addRequirement("electricity", "world.laundry.power")
        end
        if contains(containerType, "clothingwasher") or contains(customName, "washer") then
            addRequirement("water_supply", "world.laundry.water")
        end
    elseif containsAny(containerType, { "clothingdryerbasic", "laundry" })
        or (contains(sprite, "laundry") and containsAny(customName, { "bin", "cart" })) then
        addCapability("store_laundry", "world.laundry.storage")
    end

    -- PZ uses IsTable/GenericCraftingSurface for several placeable surfaces,
    -- including counters, dressers, crates, barrels, and appliances.  Those
    -- flags describe placement affordances, not the market-facing furniture
    -- subtype.  Resolve the stronger semantic names/container types first.
    local explicitTable = contains(customName, "table")
        or contains(sprite, "furniture_tables_")
    local counterSurface = containsAny(customName, { "counter", "countertop" })
        or contains(containerType, "counter")
        or contains(sprite, "fixtures_counters_")
    local storageSurface = containsAny(customName, {
        "crate", "barrel", "cabinet", "drawer", "dresser", "locker",
        "shelf", "bookcase", "wardrobe", "storage", "chest",
    }) or containsAny(containerType, {
        "crate", "militarycrate", "barrel", "cabinet", "dresser", "toolcabinet",
        "locker", "storage",
    }) or contains(sprite, "furniture_storage_")
    local applianceSurface = contains(sprite, "appliances_")
        or containsAny(customName, {
            "dishwasher", "washer", "dryer", "microwave", "stove", "oven",
            "fridge", "freezer", "coffeemaker", "toaster",
        })

    if counterSurface then
        addCapability("counter_surface", "world.furniture.counter")
    elseif storageSurface and not explicitTable then
        addCapability("storage_surface", "world.furniture.storage")
    end

    local tableEvidence = explicitTable
        or (world and (world.isTable or world.genericCraftingSurface)
            and not counterSurface and not storageSurface and not applianceSurface)
    if tableEvidence then
        addCapability("table_surface", world and world.isTable and "world.table.is_table"
            or "world.table.custom_name")
    end
    if world and world.genericCraftingSurface then
        addCapability("crafting_surface", "world.table.generic_crafting_surface")
    end
    if world and world.bedType and world.bedType ~= ""
        and (containsAny(itemId, { "futon", "mattress", "bed" })
            or containsAny(customName, { "futon", "mattress", "bed" })) then
        addCapability("sleep_surface", "world.furniture.bed_type")
    end

    if contains(groupName, "fitness")
        or (contains(sprite, "recreational_sports") and contains(customName, "contraption")) then
        addCapability("exercise", "world.recreation.fitness")
    end
    if contains(customName, "drum") or contains(customName, "snare drum")
        or customName == "tom" or customName == "kick"
        or groupName == "kick" or groupName == "tom" or groupName == "snare" then
        addCapability("play_drum", "world.recreation.drum")
    end

    if containsAny(objectClass, { "gurney", "hospitalbed" })
        or contains(customName, "gurney") or contains(itemId, "gurney") then
        addCapability("medical_transport", "world.medical.gurney")
    end
    if contains(customName, "bloodbag") or contains(itemId, "bloodbag") then
        addCapability("blood_collection", "world.medical.bloodbag")
    end

    if contains(customName, "forge") or contains(groupName, "forge") then
        addCapability("forge_heat", "world.crafting.forge")
        addRequirement("fuel_or_fire", "world.crafting.forge_heat")
    end
    if containsAny(customName, { "mixer", "grinder" })
        or containsAny(groupName, { "mortar", "masonry" }) then
        addCapability("masonry_processing", "world.crafting.masonry")
    end
    if containsAny(customName, { "pallet", "road barrier", "road cone", "block" })
        or containsAny(groupName, { "road", "pallet" }) then
        addCapability("material_logistics", "world.infrastructure.material_logistics")
    end
    if containsAny(customName, { "road barrier", "road cone" })
        or contains(itemId, "roadbarrier") or contains(itemId, "roadcone")
        or (contains(customName, "block") and contains(groupName, "road")) then
        addCapability("traffic_control", "world.infrastructure.traffic")
    end

    if contains(customName, "coffin") or contains(itemId, "coffin") then
        addCapability("body_storage", "world.funeral.coffin")
    end
    if contains(customName, "hay") or contains(itemId, "haystack") then
        addCapability("livestock_feed", "world.agriculture.hay")
    end
    if contains(customName, "salt lick") or contains(itemId, "saltlick") then
        addCapability("livestock_supplement", "world.agriculture.salt_lick")
    end
    if contains(itemId, "scarecrow") then
        addCapability("crop_protection", "item.agriculture.scarecrow")
    end
    if containsAny(customName, { "flamingo", "gnome" })
        or containsAny(itemId, { "flamingo", "gnome" }) then
        addCapability("garden_decor", "world.garden.decor")
    end
    if contains(itemId, "skeleton") then
        addCapability("display_skeleton", "item.display.skeleton")
    end

    if contains(customName, "clock") or contains(itemId, "clock") then
        addCapability("time_display", "world.display.clock")
        if electricMaterial then
            addCapability("electric_appliance", "world.clock.electric_material")
            addRequirement("electricity", "world.clock.power")
        end
    end
    if containsAny(customName, { "map", "usa" }) or contains(itemId, "mapusa") then
        addCapability("wall_map", "world.wall.map")
    end
    if containsAny(customName, { "certificate", "degree" }) or containsAny(itemId, { "degree" }) then
        addCapability("wall_certificate", "world.wall.certificate")
    end
    if containsAny(customName, { "noteboard", "cork board", "corkboard" })
        or contains(itemId, "corkboard") then
        addCapability("wall_noticeboard", "world.wall.noticeboard")
    end

    if electricMaterial and not capabilitySet.electric_appliance
        and (contains(sprite, "appliances") or contains(objectClass, "appliance")) then
        addCapability("electric_appliance", "world.appliance.electric_material")
    end

    local available = world and world.available == true or false
    return {
        available = available,
        capabilities = capabilities,
        capabilitySet = capabilitySet,
        requirements = requirements,
        requirementSet = requirementSet,
        evidence = evidence,
        sprite = world and world.sprite or "",
        objectClass = world and world.objectClass or "",
        customName = world and world.customName or "",
        groupName = world and world.groupName or "",
        containerType = world and world.containerType or "",
        powerSource = electricMaterial and "electric" or "",
    }
end

function Capabilities.analyze(ctx)
    return analyze(ctx)
end

return Capabilities
