require "MarketSense/DT_Core"

DynamicTrading = DynamicTrading or {}
DynamicTrading.Signatures = DynamicTrading.Signatures or {}

local Core = DynamicTrading.Core
local Signature = {}

local function success(confidence, category, primary, tags)
    return {
        matched = true,
        confidence = confidence,
        category = category,
        primary = primary,
        tags = tags,
    }
end

function Signature.match(ctx)
    local matched, token = Core.ctxContains(ctx, {
        "firstaid", "bandage", "bandaid", "disinfectant", "cotton", "splint",
        "pills", "antibiotics", "tablet", "vitamin", "cigarette", "cigar", "tobacco",
        "suture", "scalpel", "tweezers", "forceps", "medical",
    })

    if not matched then
        return { matched = false, confidence = 0 }
    end

    if token == "scalpel" or token == "suture" or token == "tweezers" or token == "forceps" then
        return success(0.99, "Tool", "Tool.Medical.Surgical", {
            "Tool.Medical.Surgical",
            "Medical.Consumable",
        })
    end

    if token == "pills" or token == "tablet" or token == "antibiotics" then
        return success(0.97, "Medical", "Medical.General.Pills", {
            "Medical.General.Pills",
            "Medical.Consumable",
        })
    end

    if token == "vitamin" then
        return success(0.96, "Medical", "Medical.General.Vitamin", {
            "Medical.General.Vitamin",
            "Medical.Consumable",
        })
    end

    if token == "cigarette" or token == "cigar" or token == "tobacco" then
        return success(0.95, "Medical", "Medical.General.Drug", {
            "Medical.General.Drug",
            "Medical.Consumable",
        })
    end

    if Core.ctxContains(ctx, { "aloe", "comfrey", "herb", "botanical" }) then
        return success(0.92, "Medical", "Medical.Healthcare.Botanical", {
            "Medical.Healthcare.Botanical",
            "Medical.Consumable",
        })
    end

    return success(0.94, "Medical", "Medical.Healthcare", {
        "Medical.Healthcare",
        "Medical.Consumable",
    })
end

DynamicTrading.Signatures.Medical = Signature
return Signature
