-- MarketSense localization facade backed by PsychopatzCore's modular
-- translation manager. The hub and catalog UI must not resolve MarketSense
-- owned keys directly through the native global getText() path.

require "PsychopatzCore/Translation/PsychopatzCustomTranslationManager"

MarketSense = MarketSense or {}

local Manager = CustomTranslationManager
local Scope = Manager and Manager.forMod
    and Manager.forMod("MarketSense") or nil
local Debug = Scope and Scope.registerSystem
    and Scope.registerSystem("Debug", "media/translation") or nil

local Translation = MarketSense.Translation or {}
MarketSense.Translation = Translation

function Translation.GetKey(key, fallback)
    if Debug and Debug.get then
        return Debug:get(key, fallback)
    end
    return fallback or key or ""
end

local CoreTranslation = PsychopatzCore and PsychopatzCore.Translation
if CoreTranslation and CoreTranslation.RegisterProvider then
    CoreTranslation.RegisterProvider("MarketSense", {
        getKey = function(key, fallback)
            return Translation.GetKey(key, fallback)
        end,
    })
end

return Translation
