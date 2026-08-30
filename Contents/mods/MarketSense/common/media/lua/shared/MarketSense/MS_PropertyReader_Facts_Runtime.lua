require "MarketSense/MS_Core"
require "MarketSense/MS_PropertyReader_Signals"

MarketSense = MarketSense or {}

local Core = MarketSense.Core
local Signals = require "MarketSense/MS_PropertyReader_Signals"
local positiveMagnitude = Signals.positiveMagnitude
local readNumber = Signals.readNumber
local preferNumber = Signals.preferNumber
local optionalNumber = Signals.optionalNumber
local preferString = Signals.preferString
local preferReplaceOnUseOn = Signals.preferReplaceOnUseOn
local isSentinelSpoilage = Signals.isSentinelSpoilage

local function read(scriptItem, instance, inventoryItem, definition)
    local foodType = definition.foodType
    local lootType = definition.lootType
    local eatType = definition.eatType
    local doubleClickRecipe = definition.doubleClickRecipe
    local openingRecipe = definition.openingRecipe
    local evolvedRecipe = definition.evolvedRecipe
    local evolvedRecipeName = definition.evolvedRecipeName
    local hasRuntimeState = inventoryItem ~= nil

    local isFoodInstance = false
    local isInventoryItemInstance = false
    local isLiteratureInstance = false
    local isDrainableInstance = false
    if instance and type(instanceof) == "function" then
        isFoodInstance        = instanceof(instance, "Food") == true
        isInventoryItemInstance = instanceof(instance, "InventoryItem") == true
        isLiteratureInstance  = instanceof(instance, "Literature") == true
        isDrainableInstance   = instanceof(instance, "DrainableComboItem") == true
    end

    local description = preferString(instance, scriptItem, { "getDescription", "getTooltip" }, "")

    local instanceFoodType = Core.safeString(instance, "getFoodType", "")
    if instanceFoodType ~= "" then foodType = instanceFoodType end
    local instanceLootType = Core.safeString(instance, "getLootType", "")
    if instanceLootType ~= "" then lootType = instanceLootType end
    local instanceEatType = Core.safeString(instance, "getEatType", "")
    if instanceEatType ~= "" then eatType = instanceEatType end

    -- Preserve native signed changes for valuation. The magnitude fields
    -- remain below for classifier compatibility.
    local hungerChange = preferNumber(instance, scriptItem, { "getHungChange", "getHungerChange" }, 0)
    local thirstChange = preferNumber(instance, scriptItem, { "getThirstChangeUnmodified", "getThirstChange" }, 0)
    local unhappyChange = preferNumber(instance, scriptItem, { "getUnhappyChangeUnmodified", "getUnhappyChange", "getUnhappy" }, 0)
    local boredomChange = preferNumber(instance, scriptItem, { "getBoredomChangeUnmodified", "getBoredomChange", "getBoredom" }, 0)
    local stressChange = preferNumber(instance, scriptItem, { "getStressChangeUnmodified", "getStressChange", "getStress" }, 0)
    local hunger = positiveMagnitude(hungerChange)
    local thirst = positiveMagnitude(thirstChange)
    local calories = math.max(0, preferNumber(instance, scriptItem, "getCalories", 0))
    local carbohydrates = math.max(0, preferNumber(instance, scriptItem, "getCarbohydrates", 0))
    local lipids = math.max(0, preferNumber(instance, scriptItem, "getLipids", 0))
    local proteins = math.max(0, preferNumber(instance, scriptItem, "getProteins", 0))
    local daysFresh = math.max(0, preferNumber(instance, scriptItem, "getDaysFresh", 0))
    local daysRotten = math.max(0, preferNumber(instance, scriptItem, "getDaysTotallyRotten", 0))
    local unhappy = positiveMagnitude(unhappyChange)
    local boredom = positiveMagnitude(boredomChange)
    local stress = positiveMagnitude(stressChange)
    local customEatSound = preferString(instance, scriptItem, "getCustomEatSound", "")
    -- Optional medical signals.  Keep unavailable values as nil so a missing
    -- medical API is not interpreted as a measured zero-effect treatment.
    local bandagePower = optionalNumber(instance, scriptItem, "getBandagePower")
    local reduceInfectionPower = optionalNumber(instance, scriptItem, "getReduceInfectionPower")
    local alcoholPower = optionalNumber(instance, scriptItem, "getAlcoholPower")
    local foodSicknessChange = optionalNumber(instance, scriptItem, "getFoodSicknessChange")
    local painReduction = optionalNumber(instance, scriptItem, "getPainReduction")
    local fluReduction = optionalNumber(instance, scriptItem, "getFluReduction")
    local isMedicalLoot = Core.safeBoolean(scriptItem, "isMedicalLoot", nil)
    local canBandage = Core.safeBoolean(instance, "isCanBandage", nil)
    if canBandage == nil then
        canBandage = Core.safeBoolean(scriptItem, "isCanBandage", nil)
    end
    local useSelf = Core.safeBoolean(instance, "isUseSelf", nil)
    if useSelf == nil then
        useSelf = Core.safeBoolean(scriptItem, "isUseSelf", nil)
    end
    local replaceOnUse = preferString(instance, scriptItem, "getReplaceOnUse", "")
    local replaceOnUseOn = preferReplaceOnUseOn(instance, scriptItem)
    local isDisappearOnUse = Core.safeBoolean(instance, "isDisappearOnUse", nil)
    if isDisappearOnUse == nil then
        isDisappearOnUse = Core.safeBoolean(scriptItem, "isDisappearOnUse", nil)
    end
    if bandagePower ~= nil then bandagePower = math.max(0, bandagePower) end
    if reduceInfectionPower ~= nil then reduceInfectionPower = math.max(0, reduceInfectionPower) end
    if alcoholPower ~= nil then alcoholPower = math.max(0, alcoholPower) end
    if painReduction ~= nil then painReduction = math.max(0, painReduction) end
    if fluReduction ~= nil then fluReduction = math.max(0, fluReduction) end
    local conditionMax = math.max(0, preferNumber(instance, scriptItem, "getConditionMax", 0))
    local currentCondition = conditionMax
    local hasRuntimeCondition = false
    if hasRuntimeState then
        local readCondition = readNumber(instance, "getCondition")
        if readCondition ~= nil then
            currentCondition = math.max(0, readCondition)
            hasRuntimeCondition = true
        end
    end
    local conditionRatio = nil
    if conditionMax > 0 then
        conditionRatio = math.max(0, math.min(1, currentCondition / conditionMax))
    end
    local conditionLowerChance = readNumber(instance, "getConditionLowerChance")
    if conditionLowerChance == nil then
        conditionLowerChance = readNumber(scriptItem, "getConditionLowerChance")
    end
    if conditionLowerChance ~= nil then
        conditionLowerChance = math.max(0, conditionLowerChance)
    end
    local useDelta = math.max(0, preferNumber(instance, scriptItem, "getUseDelta", 0))
    local maxUses = nil
    local currentUsesFloat = nil
    local weightEmpty = nil
    local stackCount = nil
    if hasRuntimeState then
        stackCount = readNumber(instance, "getCount")
        if stackCount ~= nil then stackCount = math.max(0, stackCount) end
    end
    if isDrainableInstance then
        maxUses = readNumber(instance, "getMaxUses")
        currentUsesFloat = readNumber(instance, "getCurrentUsesFloat")
        weightEmpty = readNumber(instance, "getWeightEmpty")
        if maxUses ~= nil then maxUses = math.max(0, maxUses) end
        if currentUsesFloat ~= nil then
            currentUsesFloat = math.max(0, math.min(1, currentUsesFloat))
        end
        if weightEmpty ~= nil then weightEmpty = math.max(0, weightEmpty) end
    end
    local hitChance = math.max(0, preferNumber(instance, scriptItem, "getHitChance", 0))
    local aimingTime = math.max(0, preferNumber(instance, scriptItem, "getAimingTime", 0))
    local isTwoHandWeapon = Core.safeBoolean(
        instance, "isTwoHandWeapon", Core.safeBoolean(scriptItem, "isTwoHandWeapon", false)
    )
    -- These are optional electronics signals.  Keep nil as "not exposed" so
    -- a missing radio/light API is not confused with a measured zero.
    local lightStrength = readNumber(instance, "getLightStrength")
    local lightDistance = readNumber(instance, "getLightDistance")
    local lightCanEmit = Core.safeCall(instance, "canEmitLight", nil)
    local lightUseBattery = Core.safeCall(instance, "isLightUseBattery", nil)
    local lightHasBattery = Core.safeCall(instance, "isLightHasBattery", nil)
    if lightStrength ~= nil then lightStrength = math.max(0, lightStrength) end
    if lightDistance ~= nil then lightDistance = math.max(0, lightDistance) end

    local device = Core.safeCall(instance, "getDeviceData", nil)
    local deviceData = nil
    if device ~= nil then
        deviceData = {
            isBatteryPowered = Core.safeCall(device, "getIsBatteryPowered", nil),
            hasBattery = Core.safeCall(device, "getHasBattery", nil),
            isTelevision = Core.safeCall(device, "getIsTelevision", nil),
            isTwoWay = Core.safeCall(device, "getIsTwoWay", nil),
            isPortable = Core.safeCall(device, "getIsPortable", nil),
            isHighTier = Core.safeCall(device, "getIsHighTier", nil),
            minChannelRange = readNumber(device, "getMinChannelRange"),
            maxChannelRange = readNumber(device, "getMaxChannelRange"),
            transmitRange = readNumber(device, "getTransmitRange"),
            power = readNumber(device, "getPower"),
            isTurnedOn = Core.safeCall(device, "getIsTurnedOn", nil),
        }
    end
    local foodAge = nil
    local hasRuntimeFoodAge = false
    local hasRuntimeFoodState = false
    local isRotten = false
    local isFrozen = false
    local isCooked = false
    local isBurnt = false
    local heat = 0
    if hasRuntimeState then
        foodAge = readNumber(inventoryItem, "getAge")
        hasRuntimeFoodAge = foodAge ~= nil
        hasRuntimeFoodState = true
        isRotten = Core.safeBoolean(inventoryItem, { "isRotten", "IsRotten" }, false)
        isFrozen = Core.safeBoolean(inventoryItem, "isFrozen", false)
        isCooked = Core.safeBoolean(inventoryItem, "isCooked", false)
        isBurnt = Core.safeBoolean(inventoryItem, "isBurnt", false)
        heat = readNumber(inventoryItem, "getHeat") or 0
    end
    local foodDaysFresh = isSentinelSpoilage(daysFresh) and 0 or daysFresh
    local foodDaysRotten = isSentinelSpoilage(daysRotten) and 0 or daysRotten
    local hasFoodNutritionEvidence = hunger > 0 or thirst > 0 or calories > 0
        or carbohydrates > 0 or lipids > 0 or proteins > 0
    local hasFoodSpoilageEvidence = foodDaysFresh > 0 or foodDaysRotten > 0
    local hasFoodRecipeEvidence = evolvedRecipe ~= "" or evolvedRecipeName ~= ""
        or doubleClickRecipe ~= "" or openingRecipe ~= "" or customEatSound ~= ""
    local isDung = Core.safeBoolean(instance or scriptItem, { "isDung", "getIsDung" }, false)

    return {
        hasRuntimeState = hasRuntimeState,
        isFoodInstance = isFoodInstance,
        isInventoryItemInstance = isInventoryItemInstance,
        isLiteratureInstance = isLiteratureInstance,
        isDrainableInstance = isDrainableInstance,
        description = description,
        foodType = foodType,
        lootType = lootType,
        eatType = eatType,
        hungerChange = hungerChange,
        thirstChange = thirstChange,
        unhappyChange = unhappyChange,
        boredomChange = boredomChange,
        stressChange = stressChange,
        hunger = hunger,
        thirst = thirst,
        calories = calories,
        carbohydrates = carbohydrates,
        lipids = lipids,
        proteins = proteins,
        daysFresh = daysFresh,
        daysRotten = daysRotten,
        unhappy = unhappy,
        boredom = boredom,
        stress = stress,
        customEatSound = customEatSound,
        bandagePower = bandagePower,
        reduceInfectionPower = reduceInfectionPower,
        alcoholPower = alcoholPower,
        foodSicknessChange = foodSicknessChange,
        painReduction = painReduction,
        fluReduction = fluReduction,
        isMedicalLoot = isMedicalLoot,
        canBandage = canBandage,
        useSelf = useSelf,
        replaceOnUse = replaceOnUse,
        replaceOnUseOn = replaceOnUseOn,
        isDisappearOnUse = isDisappearOnUse,
        conditionMax = conditionMax,
        currentCondition = currentCondition,
        hasRuntimeCondition = hasRuntimeCondition,
        conditionRatio = conditionRatio,
        conditionLowerChance = conditionLowerChance,
        useDelta = useDelta,
        maxUses = maxUses,
        currentUsesFloat = currentUsesFloat,
        weightEmpty = weightEmpty,
        stackCount = stackCount,
        hitChance = hitChance,
        aimingTime = aimingTime,
        isTwoHandWeapon = isTwoHandWeapon,
        lightStrength = lightStrength,
        lightDistance = lightDistance,
        lightCanEmit = lightCanEmit,
        lightUseBattery = lightUseBattery,
        lightHasBattery = lightHasBattery,
        deviceData = deviceData,
        foodAge = foodAge,
        hasRuntimeFoodAge = hasRuntimeFoodAge,
        hasRuntimeFoodState = hasRuntimeFoodState,
        isRotten = isRotten,
        isFrozen = isFrozen,
        isCooked = isCooked,
        isBurnt = isBurnt,
        heat = heat,
        foodDaysFresh = foodDaysFresh,
        foodDaysRotten = foodDaysRotten,
        hasFoodNutritionEvidence = hasFoodNutritionEvidence,
        hasFoodSpoilageEvidence = hasFoodSpoilageEvidence,
        hasFoodRecipeEvidence = hasFoodRecipeEvidence,
        isDung = isDung,
    }
end

return { read = read }
