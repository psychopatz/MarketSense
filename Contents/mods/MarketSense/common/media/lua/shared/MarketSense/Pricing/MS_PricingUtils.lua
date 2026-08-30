require "MarketSense/MS_Core"

local Core = MarketSense.Core
local Utils = {}

local CATEGORY_BASE_SCORES = {
    Medical = 18, Weapon = 18, Tool = 14,
    Container = 14, Clothing = 4, Electronics = 14, Resource = 5,
    Building = 5, Liquid = 5, Literature = 5, Misc = 2,
}

local function addAudit(audit, label, before, after, extra)
    if not audit then return end
    audit[#audit + 1] = { label = label, before = before, after = after, extra = extra }
end

local function applyAdjustment(value, entry, label, audit)
    if type(entry) ~= "table" then return value end
    local working = value
    if entry.add ~= nil then
        local before = working
        working = working + (tonumber(entry.add) or 0)
        addAudit(audit, label .. " add", before, working)
    end
    if entry.mult ~= nil then
        local before = working
        working = working * math.max(0, tonumber(entry.mult) or 1)
        addAudit(audit, label .. " mult", before, working)
    end
    local minPrice = entry.minPrice or entry.min
    if minPrice ~= nil then
        local before = working
        working = math.max(working, tonumber(minPrice) or working)
        addAudit(audit, label .. " min", before, working)
    end
    return working
end

local function isFoodCategory(category)
    return category == "Food" or category == "Beverage"
end

local function isLiteratureCategory(category)
    return category == "Literature"
end

local function isClothingCategory(category)
    return category == "Clothing"
end

local function isContainerCategory(category)
    return category == "Container"
end

local function clampAndRound(value)
    return Core.round(Core.priceClamp(value))
end

Utils.CATEGORY_BASE_SCORES = CATEGORY_BASE_SCORES
Utils.addAudit = addAudit
Utils.applyAdjustment = applyAdjustment
Utils.isFoodCategory = isFoodCategory
Utils.isLiteratureCategory = isLiteratureCategory
Utils.isClothingCategory = isClothingCategory
Utils.isContainerCategory = isContainerCategory
Utils.clampAndRound = clampAndRound

return Utils
