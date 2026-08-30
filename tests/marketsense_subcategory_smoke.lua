local T = require "tests/support/test"
T.addPackagePaths()

local classifier = assert(T.load("MarketSense/signatures/tags/MS_Classifier.lua"))
local mapper = assert(MarketSense.TagMapper)

local function context(id, props)
    props = props or {}
    local tags = props.tags or {}
    local normalizedTags = {}
    for _, tag in ipairs(tags) do
        local suffix = string.lower(tostring(tag)):match("([^:.]+)$") or tostring(tag)
        suffix = string.gsub(suffix, "[^%w]", "")
        normalizedTags[suffix] = true
        normalizedTags["base" .. suffix] = true
    end
    return {
        fullLower = string.lower("Base." .. id), idLower = string.lower(id),
        displayNameLower = string.lower(props.displayName or id),
        descriptionLower = string.lower(props.description or ""),
        iconLower = string.lower(props.icon or ""), tooltipLower = "",
        displayCategoryToken = string.lower(props.displayCategory or ""),
        itemTypeToken = string.lower(props.itemType or ""):match("([^:.]+)$") or "",
        tags = tags, normalizedTags = normalizedTags,
        weaponCategories = props.weaponCategories or {}, learnedRecipes = {},
        capabilitySet = props.capabilitySet or {}, capabilityRequirements = {},
        worldObjectEvidence = props.worldObjectEvidence,
        worldObjectSpriteLower = string.lower(props.worldObjectSprite or ""),
        isMoveable = props.isMoveable == true, isCraftRecipeProduct = props.isCraftRecipeProduct == true,
        isFluidContainer = false, isActualLiquid = false, isFoodInstance = props.isFoodInstance == true,
        isCannedFood = false, isPackaged = false, canAge = false,
        minDamage = props.minDamage or 0, maxDamage = props.maxDamage or 0,
        capacity = props.capacity or 0,
    }
end

local function expect(id, props, primary, path, source)
    local result = assert(classifier.classify(context(id, props)))
    T.equal(result.primary, primary, id .. " primary")
    local definition = mapper.getDefinition(result.primary)
    local categoryPath = definition.root .. "/" .. definition.subcategory
        .. "/" .. definition.leaf .. ".txt"
    T.equal(categoryPath, path, id .. " hierarchy")
    if source then
        T.equal((result.details or {}).source, source, id .. " evidence source")
    end
end

expect("IronBar", {
    itemType = "base:weapon", displayCategory = "MaterialWeapon",
    tags = { "Base:hasmetal", "Base:ironmaterial", "Base:barstock" }, maxDamage = 0.4,
}, "MaterialMetalworking", "Resource/Material/Metalworking.txt", "material_tag_ironmaterial")

expect("BowlingPin", {
    itemType = "base:weapon", displayCategory = "SportsWeapon",
    tags = { "Base:nomaintenancexp" }, weaponCategories = { "Base:improvised", "Base:smallblunt" },
    maxDamage = 0.9,
}, "WeaponSmallBlunt", "Weapon/Melee/SmallBlunt.txt", "weapon_melee")

expect("Cooler", {
    itemType = "base:container", displayCategory = "Container", capacity = 12,
}, "ContainerCooler", "Container/Cooler/Cooler.txt", "container_cooler_name")

expect("Remote", {
    itemType = "base:normal", displayCategory = "Electronics",
}, "ElectronicsControl", "Electronics/Control/Control.txt", "electronics_control_name")

expect("MeasuringTape", {
    itemType = "base:normal", displayCategory = "Tool",
}, "ToolMeasurement", "Tool/Measurement/Measurement.txt", "tool_measurement_name")

expect("GardeningSprayAphids", {
    itemType = "base:drainable", displayCategory = "Gardening",
}, "GardeningPestControl", "Building/Gardening/PestControl.txt", "gardening_spray_name")

expect("HandShovel", {
    itemType = "base:weapon", displayCategory = "Gardening",
    tags = { "Base:sharpenable", "Base:digplow" }, weaponCategories = { "Base:smallblade" },
    maxDamage = 0.4,
}, "ToolGardening", "Tool/Gardening/Gardening.txt", "tool_tag")

expect("HollowBook_Handgun", {
    itemType = "base:container", displayCategory = "Literature",
    tags = { "Base:hollowbook" }, capacity = 2,
}, "LiteratureHollowBookHandgun", "Literature/HollowBook/Handgun.txt", "lit_hollow_book_variant")

expect("FishingHook", {
    itemType = "base:normal", displayCategory = "Fishing",
    tags = { "Base:fishinghook" },
}, "MiscFishing", "Misc/Fishing/Fishing.txt", "misc_display_or_fishing_tag")

local material = classifier.classify(context("IronBar", {
    itemType = "base:weapon", displayCategory = "MaterialWeapon",
    tags = { "Base:ironmaterial" }, maxDamage = 0.4,
}))
T.equal(material.category, "Resource", "material weapon never becomes Weapon")

T.finish("marketsense_subcategory_smoke")
