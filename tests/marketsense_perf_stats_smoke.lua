local T = require "tests/support/test"
T.addPackagePaths()

local Cache = assert(T.load("MarketSense/MS_RuntimeCache.lua"))
local before = Cache.getStats()
Cache.recordInstanceRequest()
Cache.recordQueuedItem()
local after = Cache.getStats()

T.equal(after.instanceRequests, (before.instanceRequests or 0) + 1,
    "instance pricing requests are counted")
T.equal(after.queuedItems, (before.queuedItems or 0) + 1,
    "queued pricing items are counted")
T.equal(after.evaluations, (before.evaluations or 0) + 1,
    "instance requests contribute to evaluation count")

T.finish("marketsense_perf_stats_smoke")
