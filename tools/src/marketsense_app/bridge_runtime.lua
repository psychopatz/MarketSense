local modRoot = assert(arg[1], "MarketSense mod root is required")
package.path = modRoot .. "/common/media/lua/shared/?.lua;" .. package.path
_G.unpack = _G.unpack or table.unpack

local specs = __MARKETSENSE_SPEC_LITERAL__
local sandboxOptions = __MARKETSENSE_SANDBOX_LITERAL__
local yieldRecipes = __MARKETSENSE_YIELD_LITERAL__
local toolRecipeUsage = __MARKETSENSE_TOOL_RECIPE_LITERAL__
local byFullType = {}
local items = {}

local function property(self, key, fallback)
    local value = self._props[key]
    if value == nil then return fallback end
    return value
end

local function listProperty(self, key)
    local value = property(self, key)
    if type(value) == "table" then
        return value
    end
    if type(value) ~= "string" or value == "" then
        return {}
    end

    -- Item scripts store LearnedRecipes as a semicolon-separated string,
    -- while the real PZ API exposes a Java collection. Convert the static
    -- script form into the same one-based Lua collection used by the bridge.
    local values = {}
    for entry in string.gmatch(value, "[^;,]+") do
        local trimmed = string.gsub(entry, "^%s*(.-)%s*$", "%1")
        if trimmed ~= "" then
            values[#values + 1] = trimmed
        end
    end
    return values
end

local methods = {}
function methods.getFullName(self) return self._fullType end
function methods.getName(self) return self._name end
function methods.getModuleName(self) return self._module end
function methods.getDisplayCategory(self) return property(self, "displayCategory", "") end
function methods.getCategories(self) return property(self, "displayCategory", "") end
function methods.getItemType(self) return property(self, "itemType", property(self, "type", "")) end
function methods.getTypeString(self) return property(self, "itemType", property(self, "type", "")) end
function methods.getType(self) return property(self, "itemType", property(self, "type", "")) end
function methods.getDisplayName(self) return property(self, "displayName", self._name) end
function methods.getTooltip(self) return property(self, "tooltip", "") end
function methods.getDescription(self) if self._instance then return property(self, "description", "") end end
function methods.isHidden(self) return property(self, "hidden", false) end
function methods.getObsolete(self) return property(self, "obsolete", false) end
function methods.canSpawnAsLoot(self) return property(self, "canSpawnAsLoot", false) end
-- Offline-only aggregate projected by scan_phases; absent in real PZ items.
function methods.getMarketSenseLootEvidence(self)
    return property(self, "marketSenseLootEvidence", nil)
end
function methods.canBeForaged(self) return property(self, "canBeForaged", false) end
function methods.isCraftRecipeProduct(self) return property(self, "isCraftRecipeProduct", false) end
function methods.getTags(self) return self._tags end
function methods.getAmmoType(self) return property(self, "ammoType", "") end
function methods.getMagazineType(self) return property(self, "magazineType", "") end
function methods.getPartType(self) return property(self, "partType", "") end
function methods.getMountOn(self) return property(self, "mountOn", "") end
function methods.getCanStack(self) return property(self, "canStack", "") end
function methods.getBodyLocation(self) return property(self, "bodyLocation", "") end
function methods.getLootType(self) return property(self, "lootType", "") end
function methods.getEatType(self) return property(self, "eatType", "") end
function methods.getFoodType(self) return property(self, "foodType", "") end
function methods.getIcon(self) return property(self, "icon", "") end
function methods.getIconName(self) return property(self, "icon", "") end
function methods.getLearnedRecipes(self) return listProperty(self, "learnedRecipes") end
function methods.getSkillTrained(self) return property(self, "skillTrained", "") end
function methods.getLevelSkillTrained(self) return property(self, "levelSkillTrained", -1) end
function methods.getLvlSkillTrained(self) return property(self, "levelSkillTrained", -1) end
function methods.getMaxLevelTrained(self) return property(self, "maxLevelTrained", -1) end
function methods.getReadType(self) return property(self, "readType", "") end
function methods.getWorldStaticModel(self) return property(self, "worldStaticModel", "") end
function methods.getWorldObjectSprite(self) return property(self, "worldObjectSprite", "") end
function methods.getBloodClothingType(self) return property(self, "bloodClothingType", "") end
function methods.getOpenSound(self) return property(self, "openSound", "") end
function methods.getCloseSound(self) return property(self, "closeSound", "") end
function methods.getPutInSound(self) return property(self, "putInSound", "") end
function methods.getPourType(self) return property(self, "pourType", "") end
function methods.getDoubleClickRecipe(self) return property(self, "doubleClickRecipe", "") end
function methods.getOpeningRecipe(self) return property(self, "openingRecipe", "") end
function methods.getReplaceOnDeplete(self) return property(self, "replaceOnDeplete", "") end
function methods.getReplaceOnUse(self) return property(self, "replaceOnUse", "") end
function methods.getReplaceOnCooked(self) return property(self, "replaceOnCooked", "") end
function methods.getOnCooked(self) return property(self, "onCooked", "") end
function methods.getEvolvedRecipe(self) return property(self, "evolvedRecipe", "") end
function methods.getEvolvedRecipeName(self) return property(self, "evolvedRecipeName", "") end
function methods.getCanBeEquipped(self) return property(self, "canBeEquipped", "") end
function methods.getAcceptItemFunction(self) return property(self, "acceptItemFunction", "") end
function methods.isRanged(self) return property(self, "ranged", "") end
function methods.getRanged(self) return property(self, "ranged", "") end
function methods.isAimedFirearm(self) return property(self, "aimedFirearm", "") end
function methods.getIsAimedFirearm(self) return property(self, "aimedFirearm", "") end

-- PZ exposes fluid contents through InventoryItem:getFluidContainer(), not
-- through the item script's ordinary scalar properties.  This small bridge
-- mirrors the methods consumed by MS_PropertyReader so the offline evaluator
-- follows the same primary-fluid path as the game.
local fluidMethods = {}
function fluidMethods.getFluidType(self) return self._name end
function fluidMethods.getFluidTypeString(self) return self._name end
function fluidMethods.getCategories(self)
    return property(self._item, "fluidCategories", {})
end

local function fluidNames(item)
    local names = property(item, "fluidTypes", {})
    if type(names) ~= "table" then names = {} end
    if #names == 0 then
        local direct = property(item, "fluidType", "")
        if direct ~= "" then names = { direct } end
    end
    return names
end

local function primaryFluidName(item)
    local names = fluidNames(item)
    local first = names[1]
    if type(first) == "table" then first = first.name or first.fluid or first.type end
    return tostring(first or "")
end

local fluidContainerMethods = {}
function fluidContainerMethods.getContainerName(self)
    return property(self._item, "fluidContainerName", "")
end
function fluidContainerMethods.getCapacity(self)
    return tonumber(property(self._item, "fluidCapacity", 0)) or 0
end
function fluidContainerMethods.getAmount(self)
    local configured = property(self._item, "fluidAmount", nil)
    if configured ~= nil then return tonumber(configured) or 0 end
    local name = primaryFluidName(self._item)
    return name ~= "" and (self:getCapacity()) or 0
end
function fluidContainerMethods.getPrimaryFluidAmount(self)
    local configured = property(self._item, "fluidPrimaryAmount", nil)
    if configured ~= nil then return tonumber(configured) or 0 end
    return self:getAmount()
end
function fluidContainerMethods.getFilledRatio(self)
    local capacity = self:getCapacity()
    if capacity <= 0 then return 0 end
    return math.max(0, math.min(1, self:getAmount() / capacity))
end
function fluidContainerMethods.isEmpty(self)
    return primaryFluidName(self._item) == "" or self:getAmount() <= 0
end
function fluidContainerMethods.isMixture(self)
    local configured = property(self._item, "fluidIsMixture", nil)
    if configured ~= nil then return configured == true end
    return #fluidNames(self._item) > 1
end
function fluidContainerMethods.getPrimaryFluid(self)
    if self:isEmpty() then return nil end
    local name = primaryFluidName(self._item)
    return setmetatable({ _item = self._item, _name = name }, { __index = fluidMethods })
end
function methods.getFluidContainer(self)
    local hasFluidDefinition = property(self, "fluidContainer", false) == true
        or property(self, "fluidType", "") ~= ""
        or type(property(self, "fluidTypes", nil)) == "table"
        or property(self, "canStoreWater", false) == true
    if not hasFluidDefinition then return nil end
    return setmetatable({ _item = self }, { __index = fluidContainerMethods })
end

local numberMethods = {
    getActualWeight="actualWeight", getWeight="actualWeight", getHungerChange="hungerChange",
    getHungChange="hungerChange", getThirstChange="thirstChange",
    getThirstChangeUnmodified="thirstChange", getUnhappyChangeUnmodified="unhappyChange",
    getBoredomChangeUnmodified="boredomChange", getStressChangeUnmodified="stressChange",
    getUnhappyChange="unhappyChange", getBoredomChange="boredomChange",
    getStressChange="stressChange", getCalories="calories", getCarbohydrates="carbohydrates",
    getLipids="lipids", getProteins="proteins", getDaysFresh="daysFresh",
    getDaysTotallyRotten="daysRotten", getMinDamage="minDamage", getMaxDamage="maxDamage",
    getMaxRange="maxRange", getMaxHitCount="maxHitCount", getConditionMax="conditionMax",
    getHitChance="hitChance", getAimingTime="aimingTime", getUseDelta="useDelta",
    getCapacity="capacity", getWeightReduction="weightReduction", getBiteDefense="biteDefense",
    getScratchDefense="scratchDefense", getBulletDefense="bulletDefense",
    getAlcoholPower="alcoholPower", getFatigueChange="fatigueChange",
    getReduceInfectionPower="reduceInfectionPower", getBandagePower="bandagePower",
    getMechanicType="mechanicType", getCondition="condition", getAge="age", getHeat="heat",
}
for methodName, propertyName in pairs(numberMethods) do
    methods[methodName] = function(self) return property(self, propertyName, 0) end
end
-- Clothing protection is optional in script definitions. Keep missing values
-- as nil so classifiers can distinguish "not measured" from a real zero.
function methods.getInsulation(self) return property(self, "insulation", nil) end
function methods.getWindresist(self) return property(self, "windResistance", nil) end
function methods.getWindresistance(self) return property(self, "windResistance", nil) end
function methods.getWindResistance(self) return property(self, "windResistance", nil) end
function methods.getWaterResistance(self) return property(self, "waterResistance", nil) end

local boolMethods = {
    isSpice="spice", isPoison="poison", canAge="canAge",
    canBeWrite="canBeWrite", isCantEat="cantEat", isCookable="cookable", isDrainable="drainable",
    CanStoreWater="canStoreWater", isCanStoreWater="canStoreWater", isCannedFood="cannedFood",
    getCannedFood="cannedFood", isPackaged="packaged", getPackaged="packaged",
    isFishingLure="fishingLure", getFishingLure="fishingLure", isDangerousUncooked="dangerousUncooked",
    getDangerousUncooked="dangerousUncooked", isGoodHot="goodHot", getGoodHot="goodHot",
    isDung="dung", getIsDung="dung", isRotten="rotten", IsRotten="rotten",
    isFrozen="frozen", isCooked="cooked", isBurnt="burnt",
}
for methodName, propertyName in pairs(boolMethods) do
    methods[methodName] = function(self) return property(self, propertyName, false) end
end
-- The script format uses `TwoHandWeapon`, while the runtime-facing bridge
-- historically looked only for a lower-case fixture key. Accept both forms
-- so rifle/shotgun evidence follows the PZ Item/InventoryItem contract.
function methods.isTwoHandWeapon(self)
    return property(self, "TwoHandWeapon", property(self, "twoHandWeapon", false))
end
function methods.getWeaponCategories(self) return listProperty(self, "weaponCategories") end
function methods.getModID(self) return property(self, "modId", "") end
function methods.getModId(self) return property(self, "modId", "") end
function methods.getSourceMod(self) return property(self, "modId", "") end
function methods.getModName(self) return property(self, "modName", "") end
function methods.Remove(self) end

local function runtimeProperties(spec, instance)
    local source = spec.props or {}
    if not instance then return source end

    -- Item scripts store Food hunger/thirst changes as hundredths, while the
    -- runtime Food object exposes native values after Item.createItem divides
    -- them by 100.  Keep script objects raw and mirror that conversion only
    -- on temporary/runtime instances used by PropertyReader.
    local itemType = string.lower(tostring(source.itemType or source.type or ""))
    local isFood = itemType:find("food", 1, true) ~= nil
        or source.foodType ~= nil
        or source.cantEat ~= nil
        or source.calories ~= nil
    if not isFood and source.stressChange == nil then return source end

    local result = {}
    for key, value in pairs(source) do result[key] = value end
    if isFood then
        if result.hungerChange ~= nil then
            result.hungerChange = (tonumber(result.hungerChange) or 0) / 100.0
        end
        if result.thirstChange ~= nil then
            result.thirstChange = (tonumber(result.thirstChange) or 0) / 100.0
        end
    end
    if result.stressChange ~= nil then
        result.stressChange = (tonumber(result.stressChange) or 0) / 100.0
    end
    return result
end

local function makeItem(spec, instance)
    local fullType = spec.fullType
    local moduleName, typeName = string.match(fullType, "^([^%.]+)%.(.+)$")
    local item = {
        _fullType = fullType, _module = moduleName or spec.module, _name = typeName or fullType,
        _props = runtimeProperties(spec, instance == true), _tags = spec.tags or {}, _instance = instance == true,
    }
    return setmetatable(item, { __index = methods })
end

for _, spec in ipairs(specs) do
    local item = makeItem(spec, false)
    spec._item = item
    byFullType[spec.fullType] = item
    items[#items + 1] = item
end

-- Offline mirror of the PZ sprite API used by MS_WorldObjectEvidence.  The
-- Python side parses newtiledefinitions.tiles.txt into spriteProperties;
-- Lua still performs the actual lookup and semantic analysis.
local spriteByName = {}
for _, spec in ipairs(specs) do
    local props = spec.props or {}
    local spriteName = tostring(props.worldObjectSprite or "")
    local spriteProperties = props.spriteProperties
    if spriteName ~= "" and type(spriteProperties) == "table" then
        spriteByName[spriteName] = spriteProperties
    end
end

local propertyContainerMethods = {}
function propertyContainerMethods.get(self, key)
    return self._props[key]
end
function propertyContainerMethods.has(self, key)
    return self._props[key] ~= nil
end
function propertyContainerMethods.isTable(self)
    return self._props.IsTable == true or tostring(self._props.IsTable or "") == "true"
end
function propertyContainerMethods.isTableTop(self)
    return self._props.IsTableTop == true or tostring(self._props.IsTableTop or "") == "true"
end
function propertyContainerMethods.getSurface(self)
    return tonumber(self._props.Surface) or 0
end
function propertyContainerMethods.getItemHeight(self)
    return tonumber(self._props.ItemHeight) or 0
end

local spriteMethods = {}
function spriteMethods.getProperties(self)
    return self._properties
end

getSprite = function(spriteName)
    local properties = spriteByName[tostring(spriteName or "")]
    if type(properties) ~= "table" then return nil end
    local container = setmetatable(
        { _props = properties },
        { __index = propertyContainerMethods }
    )
    return setmetatable(
        { _properties = container },
        { __index = spriteMethods }
    )
end

local scriptManager = {}
function scriptManager:FindItem(fullType) return byFullType[fullType] end
function scriptManager:getItem(fullType) return byFullType[fullType] end
ScriptManager = { instance = scriptManager }
getScriptManager = function() return scriptManager end
instanceItem = function(scriptItem)
    for _, spec in ipairs(specs) do
        if spec._item == scriptItem then return makeItem(spec, true) end
    end
end
instanceof = function(item, className)
    if not item or not item._instance then return false end
    if className == "InventoryItem" then return true end
    local itemType = string.lower(tostring(item:getItemType() or ""))
    local displayCategory = string.lower(tostring(item:getDisplayCategory() or ""))
    if className == "Food" then
        return itemType:find("food", 1, true) ~= nil or displayCategory == "food"
            or item:getFoodType() ~= "" or tonumber(item:getCalories()) > 0
    end
    if className == "Literature" then return itemType:find("literature", 1, true) ~= nil end
    return false
end

local function collection(values)
    local result = {}
    function result:size() return #values end
    function result:get(index) return values[index + 1] end
    return result
end
getAllItems = function() return collection(items) end
getActivatedMods = function()
    local active = {}
    for _, spec in ipairs(specs) do active[spec.workshopMod] = true end
    local ids = {}
    for id in pairs(active) do ids[#ids + 1] = id end
    table.sort(ids)
    return collection(ids)
end
getCore = function() return { getGameVersionString = function() return "offline-harness" end } end
getGameTime = function()
    return { getYear=function() return 1993 end, getMonth=function() return 6 end,
        getDay=function() return 15 end, getTimeOfDay=function() return 12 end,
        getMinutes=function() return 0 end }
end
SandboxVars = { MarketSense = sandboxOptions }

local api = require "MarketSense/MS_PublicAPI"
if MarketSense.YieldResolver and MarketSense.YieldResolver.setRecipeIndex then
    MarketSense.YieldResolver.setRecipeIndex(yieldRecipes)
end
if MarketSense.ToolRecipeDemand and MarketSense.ToolRecipeDemand.setRecipeIndex then
    MarketSense.ToolRecipeDemand.setRecipeIndex(toolRecipeUsage)
end

local function jsonEscape(value)
    local text = tostring(value or "")
    text = string.gsub(text, "\\", "\\\\")
    text = string.gsub(text, '"', '\\"')
    text = string.gsub(text, "\r", "\\r")
    text = string.gsub(text, "\n", "\\n")
    text = string.gsub(text, "\t", "\\t")
    return text
end
local function jsonString(value) return '"' .. jsonEscape(value) .. '"' end
local function jsonNumber(value)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge then
        return "null"
    end
    return tostring(number)
end
local function jsonField(value)
    -- Keep the flat row schema's historical empty-string values for nil and
    -- string fields, but preserve booleans as JSON booleans.  This matters for
    -- runtime evidence such as isActualLiquid and marketEligible: consumers
    -- should not have to guess whether "true" means true or text.
    if type(value) == "number" then return jsonNumber(value) end
    if type(value) == "boolean" then return value and "true" or "false" end
    return jsonString(value)
end
local function jsonValue(value, depth, seen)
    if value == nil then return "null" end
    local valueType = type(value)
    if valueType == "string" then return jsonString(value) end
    if valueType == "number" then return jsonNumber(value) end
    if valueType == "boolean" then return value and "true" or "false" end
    if valueType ~= "table" then return "null" end

    depth = depth or 0
    if depth > 6 then return "null" end
    seen = seen or {}
    if seen[value] then return "null" end
    seen[value] = true

    local isArray = true
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
            isArray = false
            break
        end
    end
    if isArray then
        local result = {}
        for index = 1, #value do
            result[#result + 1] = jsonValue(value[index], depth + 1, seen)
        end
        seen[value] = nil
        return "[" .. table.concat(result, ",") .. "]"
    end

    local keys = {}
    for key in pairs(value) do
        if type(key) == "string" or type(key) == "number" then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys, function(left, right) return tostring(left) < tostring(right) end)
    local result = {}
    for _, key in ipairs(keys) do
        result[#result + 1] = jsonString(key) .. ":" .. jsonValue(value[key], depth + 1, seen)
    end
    seen[value] = nil
    return "{" .. table.concat(result, ",") .. "}"
end

local function jsonArray(values) return jsonValue(values or {}) end

local function descriptorValue(tags, prefix)
    local marker = tostring(prefix or "") .. "."
    for _, tag in ipairs(tags or {}) do
        local text = tostring(tag or "")
        if string.sub(text, 1, #marker) == marker then
            return string.sub(text, #marker + 1)
        end
    end
    return ""
end

local function descriptorValues(tags, prefix)
    local values = {}
    local marker = tostring(prefix or "") .. "."
    for _, tag in ipairs(tags or {}) do
        local text = tostring(tag or "")
        if string.sub(text, 1, #marker) == marker then
            values[#values + 1] = string.sub(text, #marker + 1)
        end
    end
    return values
end

local function printRuntimeMetadata()
    local runtime = MarketSense.ItemRuntimeConfig or {}
    local pricing = runtime.pricing or {}
    local stock = runtime.stock or {}
    print("MSMETA\t" .. jsonValue({
        requested = sandboxOptions,
        applied = runtime.sandboxVars or {},
        runtime = {
            pricing = {
                minPrice = pricing.minPrice,
                maxPrice = pricing.maxPrice,
                baseMultiplier = pricing.baseMultiplier,
                baseMultiplierPercent = pricing.baseMultiplierPercent,
                globalValue = pricing.globalValue,
                contrastPercent = pricing.contrastPercent,
                variationPercent = pricing.variationPercent,
                categoryBands = pricing.categoryBands,
            },
            foodPricing = {
                openedPenalty = (runtime.foodPricing or {}).openedPenalty,
                sealedPreservationMultiplier = (runtime.foodPricing or {}).sealedPreservationMultiplier,
            },
            stock = {
                globalMultiplier = stock.globalMultiplier,
                maxCap = stock.maxCap,
                defaultMinRatio = stock.defaultMinRatio,
            },
        },
    }))
end

local function contextSnapshot(context)
    local snapshot = {}
    for key, value in pairs(context or {}) do
        -- The script item contains methods and its own property table. It is
        -- intentionally excluded; all scalar runtime inputs remain visible.
        if key ~= "item" and type(value) ~= "function" and type(value) ~= "userdata" then
            snapshot[key] = value
        end
    end
    return snapshot
end

local function safeCall(functionValue, ...)
    if type(functionValue) ~= "function" then return nil, "missing function" end
    local ok, result = pcall(functionValue, ...)
    if not ok then return nil, tostring(result) end
    return result, nil
end

local function detectionSnapshot(context)
    local classifier, classifierError = safeCall(
        MarketSense.Classifier and MarketSense.Classifier.classify, context
    )
    local final, finalError = safeCall(
        MarketSense.AutoTag and MarketSense.AutoTag.generate, context
    )
    local rootDecision = classifier and classifier.rootDecision or {}
    return {
        classifier = {
            signature = classifier and classifier.signature,
            category = classifier and classifier.category,
            primary = classifier and classifier.primary,
            confidence = classifier and classifier.confidence,
            details = classifier and classifier.details,
            error = classifierError,
        },
        final = {
            category = final and final.category,
            primary = final and final.primary,
            confidence = final and final.confidence,
            tags = final and final.tags,
            expandedTags = final and final.expandedTags,
            details = final and final.details,
            error = finalError,
        },
        root = rootDecision.root,
        resolverSource = rootDecision.source,
        method = "MarketSense.AutoTag.generate",
    }
end

local function hierarchySnapshot(primary, category)
    local hierarchy, hierarchyError = safeCall(
        MarketSense.TagMapper and MarketSense.TagMapper.getDefinition, primary
    )
    if type(hierarchy) ~= "table" then
        hierarchy = {
            root = category or "Misc",
            token = primary or "Misc",
            subcategory = "Unknown",
            leaf = primary or "Misc",
            primaryPrefix = (category or "Misc") .. ".Unknown." .. (primary or "Misc"),
            path = (category or "Misc") .. "/Unknown.txt",
            parents = {},
            error = hierarchyError or "TagMapper.getDefinition returned no table",
        }
    end
    return hierarchy
end

local function yieldResolverLabel(resolution)
    if type(resolution) ~= "table" then return "" end
    local status = tostring(resolution.status or "not_detected")
    if status == "not_detected" then return "none" end
    local method = tostring(resolution.candidateMethod or resolution.resolution or "unknown")
    local recipe = tostring(resolution.recipe or "")
    if recipe ~= "" then
        return status .. " · " .. method .. " · " .. recipe
    end
    return status .. " · " .. method
end

local function rowJson(row)
    local fields = {}
    local ordered = { "fullType", "category", "primary", "mechanicalClass", "mechanicalFamily", "marketRole",
        "price", "basePrice", "rawScore", "confidence", "source",
        "moduleName", "typeName", "displayName", "displayCategory", "itemType",
        "sourceModId", "sourceModName", "quality", "rarity", "theme", "origin",
        "weight", "hunger", "thirst", "calories", "daysFresh", "daysRotten",
        "minDamage", "maxDamage", "maxRange", "conditionMax", "capacity", "workshopMod", "workshopName",
        "workshopId", "workshopVersion", "scriptPath", "description", "subcategory", "leaf",
        "primaryPrefix", "categoryPath", "detector", "resolver", "marketEligible", "availabilityStatus",
        "fluidType", "fluidTypeString", "fluidAmount", "fluidCapacity", "fluidPrimaryAmount",
        "fluidFilledRatio", "isActualLiquid", "fluidIsMixture", "yieldResolver" }
    for _, key in ipairs(ordered) do
        local value = row[key]
        fields[#fields + 1] = jsonString(key) .. ":" .. jsonField(value)
    end
    fields[#fields + 1] = jsonString("tags") .. ":" .. jsonArray(row.tags)
    fields[#fields + 1] = jsonString("expandedTags") .. ":" .. jsonArray(row.expandedTags)
    fields[#fields + 1] = jsonString("themes") .. ":" .. jsonArray(row.themes)
    fields[#fields + 1] = jsonString("definitionSources") .. ":" .. jsonArray(row.definitionSources)
    fields[#fields + 1] = jsonString("metadata") .. ":" .. jsonValue(row.metadata)
    fields[#fields + 1] = jsonString("stock") .. ":" .. jsonValue(row.stock)
    fields[#fields + 1] = jsonString("baseStock") .. ":" .. jsonValue(row.baseStock)
    fields[#fields + 1] = jsonString("hierarchy") .. ":" .. jsonValue(row.hierarchy)
    fields[#fields + 1] = jsonString("detection") .. ":" .. jsonValue(row.detection)
    fields[#fields + 1] = jsonString("context") .. ":" .. jsonValue(row.context)
    fields[#fields + 1] = jsonString("priceAudit") .. ":" .. jsonValue(row.priceAudit)
    fields[#fields + 1] = jsonString("marketPricing") .. ":" .. jsonValue(row.marketPricing)
    fields[#fields + 1] = jsonString("priceHeuristic") .. ":" .. jsonValue(row.priceHeuristic)
    fields[#fields + 1] = jsonString("descriptorEvidence") .. ":" .. jsonValue(row.descriptorEvidence)
    fields[#fields + 1] = jsonString("descriptorRejected") .. ":" .. jsonValue(row.descriptorRejected)
    fields[#fields + 1] = jsonString("rarityEvidence") .. ":" .. jsonValue(row.rarityEvidence)
    fields[#fields + 1] = jsonString("yieldResolution") .. ":" .. jsonValue(row.yieldResolution)
    fields[#fields + 1] = jsonString("evaluator") .. ":" .. jsonValue(row.evaluator)
    fields[#fields + 1] = jsonString("availability") .. ":" .. jsonValue(row.availability)
    if row.error then fields[#fields + 1] = jsonString("error") .. ":" .. jsonString(row.error) end
    return "{" .. table.concat(fields, ",") .. "}"
end

printRuntimeMetadata()

for _, spec in ipairs(specs) do
    if spec.emit ~= false then
    local ok, details = pcall(api.GetPriceDetails, spec.fullType, true)
    local row = {
        fullType = spec.fullType, workshopMod = spec.workshopMod, workshopName = spec.workshopName,
        workshopId = spec.workshopId, workshopVersion = spec.workshopVersion,
        scriptPath = spec.scriptPath,
        definitionSources = spec.definitionSources,
    }
    if ok and type(details) == "table" then
        local context = MarketSense.PropertyReader.buildContext(spec.fullType)
        local detection = detectionSnapshot(context)
        local hierarchy = hierarchySnapshot(details.primary, details.category)
        local category = hierarchy.root or details.category or "Misc"
        local subcategory = hierarchy.subcategory or "Unknown"
        local leaf = hierarchy.leaf or details.primary or "Unknown"
        local config = MarketSense.ItemRuntimeConfig or {}
        local pricing = config.pricing or {}
        local stock = config.stock or {}
        local basePrice = math.max(
            tonumber(pricing.minPrice) or 1,
            MarketSense.Core.round(MarketSense.Core.priceClamp(details.rawScore))
        )
        local baseMax = MarketSense.Stock.baseMaxForWeight(context.weight)
        local baseStock = {
            min = math.floor(baseMax * (tonumber(stock.defaultMinRatio) or 0.2)),
            max = baseMax,
        }
        row.category, row.primary, row.price = details.category, details.primary, details.price
        row.displayName = context.displayName
        row.displayCategory = context.displayCategory
        row.itemType = context.itemType
        row.sourceModId, row.sourceModName = context.sourceModId, context.sourceModName
        local weaponDetails = (detection.final and detection.final.details) or {}
        local weaponEvidence = weaponDetails.weaponEvidence or {}
        row.mechanicalClass = weaponDetails.mechanicalClass or weaponEvidence.mechanicalClass
        row.mechanicalFamily = weaponDetails.mechanicalFamily or weaponEvidence.mechanicalFamily
        row.marketRole = weaponDetails.marketRole or weaponEvidence.marketRole
        row.basePrice = basePrice
        row.rawScore, row.confidence, row.source = details.rawScore, details.confidence, details.source
        row.moduleName, row.typeName = details.moduleName, details.typeName
        row.tags, row.expandedTags = details.tags, details.expandedTags
        row.quality = descriptorValue(row.expandedTags, "Quality")
        row.rarity = descriptorValue(row.expandedTags, "Rarity")
        row.theme = descriptorValue(row.expandedTags, "Theme")
        row.themes = descriptorValues(row.expandedTags, "Theme")
        row.origin = descriptorValue(row.expandedTags, "Origin")
        row.metadata = {
            quality = row.quality,
            rarity = row.rarity,
            theme = row.theme,
            themes = row.themes,
            origin = row.origin,
        }
        row.weight, row.hunger, row.thirst = context.weight, context.hunger, context.thirst
        row.calories, row.daysFresh, row.daysRotten = context.calories, context.daysFresh, context.daysRotten
        row.minDamage, row.maxDamage, row.maxRange = context.minDamage, context.maxDamage, context.maxRange
        row.conditionMax, row.capacity = context.conditionMax, context.capacity
        row.fluidType, row.fluidTypeString = context.fluidType, context.fluidTypeString
        row.fluidAmount, row.fluidCapacity = context.fluidAmount, context.fluidCapacity
        row.fluidPrimaryAmount, row.fluidFilledRatio = context.fluidPrimaryAmount, context.fluidFilledRatio
        row.isActualLiquid, row.fluidIsMixture = context.isActualLiquid, context.fluidIsMixture
        row.description = context.description
        row.availability = MarketSense.ItemsRegistry and MarketSense.ItemsRegistry.getAvailability
            and MarketSense.ItemsRegistry.getAvailability(spec.fullType) or nil
        row.marketEligible = row.availability and row.availability.obtainable == true or false
        row.availabilityStatus = row.availability and row.availability.status or "uncertain"
        row.stock = details.stock
        row.baseStock = baseStock
        row.hierarchy = hierarchy
        row.subcategory, row.leaf = subcategory, leaf
        row.primaryPrefix = hierarchy.primaryPrefix
        row.categoryPath = category .. " > " .. subcategory .. " > " .. leaf
        row.detector = detection.classifier.signature or detection.final.details and detection.final.details.source
        row.resolver = detection.resolverSource or detection.final.details and detection.final.details.source
        row.detection = detection
        row.context = contextSnapshot(context)
        row.priceAudit = details.balanceAudit
        row.marketPricing = details.marketPricing
        row.priceHeuristic = details.priceHeuristic
        row.descriptorEvidence = details.descriptorEvidence
        row.descriptorRejected = details.descriptorRejected
        row.rarityEvidence = details.rarityEvidence
        row.yieldResolution = details.yieldResolution
        row.yieldResolver = yieldResolverLabel(details.yieldResolution)
        row.evaluator = {
            api = "MarketSense.GetPriceDetails",
            withAudit = true,
            contextBuilder = "MarketSense.PropertyReader.buildContext",
            classifier = "MarketSense.Classifier.classify + MarketSense.AutoTag.generate",
            hierarchy = "MarketSense.TagMapper.getDefinition",
        }
    else
        row.error = tostring(details)
        row.tags, row.expandedTags = {}, {}
    end
    print("MSROW\t" .. rowJson(row))
    end
end
