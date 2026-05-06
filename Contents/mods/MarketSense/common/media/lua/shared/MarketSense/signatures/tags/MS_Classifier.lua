-- MS_Classifier.lua
-- Thin pipeline orchestrator. Requires all individual tag signature files and
-- runs them in order, returning the first matched result.
-- Add new signatures here to extend coverage.

require "MarketSense/signatures/tags/MS_TagMapper"
require "MarketSense/signatures/tags/MS_Sig_Smoking"
require "MarketSense/signatures/tags/MS_Sig_Medical"
require "MarketSense/signatures/tags/MS_Sig_Material"
require "MarketSense/signatures/tags/MS_Sig_Ammo"
require "MarketSense/signatures/tags/MS_Sig_Apparel"
require "MarketSense/signatures/tags/MS_Sig_Container"
require "MarketSense/signatures/tags/MS_Sig_Beverage"
require "MarketSense/signatures/tags/MS_Sig_Gardening"
require "MarketSense/signatures/tags/MS_Sig_Literature"
require "MarketSense/signatures/tags/MS_Sig_Tool"
require "MarketSense/signatures/tags/MS_Sig_Weapon"
require "MarketSense/signatures/tags/MS_Sig_Memento"
require "MarketSense/signatures/tags/MS_Sig_Food"

MarketSense = MarketSense or {}
MarketSense.Classifier = MarketSense.Classifier or {}

local Classifier = MarketSense.Classifier

-- Pipeline order mirrors CAEC ScriptCategorizers order.
-- Each entry must resolve to a key in MarketSense.Signatures.
local PIPELINE = {
    "Smoking",
    "Medical",
    "Material",
    "Ammo",
    "Apparel",
    "Container",
    "Beverage",
    "Gardening",
    "Literature",
    "Tool",
    "Weapon",
    "Memento",
    "Food",
}

function Classifier.classify(ctx)
    if not ctx then return nil end
    for _, name in ipairs(PIPELINE) do
        local sig = MarketSense.Signatures[name]
        if sig and type(sig.match) == "function" then
            local ok, result = pcall(sig.match, ctx)
            if ok and result and result.matched then
                result.signature = name
                return result
            end
        end
    end
    return nil
end

return Classifier
