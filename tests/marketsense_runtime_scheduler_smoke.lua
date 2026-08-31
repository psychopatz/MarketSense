local T = require "tests/support/test"
T.addPackagePaths()

_G.unpack = _G.unpack or table.unpack
local written = {}
_G.getFileReader = function(path)
    local source = written[path]
    if not source then return nil end
    local lines = {}
    for line in string.gmatch(string.gsub(source, "\r\n", "\n"), "[^\n]*") do
        lines[#lines + 1] = line
    end
    local position = 0
    return {
        readLine = function()
            position = position + 1
            return lines[position]
        end,
        close = function() end,
    }
end
_G.getFileWriter = function(path)
    return {
        write = function(_, content) written[path] = content end,
        close = function() end,
    }
end
_G.getActivatedMods = function() return {} end

local handlers = {}
local removed = {}
_G.Events = {
    OnTick = {
        Add = function(handler) handlers[#handlers + 1] = handler end,
        Remove = function(handler) removed[handler] = true end,
    },
}

local items = {}
local collection = {}
function collection:size() return #items end
function collection:get(index) return items[index + 1] end
_G.getAllItems = function() return collection end
_G.getScriptManager = function()
    return {
        getAllCraftRecipes = function() return nil end,
        getAllRecipes = function() return nil end,
    }
end

local api = assert(T.load("MarketSense/MS_PublicAPI.lua"))
local registry = assert(MarketSense.ItemsRegistry)

local initial = assert(api.EnsureRuntimeRegistryLoaded(false))
T.equal(initial.total, 0, "cold boot does not synchronously rebuild the catalog")
T.equal(#handlers, 1, "cold boot schedules one rebuild handler")
T.falsy(registry.state.rebuildInProgress, "empty live tables do not start a rebuild")

handlers[1]()
T.falsy(registry.state.rebuildInProgress, "readiness probe waits for live items")

local item = {}
function item:getFullName() return "Base.SchedulerProbe" end
function item:getModuleName() return "Base" end
function item:getName() return "SchedulerProbe" end
function item:getDisplayCategory() return "Tool" end
function item:getDisplayName() return "Scheduler Probe" end
function item:getTooltip() return "" end
function item:getObsolete() return false end
function item:isHidden() return false end
function item:canSpawnAsLoot() return true end
function item:isCraftRecipeProduct() return false end
function item:canBeForaged() return false end
items[1] = item

handlers[1]()
T.falsy(registry.state.rebuildInProgress, "first stable probe does not start a rebuild")
handlers[1]()
T.truthy(registry.state.rebuildInProgress, "second stable probe starts the deferred rebuild")
T.equal(registry.state.rebuildJob.phase, "availability",
    "deferred rebuild begins with the availability phase")
T.equal(registry.state.rebuildJob.availabilityJob.index, 1,
    "availability work advances only one bounded batch")
T.equal(#removed, 0, "rebuild handler remains attached while work is pending")

for _ = 1, 24 do handlers[1]() end
T.falsy(registry.state.rebuildInProgress,
    "scheduled rebuild completes without blocking the caller")
T.falsy(registry.state.rebuildPending,
    "completed scheduled rebuild clears the pending state")
T.truthy(registry.state.catalog and registry.state.catalog.total >= 1,
    "completed scheduled rebuild publishes the generated catalog")

T.finish("marketsense_runtime_scheduler_smoke")
