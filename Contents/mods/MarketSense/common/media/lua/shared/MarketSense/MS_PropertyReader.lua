require "MarketSense/MS_RuntimeCache"
require "MarketSense/MS_WorldObjectEvidence"
require "MarketSense/MS_ItemCapabilities"

MarketSense = MarketSense or {}
MarketSense.PropertyReader = MarketSense.PropertyReader or {}

local PropertyReader = MarketSense.PropertyReader
local ContextBuilder = require "MarketSense/MS_PropertyReader_Context"

-- Keep the public namespace stable while isolating context assembly from the
-- cache-facing compatibility entry point.
PropertyReader.buildContext = ContextBuilder.buildContext

return PropertyReader
