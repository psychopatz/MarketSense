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

local scriptManager = {}
function scriptManager:FindItem(fullType)
    if fullType == scriptItem.fullName then
        return scriptItem
    end
end
_G.getScriptManager = function() return scriptManager end

_G.DynamicTrading = {
    Log = function() end,
}

local api = assert(require "MarketSense/MS_PublicAPI")
local propertyReader = assert(MarketSense.PropertyReader)
local registry = assert(MarketSense.ItemsRegistry)

T.truthy(api.ApplyRuntimeRule({
    overridesById = {
        [scriptItem.fullName] = { price = 77 },
    },
}), "fresh public runtime-rule API")
T.equal(api.GetRuntimeRules().overridesById[scriptItem.fullName].price, 77,
    "public runtime-rule API applies overrides")

local context = propertyReader.buildContext(scriptItem, inventoryItem)
T.equal(context.itemType, "Food", "PZ Item.getItemType is read")
T.equal(context.lvlSkillTrained, 3, "PZ Item.getLevelSkillTrained is read")
T.equal(context.description, "Canned preserved bean meal", "inventory description is read")
T.equal(context.weight, 0.5, "live weight overrides script weight")
T.equal(context.conditionMax, 99, "live condition overrides script condition")

local details = assert(api.GetPriceDetails(scriptItem.fullName, true))
T.equal(details.category, "Food", "food root")
T.equal(details.primary, "FoodNonPerishableCanned", "description drives canned subtype")
T.truthy(details.price > 0, "generated price")
T.equal(type(details.balanceAudit), "table", "audit is present")

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
