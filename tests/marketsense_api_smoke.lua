local T = require "tests/support/test"
T.addPackagePaths()

_G.unpack = _G.unpack or table.unpack

local scriptItem = {
    fullName = "Base.DescriptionFood",
}

function scriptItem:getFullName() return self.fullName end
function scriptItem:getModuleName() return "Base" end
function scriptItem:getName() return "DescriptionFood" end
function scriptItem:getDisplayCategory() return "Food" end
function scriptItem:getItemType() return "Food" end
function scriptItem:getDisplayName() return "Generic Item" end
function scriptItem:getTooltip() return "Canned preserved bean meal" end
function scriptItem:getFoodType() return "" end
function scriptItem:getHungerChange() return -0.2 end
function scriptItem:getCalories() return 250 end
function scriptItem:getDaysFresh() return 20 end
function scriptItem:getDaysTotallyRotten() return 40 end
function scriptItem:getActualWeight() return 3 end
function scriptItem:getConditionMax() return 10 end
function scriptItem:getLevelSkillTrained() return 3 end

local inventoryItem = {}
function inventoryItem:getDescription() return "Canned preserved bean meal" end
function inventoryItem:getActualWeight() return 0.5 end
function inventoryItem:getCalories() return 180 end
function inventoryItem:getConditionMax() return 99 end
function inventoryItem:isCannedFood() return true end
function inventoryItem:Remove() end

_G.instanceof = function(_, className)
    return className == "Food" or className == "InventoryItem"
end
_G.instanceItem = function(_) return inventoryItem end

local weaponScriptItem = {
    fullName = "Base.HarnessSpear",
}
function weaponScriptItem:getFullName() return self.fullName end
function weaponScriptItem:getModuleName() return "Base" end
function weaponScriptItem:getName() return "HarnessSpear" end
function weaponScriptItem:getDisplayCategory() return "Weapon" end
function weaponScriptItem:getItemType() return "base:weapon" end
function weaponScriptItem:getDisplayName() return "Harness Spear" end
function weaponScriptItem:getWeaponCategories() return { "base:spear", "base:improvised" } end
function weaponScriptItem:getMinDamage() return 1 end
function weaponScriptItem:getMaxDamage() return 2 end
function weaponScriptItem:getMaxRange() return 1.5 end
function weaponScriptItem:getMaxHitCount() return 2 end
function weaponScriptItem:getConditionMax() return 100 end
function weaponScriptItem:getActualWeight() return 1.2 end
function weaponScriptItem:getTooltip() return "a crafted spear" end

local scriptManager = {}
function scriptManager:FindItem(fullType)
    if fullType == scriptItem.fullName then
        return scriptItem
    end
    if fullType == "Base.HarnessSpear" then
        return weaponScriptItem
    end
end
_G.getScriptManager = function() return scriptManager end

local function weaponInstance(condition)
    local item = {}
    function item:getCondition() return condition end
    function item:getConditionMax() return 100 end
    function item:getActualWeight() return 1.2 end
    function item:Remove() end
    return item
end

local api = assert(require "MarketSense/MS_PublicAPI")
T.equal(api, MarketSense, "canonical public API is MarketSense")
MarketSense.Config.MasterList = {
    ["Base.HarnessRegistryItem"] = {
        fullType = "Base.HarnessRegistryItem",
    },
}
T.truthy(MarketSense.Config.MasterList["Base.HarnessRegistryItem"],
    "MarketSense owns the canonical master list")
T.truthy(api.GetPriceDetails(scriptItem.fullName),
    "MarketSense evaluator works as a standalone mod")
local propertyReader = assert(MarketSense.PropertyReader)
local registry = assert(MarketSense.ItemsRegistry)

T.truthy(api.ApplyRuntimeRule({
    overridesById = {
        [scriptItem.fullName] = {
            price = 77,
            tags = { "FoodNonPerishableCanned" },
            stock = { min = 2, max = 4 },
        },
    },
}), "fresh public runtime-rule API")
T.equal(api.GetRuntimeRules().overridesById[scriptItem.fullName].price, 77,
    "public runtime-rule API applies exact price override")
T.truthy(api.ApplyRuntimeRule({
    blacklist = { "Base.HarnessBlocked" },
    whitelist = { "Base.HarnessWhitelistWins" },
}), "public blacklist and whitelist API")
T.truthy(MarketSense.RuntimeRules.isBlacklisted("Base.HarnessBlocked"),
    "blacklist blocks an exact item")
T.falsy(MarketSense.RuntimeRules.isBlacklisted("Base.HarnessWhitelistWins"),
    "whitelist takes precedence over blacklist decisions")

local context = propertyReader.buildContext(scriptItem, inventoryItem)
T.equal(context.itemType, "Food", "PZ Item.getItemType is read")
T.equal(context.lvlSkillTrained, 3, "PZ Item.getLevelSkillTrained is read")
T.equal(context.description, "Canned preserved bean meal", "inventory description is read")
T.equal(context.weight, 0.5, "live weight overrides script weight")
T.equal(context.conditionMax, 99, "live condition overrides script condition")

local details = assert(api.GetPriceDetails(scriptItem.fullName, true))
T.equal(details.category, "Food", "food root")
T.equal(details.primary, "FoodNonPerishableCanned", "description drives canned subtype")
T.equal(details.price, 77, "exact item price override is authoritative")
T.equal(details.stock.min, 2, "item stock override minimum")
T.equal(details.stock.max, 4, "item stock override maximum")
T.equal(type(details.balanceAudit), "table", "audit is present")

local debugDetails = assert(api.DebugItem(scriptItem.fullName, false))
T.equal(debugDetails.availability.status, "uncertain", "debug exposes Lua availability")
T.equal(debugDetails.marketEligible, false, "uncertain item is not market eligible")

local tags = api.GetTags(scriptItem.fullName)
T.equal(tags.primary, details.primary, "public tag primary")
T.equal(tags.category, details.category, "public tag category")

api.ClearRuntimeCache()
local withoutAudit = assert(api.GetPriceDetails(scriptItem.fullName, false))
T.falsy(withoutAudit.balanceAudit, "non-audit result does not include audit")
local withAudit = assert(api.GetPriceDetails(scriptItem.fullName, true))
T.equal(type(withAudit.balanceAudit), "table", "audit cache miss is repaired")

T.falsy(api.GetPriceDetails(nil), "invalid full type is rejected")
T.equal(type(api.IsItemRuntimeDebugEnabled()), "boolean", "debug API is boolean")

local fullCondition = assert(api.GetPriceDetailsForInstance(
    weaponScriptItem.fullName, weaponInstance(100), true
))
local halfCondition = assert(api.GetPriceDetailsForInstance(
    weaponScriptItem.fullName, weaponInstance(50), true
))
local brokenCondition = assert(api.GetPriceDetailsForInstance(
    weaponScriptItem.fullName, weaponInstance(0), true
))
T.equal(fullCondition.primary, "WeaponSpear", "instance pricing keeps spear leaf")
T.equal(fullCondition.weaponEvidence.mechanicalClass, "WeaponSpear", "instance exposes melee evidence")
T.equal(fullCondition.priceHeuristic.model, "weapon_melee_v1", "melee pricing model is exposed")
T.truthy(fullCondition.price > halfCondition.price, "condition curve lowers half-condition price")
T.truthy(halfCondition.price > brokenCondition.price, "condition curve lowers broken price")
T.equal(fullCondition.priceHeuristic.conditionRatio, 1, "full condition ratio is visible")
T.equal(halfCondition.priceHeuristic.conditionRatio, 0.5, "half condition ratio is visible")

registry.state.catalog = {
    items = {
        [scriptItem.fullName] = {
            fullType = scriptItem.fullName,
            category = details.category,
            primary = details.primary,
            price = details.price,
        },
    },
}
local registryDetail = assert(api.GetRegistryDetails(scriptItem.fullName))
T.equal(registryDetail.primary, details.primary, "registry detail lookup")
local allKnown = api.GetAllKnownItems()
T.truthy(allKnown[scriptItem.fullName], "registry known-item lookup")
allKnown[scriptItem.fullName].price = -1
T.truthy(registry.state.catalog.items[scriptItem.fullName].price > 0, "registry returns a copy")

local previousEnsureLoaded = registry.ensureLoaded
local receivedForce
registry.ensureLoaded = function(force)
    receivedForce = force
    return "mock-catalog"
end
T.equal(api.EnsureRuntimeRegistryLoaded(true), "mock-catalog", "registry load wrapper result")
T.equal(receivedForce, true, "registry force flag is forwarded")
registry.ensureLoaded = previousEnsureLoaded

T.finish("marketsense_api_smoke")
