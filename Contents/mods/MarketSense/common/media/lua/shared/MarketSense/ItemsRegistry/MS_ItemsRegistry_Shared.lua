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
Registry.PRICING_HEURISTIC_VERSION = 26
Registry.SIGNATURE_VERSION = "market-sense-v25-battery-root"
Registry.ROOT_FOLDER = "MS_Items"
-- PZ's getFileWriter only permits data extensions such as .txt/.json. The
-- index is a safe, line-parsed manifest persisted as .txt.
Registry.INDEX_PATH = Registry.ROOT_FOLDER .. "/MS_ItemsIndex.txt"
Registry.REQUEST_PATH = Registry.ROOT_FOLDER .. "/MS_RebuildRequest.json"
-- The grouped TXT files are the runtime catalog.  The prebuild audit was a
-- diagnostic sidecar and was never consumed by the mod or catalog viewer.
-- Keep it opt-in for troubleshooting instead of writing a second catalog on
-- every generation.
Registry.WRITE_PREBUILD_AUDIT = false
Registry.AUDIT_PATH = Registry.ROOT_FOLDER .. "/MS_PrebuildAudit.json"
Registry.OUTPUT_HINT = "Zomboid/Lua/MS_Items/"

Registry.state = Registry.state or {
    loaded = false,
    activeModsHash = nil,
    catalog = nil,
    lastIndex = nil,
    lastRequestKey = nil,
    deferredRebuild = false,
    rebuildPending = false,
    rebuildScheduled = false,
    rebuildInProgress = false,
    rebuildJob = nil,
    rebuildReason = nil,
    readyProbeCount = 0,
    lastReadyItemCount = nil,
    stale = false,
}

-- These limits deliberately keep registry work out of the boot critical path.
-- The rebuild is spread across ticks once PZ's live item data is stable.
Registry.REBUILD_ITEMS_PER_TICK = 24
Registry.REBUILD_READY_STABLE_TICKS = 2
Registry.REBUILD_BUDGET_MS = 3

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

local function appendConfigSignature(parts, prefix, value, seen)
    local valueType = type(value)
    if valueType == "function" or valueType == "userdata" or valueType == "thread" then
        return
    end
    if valueType ~= "table" then
        parts[#parts + 1] = prefix .. "=" .. tostring(value)
        return
    end
    if seen[value] then return end
    seen[value] = true

    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(left, right)
        return tostring(left) < tostring(right)
    end)
    for _, key in ipairs(keys) do
        local keyText = tostring(key)
        if keyText ~= "MasterList" and keyText ~= "ItemRegistryRevision"
            and keyText ~= "pricingRevision" then
            appendConfigSignature(parts, prefix .. "." .. keyText, value[key], seen)
        end
    end
end

function Shared.buildPricingConfigHash()
    local parts = {}
    appendConfigSignature(parts, "runtime", Shared.Config or {}, {})
    table.sort(parts)
    return Text.stableHash(parts)
end

return Shared
