require "MarketSense/MS_PropertyReader_Facts_Definition"
require "MarketSense/MS_PropertyReader_Facts_Runtime"
require "MarketSense/MS_PropertyReader_Facts_Fluid"

MarketSense = MarketSense or {}

local DefinitionReader = require "MarketSense/MS_PropertyReader_Facts_Definition"
local RuntimeReader = require "MarketSense/MS_PropertyReader_Facts_Runtime"
local FluidReader = require "MarketSense/MS_PropertyReader_Facts_Fluid"

local FactReader = {}

local function merge(target, values)
    for key, value in pairs(values or {}) do
        target[key] = value
    end
end

function FactReader.read(scriptItem, instance, inventoryItem, moduleName, typeName)
    local facts = {}
    merge(facts, DefinitionReader.read(scriptItem, moduleName, typeName))
    merge(facts, RuntimeReader.read(scriptItem, instance, inventoryItem, facts))
    merge(facts, FluidReader.read(instance or scriptItem))
    return facts
end

MarketSense.PropertyReaderFacts = FactReader

return FactReader

