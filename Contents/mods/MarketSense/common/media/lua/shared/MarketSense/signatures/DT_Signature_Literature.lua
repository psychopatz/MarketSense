require "MarketSense/DT_Core"

DynamicTrading = DynamicTrading or {}
DynamicTrading.Signatures = DynamicTrading.Signatures or {}

local Core = DynamicTrading.Core
local Signature = {}

local function success(confidence, primary, tags)
    return {
        matched = true,
        confidence = confidence,
        category = "Literature",
        primary = primary,
        tags = tags,
    }
end

function Signature.match(ctx)
    local isDoc = ctx.itemTypeLower == "literature"
    local hasSkillStr = Core.safeString(ctx.item, "getLvlSkillTrained", "")
    local hasSkill = hasSkillStr ~= "" or ctx.idLower:find("skillbook")
    
    local matched = isDoc
        or Core.ctxContains(ctx, {
            "skillbook", "magazine", "recipe", "map", "book", "journal", "diary", "notebook",
        })

    if not matched then
        return { matched = false, confidence = 0 }
    end

    local primary = "Literature.Book"
    local tags = { "Literature.Book" }
    
    if hasSkill then
        primary = "Literature.SkillBook"
        tags = { "Literature.SkillBook" }
        -- Determine level
        if Core.startsWith(hasSkillStr, "1") or ctx.idLower:find("vol1") or ctx.idLower:find("beginner") then
            tags[#tags + 1] = "Literature.SkillBook.Beginner"
        elseif Core.startsWith(hasSkillStr, "3") or ctx.idLower:find("vol2") or ctx.idLower:find("intermediate") then
            tags[#tags + 1] = "Literature.SkillBook.Intermediate"
        elseif Core.startsWith(hasSkillStr, "5") or ctx.idLower:find("vol3") or ctx.idLower:find("advanced") then
            tags[#tags + 1] = "Literature.SkillBook.Advanced"
        elseif Core.startsWith(hasSkillStr, "7") or ctx.idLower:find("vol4") or ctx.idLower:find("expert") then
            tags[#tags + 1] = "Literature.SkillBook.Expert"
        elseif Core.startsWith(hasSkillStr, "9") or ctx.idLower:find("vol5") or ctx.idLower:find("master") then
            tags[#tags + 1] = "Literature.SkillBook.Master"
        end
    elseif Core.ctxContains(ctx, { "magazine" }) then
        primary = "Literature.Magazine"
        tags = { "Literature.Magazine" }
    elseif Core.ctxContains(ctx, { "recipe" }) or Core.safeString(ctx.item, "getTeaches", "") ~= "" then
        primary = "Literature.Recipe"
        tags = { "Literature.Recipe" }
    elseif Core.ctxContains(ctx, { "map" }) then
        primary = "Literature.Map"
        tags = { "Literature.Map" }
    end

    return success(0.95, primary, tags)
end

DynamicTrading.Signatures.Literature = Signature
return Signature
