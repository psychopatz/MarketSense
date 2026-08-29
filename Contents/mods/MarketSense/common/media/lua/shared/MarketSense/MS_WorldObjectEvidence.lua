-- Runtime evidence for items that are represented by world sprites.
--
-- Item scripts only tell us that an item can be moved and which sprite is
-- placed.  The sprite PropertyContainer is where PZ keeps the useful
-- semantic hints: IsoType, CustomName, GroupName, IsTable, containers,
-- materials, and crafting surfaces.  This module is deliberately read-only
-- and defensive so it is safe for both vanilla and workshop sprites.

require "MarketSense/MS_Core"

MarketSense = MarketSense or {}
MarketSense.WorldObjectEvidence = MarketSense.WorldObjectEvidence or {}

local Evidence = MarketSense.WorldObjectEvidence
local Core = MarketSense.Core

local PROPERTY_NAMES = {
    "IsoType", "CustomName", "GroupName", "container", "ContainerCapacity",
    "Material", "Material2", "Material3", "MaterialType", "MoveType",
    "GenericCraftingSurface", "Surface", "BedType", "PickUpTool", "PlaceTool",
    "PickUpLevel", "PickUpWeight", "SpriteGridPos", "waterPiped",
    "MinimumCarSpeedDmg", "ForceSingleItem",
}

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function isTrue(value)
    if value == true then return true end
    local text = lower(value)
    return text == "true" or text == "1" or text == "yes"
end

local function contains(text, token)
    return string.find(lower(text), lower(token), 1, true) ~= nil
end

local function readProperty(container, name)
    if not container then return nil end
    local value = Core.safeCall(container, "get", nil, name)
    if value ~= nil then return value end
    if Core.safeBoolean(container, "has", false, name) then
        -- Empty properties are flags in newtiledefinitions.tiles.txt (for
        -- example IsTable and GenericCraftingSurface).
        return true
    end
    return nil
end

local function readProperties(container)
    local properties = {}
    for _, name in ipairs(PROPERTY_NAMES) do
        local value = readProperty(container, name)
        if value ~= nil then
            properties[name] = value
        end
    end
    return properties
end

local function flag(container, properties, name)
    local methodValue = Core.safeBoolean(container, name == "IsTable" and "isTable" or name, false)
    return methodValue or isTrue(properties[name])
        or Core.safeBoolean(container, "has", false, name)
end

local function unavailable(spriteName, reason)
    return {
        available = false,
        sprite = spriteName or "",
        reason = reason or "world sprite evidence unavailable",
        properties = {},
        isTable = false,
        isTableTop = false,
    }
end

function Evidence.read(spriteName)
    spriteName = tostring(spriteName or "")
    if spriteName == "" then
        return unavailable(spriteName, "item has no WorldObjectSprite")
    end
    if type(getSprite) ~= "function" then
        return unavailable(spriteName, "getSprite API is unavailable")
    end

    local ok, sprite = pcall(getSprite, spriteName)
    if not ok or not sprite then
        return unavailable(spriteName, "sprite was not found")
    end

    local container = Core.safeCall(sprite, "getProperties", nil)
    if not container then
        return unavailable(spriteName, "sprite has no PropertyContainer")
    end

    local properties = readProperties(container)
    local result = {
        available = true,
        sprite = spriteName,
        objectClass = tostring(properties.IsoType or ""),
        customName = tostring(properties.CustomName or ""),
        groupName = tostring(properties.GroupName or ""),
        containerType = tostring(properties.container or ""),
        material = tostring(properties.Material or ""),
        material2 = tostring(properties.Material2 or ""),
        material3 = tostring(properties.Material3 or ""),
        materialType = tostring(properties.MaterialType or ""),
        moveType = tostring(properties.MoveType or ""),
        bedType = tostring(properties.BedType or ""),
        surface = tonumber(properties.Surface) or 0,
        containerCapacity = tonumber(properties.ContainerCapacity) or 0,
        isTable = flag(container, properties, "IsTable"),
        isTableTop = Core.safeBoolean(container, "isTableTop", false),
        genericCraftingSurface = isTrue(properties.GenericCraftingSurface),
        properties = properties,
    }

    -- Keep the compact summary useful even on game builds where a flag is
    -- exposed only through a method rather than a readable property value.
    if result.isTable then result.properties.IsTable = true end
    if result.isTableTop then result.properties.IsTableTop = true end
    if result.genericCraftingSurface then result.properties.GenericCraftingSurface = true end
    return result
end

function Evidence.has(evidence, propertyName)
    return evidence and evidence.properties and evidence.properties[propertyName] ~= nil or false
end

function Evidence.contains(evidence, fieldName, token)
    return evidence and contains(evidence[fieldName], token) or false
end

return Evidence
