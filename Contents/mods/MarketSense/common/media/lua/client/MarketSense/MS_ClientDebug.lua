if isServer() then
    return
end

require "MarketSense/MS_ClientDebugWindow"

MarketSense = MarketSense or {}
MarketSense.ClientDebug = MarketSense.ClientDebug or {}

function MarketSense.ClientDebug.Open()
    return MS_ItemRuntimeDebugWindow.Open()
end

return MarketSense.ClientDebug
