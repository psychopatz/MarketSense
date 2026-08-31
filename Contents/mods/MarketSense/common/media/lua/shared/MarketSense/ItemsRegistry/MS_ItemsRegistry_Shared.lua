local Shared = {}

MarketSense = MarketSense or {}
require "MarketSense/MS_Config"
require "MarketSense/MS_Core"
require "MarketSense/MS_TagUtils"
require "MarketSense/MS_Pricing"
require "MarketSense/MS_Stock"
require "MarketSense/signatures/tags/MS_TagMapper"

MarketSense.ItemsRegistry = MarketSense.ItemsRegistry or {}
local Registry = MarketSense.ItemsRegistry

Registry.SCHEMA_VERSION = 4
Registry.FILE_SCHEMA = "MS_ITEMS_V1"
-- Force one migration from older caches that were valid but incomplete at
-- boot, causing live bundle items to appear only after manual generation.
Registry.GENERATOR_VERSION = 3
-- Bump when pricing inputs or runtime resolver semantics change so an old
-- materialized cache cannot hide the corrected bundle values.
Registry.PRICING_HEURISTIC_VERSION = 24
Registry.SIGNATURE_VERSION = "market-sense-v24-theme-material-loot-rarity"
Registry.ROOT_FOLDER = "MS_Items"
-- PZ's getFileWriter only permits data extensions such as .txt/.json. The
-- index is a safe, line-parsed manifest persisted as .txt.
Registry.INDEX_PATH = Registry.ROOT_FOLDER .. "/MS_ItemsIndex.txt"
Registry.REQUEST_PATH = Registry.ROOT_FOLDER .. "/MS_RebuildRequest.json"
Registry.AUDIT_PATH = Registry.ROOT_FOLDER .. "/MS_PrebuildAudit.json"
Registry.OUTPUT_HINT = "Zomboid/Lua/MS_Items/"

Registry.state = Registry.state or {
    loaded = false,
    activeModsHash = nil,
    catalog = nil,
    lastIndex = nil,
    lastRequestKey = nil,
    deferredRebuild = false,
}

local Text = require "MarketSense/ItemsRegistry/MS_ItemsRegistry_Text"
local State = require "MarketSense/ItemsRegistry/MS_ItemsRegistry_State"
local Domain = require "MarketSense/ItemsRegistry/MS_ItemsRegistry_Domain"

for key, value in pairs(Text) do Shared[key] = value end
for key, value in pairs(State) do Shared[key] = value end
for key, value in pairs(Domain) do Shared[key] = value end

Shared.Registry = Registry
Shared.Core = MarketSense.Core
Shared.TagUtils = MarketSense.TagUtils
Shared.Pricing = MarketSense.Pricing
Shared.Stock = MarketSense.Stock
Shared.Config = MarketSense.ItemRuntimeConfig

return Shared
