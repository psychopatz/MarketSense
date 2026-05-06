require "MarketSense/MS_Config"
require "MarketSense/MS_Core"
require "MarketSense/MS_PropertyReader"
require "MarketSense/MS_AutoTag"
require "MarketSense/MS_Pricing"
require "MarketSense/MS_Stock"
require "MarketSense/MS_TagUtils"
require "MarketSense/signatures/tags/MS_TagMapper"

local Shared = require "MarketSense/ItemsRegistry/MS_ItemsRegistry_Shared"
require "MarketSense/ItemsRegistry/MS_ItemsRegistry_IO"
require "MarketSense/ItemsRegistry/MS_ItemsRegistry_Build"
local Runtime = require "MarketSense/ItemsRegistry/MS_ItemsRegistry_Runtime"

local Registry = Shared.Registry
MarketSense = MarketSense or {}
MarketSense.ItemsRegistry = Registry

Registry.loadCatalogFromCache = Runtime.loadCatalogFromCache
Registry.rebuildCache = Runtime.rebuildCache
Registry.ensureLoaded = Runtime.ensureLoaded
Registry.regenerate = Runtime.rebuildCache

return Registry
