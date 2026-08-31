local T = require "tests/support/test"
T.addPackagePaths()

local theme = assert(T.load("MarketSense/signatures/TagFilters/MS_filter_Theme.lua"))
local rarity = assert(T.load("MarketSense/signatures/TagFilters/MS_filter_Rarity.lua"))
local availability = assert(require "MarketSense/MS_ItemAvailability")

local function hasTag(tags, wanted)
    for _, tag in ipairs(tags or {}) do
        if tag == wanted then return true end
    end
    return false
end

local function context(fullType, displayName, insulation, windResistance)
    return {
        fullType = fullType,
        fullLower = string.lower(fullType),
        idLower = string.lower(string.match(fullType, "[^%.]+$") or fullType),
        displayNameLower = string.lower(displayName or ""),
        descriptionLower = "",
        displayCategoryLower = "clothing",
        itemTypeLower = "clothing",
        bodyLocationLower = "torso",
        worldStaticModelLower = "",
        worldObjectSpriteLower = "",
        insulation = insulation or 0,
        insulationAvailable = insulation ~= nil,
        windResistance = windResistance or 0,
        windResistanceAvailable = windResistance ~= nil,
    }
end

local function foodContext(fullType, displayName, calories, lipids, proteins,
    carbohydrates, thirstChange)
    return {
        fullType = fullType,
        fullLower = string.lower(fullType),
        idLower = string.lower(string.match(fullType, "[^%.]+$") or fullType),
        displayNameLower = string.lower(displayName or ""),
        descriptionLower = "",
        displayCategoryLower = "food",
        itemTypeLower = "food",
        bodyLocationLower = "",
        worldStaticModelLower = "",
        worldObjectSpriteLower = "",
        isFoodInstance = true,
        hasFoodNutritionEvidence = true,
        calories = calories,
        lipids = lipids,
        proteins = proteins,
        carbohydrates = carbohydrates,
        thirstChange = thirstChange,
    }
end

local guacamole = context("Base.Guacamole", "Guacamole")
local guacamoleResult = theme.apply(guacamole, { tags = {} })
T.falsy(hasTag(guacamoleResult.tags, "Theme.Militia"),
    "guacamole is not militia-themed")
T.falsy(hasTag(guacamoleResult.tags, "Theme.Camouflage"),
    "guacamole is not camouflage-themed")

local noBackpack = context("Base.SCBA_NoBackpack", "SCBA No Backpack")
local noBackpackResult = theme.apply(noBackpack, { tags = {} })
T.falsy(hasTag(noBackpackResult.tags, "Theme.Survival"),
    "no-backpack variant is not survival backpack gear")

local jacket = context("Base.CamoDenimLeatherJacket", "Camo Denim Leather Jacket", 0.85, 0.90)
local jacketResult = theme.apply(jacket, { tags = {} })
T.truthy(hasTag(jacketResult.tags, "Theme.Camouflage"), "camo theme")
T.truthy(hasTag(jacketResult.tags, "Theme.Denim"), "denim theme")
T.truthy(hasTag(jacketResult.tags, "Theme.Leather"), "leather theme")
T.truthy(hasTag(jacketResult.tags, "Theme.Thermal"), "thermal theme")
T.truthy(hasTag(jacketResult.tags, "Theme.Winter"), "high-insulation clothing is winter gear")
T.falsy(hasTag(jacketResult.tags, "Theme.Summer"), "winter jacket is not summer gear")

local summerShirt = context("Base.TShirt", "T-Shirt", 0.15, 0.10)
local summerShirtResult = theme.apply(summerShirt, { tags = {} })
T.truthy(hasTag(summerShirtResult.tags, "Theme.Summer"), "low-insulation shirt is summer gear")
T.falsy(hasTag(summerShirtResult.tags, "Theme.Winter"), "summer shirt is not winter gear")

local missingProtection = context("Base.GenericShirt", "Generic Shirt", 0, 0)
missingProtection.insulationAvailable = false
missingProtection.windResistanceAvailable = false
local missingProtectionResult = theme.apply(missingProtection, { tags = {} })
T.falsy(hasTag(missingProtectionResult.tags, "Theme.Summer"),
    "missing insulation is not treated as low insulation")

local raincoat = context("Base.Raincoat", "Rain Coat", 0.40, 0.20)
local raincoatResult = theme.apply(raincoat, { tags = {} })
T.truthy(hasTag(raincoatResult.tags, "Theme.Rain"), "raincoat is rain gear")

local waterproofJacket = context("Base.WaterproofJacket", "Waterproof Jacket", 0.40, 0.20)
waterproofJacket.waterResistance = 0.75
local waterproofResult = theme.apply(waterproofJacket, { tags = {} })
T.truthy(hasTag(waterproofResult.tags, "Theme.Rain"),
    "measured water resistance identifies rain gear")

local overrideResult = theme.apply(jacket, {
    tags = { "Theme.Police" }, details = { source = "item_override" },
})
T.truthy(hasTag(overrideResult.tags, "Theme.Police"), "explicit theme override")
T.truthy(hasTag(overrideResult.tags, "Theme.Denim"),
    "explicit theme still receives material facet")
T.truthy(hasTag(overrideResult.tags, "Theme.Thermal"),
    "explicit theme still receives numeric facet")

local nutrientFood = foodContext("Base.NutrientMeal", "Nutrient Meal", 500, 25, 30, 45, -0.20)
local nutrientResult = theme.apply(nutrientFood, { tags = {} })
T.truthy(hasTag(nutrientResult.tags, "Theme.HighCalorie"), "high-calorie theme")
T.truthy(hasTag(nutrientResult.tags, "Theme.HighFat"), "high-fat theme")
T.truthy(hasTag(nutrientResult.tags, "Theme.HighProtein"), "high-protein theme")
T.truthy(hasTag(nutrientResult.tags, "Theme.HighCarbohydrate"),
    "high-carbohydrate theme")
T.truthy(hasTag(nutrientResult.tags, "Theme.Hydrating"), "hydrating theme")
T.falsy(hasTag(nutrientResult.tags, "Theme.ThirstInducing"),
    "hydrating food is not thirst-inducing")
T.equal(nutrientResult.details.descriptorEvidence[1].source, "theme_heuristic",
    "numeric descriptor evidence source")

local thirstyFood = foodContext("Base.SaltyMeal", "Salty Meal", 250, 10, 8, 20, 0.25)
local thirstyResult = theme.apply(thirstyFood, { tags = {} })
T.truthy(hasTag(thirstyResult.tags, "Theme.ThirstInducing"),
    "thirst-inducing theme")
T.falsy(hasTag(thirstyResult.tags, "Theme.Hydrating"),
    "thirst-inducing food is not hydrating")

local radioContext = context("Base.WalkieTalkie", "Walkie Talkie", 0, 0)
radioContext.displayCategoryLower = "electronics"
radioContext.itemTypeLower = "electronics"
radioContext.bodyLocationLower = ""
local radioResult = theme.apply(radioContext, { tags = {} })
T.truthy(hasTag(radioResult.tags, "Theme.Communication"),
    "name fallback identifies walkie-talkie communication")

local verifiedRadio = radioContext
verifiedRadio.deviceDataAvailable = true
verifiedRadio.deviceData = { isTwoWay = true }
local verifiedRadioResult = theme.apply(verifiedRadio, { tags = {} })
T.truthy(hasTag(verifiedRadioResult.tags, "Theme.Communication"),
    "runtime two-way flag identifies communication")

local oneWayRadio = context("Base.WalkieTalkieReceiver", "Walkie Talkie Receiver", 0, 0)
oneWayRadio.displayCategoryLower = "electronics"
oneWayRadio.itemTypeLower = "electronics"
oneWayRadio.bodyLocationLower = ""
oneWayRadio.deviceDataAvailable = true
oneWayRadio.deviceData = { isTwoWay = false }
local oneWayResult = theme.apply(oneWayRadio, { tags = {} })
T.falsy(hasTag(oneWayResult.tags, "Theme.Communication"),
    "explicit one-way device data blocks name fallback")

local swimsuit = context("Base.Swimsuit", "Swimsuit", 0.10, 0.10)
local swimsuitResult = theme.apply(swimsuit, { tags = {} })
T.truthy(hasTag(swimsuitResult.tags, "Theme.Swimwear"),
    "swimsuit name identifies swimwear")

local goggles = context("Base.DivingGoggles", "Diving Goggles", 0, 0)
goggles.displayCategoryLower = "accessory"
goggles.itemTypeLower = "normal"
goggles.bodyLocationLower = ""
goggles.displayCategoryToken = "accessory"
local gogglesResult = theme.apply(goggles, { tags = { "Swimwear" } })
T.truthy(hasTag(gogglesResult.tags, "Theme.Swimwear"),
    "resolved swimwear tag identifies goggles")

local seed = context("Base.TomatoSeeds", "Tomato Seeds", 0, 0)
seed.displayCategoryLower = "gardening"
seed.itemTypeLower = "normal"
seed.bodyLocationLower = ""
seed.displayCategoryToken = "gardening"
local seedResult = theme.apply(seed, { tags = { "GardeningSeed" } })
T.truthy(hasTag(seedResult.tags, "Theme.GrowingSeason"),
    "gardening seed identifies growing-season goods")

local trap = context("Base.TrapSnare", "Trap Snare", 0, 0)
trap.displayCategoryLower = "trapping"
trap.itemTypeLower = "normal"
trap.bodyLocationLower = ""
trap.displayCategoryToken = "trapping"
local trapResult = theme.apply(trap, { tags = { "MiscTrapping" } })
T.truthy(hasTag(trapResult.tags, "Theme.HuntingSeason"),
    "trapping tag identifies hunting-season goods")

local genericAmmo = context("Base.223Bullets", "223 Bullets", 0, 0)
genericAmmo.displayCategoryLower = "ammo"
genericAmmo.itemTypeLower = "ammo"
genericAmmo.bodyLocationLower = ""
genericAmmo.displayCategoryToken = "ammo"
local genericAmmoResult = theme.apply(genericAmmo, { tags = {} })
T.falsy(hasTag(genericAmmoResult.tags, "Theme.HuntingSeason"),
    "generic ammunition is not assumed to be hunting ammunition")

local fishingRod = context("Base.FishingRod", "Fishing Rod", 0, 0)
fishingRod.displayCategoryLower = "fishing"
fishingRod.itemTypeLower = "normal"
fishingRod.bodyLocationLower = ""
fishingRod.displayCategoryToken = "fishing"
local fishingResult = theme.apply(fishingRod, { tags = { "MiscFishing" } })
T.truthy(hasTag(fishingResult.tags, "Theme.FishingSeason"),
    "fishing tag identifies fishing-season goods")

local bait = foodContext("Base.Bait", "Bait", 20, 1, 2, 3, 0)
bait.isFishingLure = true
local baitResult = theme.apply(bait, { tags = {} })
T.truthy(hasTag(baitResult.tags, "Theme.FishingSeason"),
    "fishing-lure runtime flag identifies fishing-season goods")

local holiday = context("Base.HalloweenMask", "Halloween Mask", 0.10, 0.10)
local holidayResult = theme.apply(holiday, { tags = {} })
T.truthy(hasTag(holidayResult.tags, "Theme.Holiday"),
    "holiday name identifies holiday goods")

local taggedHoliday = context("Base.SeasonalDecoration", "Seasonal Decoration", 0, 0)
local taggedHolidayResult = theme.apply(taggedHoliday, { tags = { "Halloween" } })
T.truthy(hasTag(taggedHolidayResult.tags, "Theme.Holiday"),
    "resolved holiday tag identifies holiday goods")

availability.state = {
    built = true,
    records = {
        ["Base.RareHarness"] = {
            channels = { loot = true }, references = { "runtime:ProceduralDistributions:Harness.items" },
            exclusions = {}, engineSignals = {}, lootSources = { ProceduralDistributions = true },
            lootEntryCount = 1, lootWeightedEntryCount = 1, lootWeightSum = 1,
            lootRelativeWeightSum = 0.04,
        },
    },
}
local rareResult = rarity.apply(context("Base.RareHarness", "Rare Harness"), { tags = {} })
T.truthy(hasTag(rareResult.tags, "Rarity.Rare"), "loot rarity tag")
T.equal(rareResult.details.rarityEvidence.source, "loot_distribution",
    "loot rarity evidence source")

availability.state = {
    built = true,
    records = {
        ["Base.Copper"] = {
            channels = { loot = true }, references = {}, exclusions = {}, engineSignals = {},
            lootSources = {}, lootEntryCount = 0, lootWeightedEntryCount = 0,
            lootWeightSum = 0, lootRelativeWeightSum = 0,
        },
    },
}
local copperResult = rarity.apply(context("Base.Copper", "Copper"), { tags = {} })
T.truthy(hasTag(copperResult.tags, "Rarity.Common"),
    "copper does not inherit a removed cop substring heuristic")

T.finish("marketsense_descriptor_smoke")
