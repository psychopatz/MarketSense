local Utils = require "MarketSense/ClientDebug/MS_ClientDebugUtils"

local Renderers = {}

function Renderers.compareCatalogEntries(a, b)
    if a.category ~= b.category then
        return a.category < b.category
    end
    if a.moduleName ~= b.moduleName then
        return a.moduleName < b.moduleName
    end
    return a.fullType < b.fullType
end

function Renderers.compareSignatureEntries(a, b)
    local matchedA = a.matched == true and 1 or 0
    local matchedB = b.matched == true and 1 or 0
    if matchedA ~= matchedB then
        return matchedA > matchedB
    end

    local confidenceA = tonumber(a.confidence) or 0
    local confidenceB = tonumber(b.confidence) or 0
    if confidenceA ~= confidenceB then
        return confidenceA > confidenceB
    end

    return Utils.safeText(a.signature) < Utils.safeText(b.signature)
end

function Renderers.renderCatalogRow(listbox, y, item, alt)
    local entry = item and item.item or nil
    if not entry then
        return y + listbox.itemheight
    end

    local selected = listbox.selected == item.index
    if selected then
        listbox:drawRect(0, y, listbox.width, listbox.itemheight, 0.28, 0.20, 0.36, 0.24)
    elseif alt then
        listbox:drawRect(0, y, listbox.width, listbox.itemheight, 0.08, 1, 1, 1)
    end
    listbox:drawRectBorder(0, y, listbox.width, listbox.itemheight, 0.10, 1, 1, 1)

    listbox:drawText(entry.fullType, 8, y + 4, 0.93, 0.93, 0.93, 1, UIFont.Small)
    local sourceMod = Utils.safeText(entry.sourceModName, "")
    if sourceMod == "" then
        sourceMod = Utils.safeText(entry.moduleName, "?")
    end

    listbox:drawText(
        string.format("%s | %s", sourceMod, Utils.safeText(entry.category, "?")),
        8,
        y + 20,
        0.68,
        0.78,
        0.92,
        1,
        UIFont.Small
    )
    listbox:drawTextRight("P:" .. Utils.safeText(entry.price, "0"), listbox.width - 8, y + 4, 0.74, 0.92, 0.74, 1, UIFont.Small)
    listbox:drawTextRight(Utils.safeText(entry.primary, "Misc.General"), listbox.width - 8, y + 20, 0.80, 0.74, 0.94, 1, UIFont.Small)

    return y + listbox.itemheight
end

function Renderers.renderTagRow(listbox, y, item, alt)
    local entry = item and item.item or nil
    if not entry then
        return y + listbox.itemheight
    end

    local selected = listbox.selected == item.index
    if selected then
        listbox:drawRect(0, y, listbox.width, listbox.itemheight, 0.22, 0.22, 0.36, 0.26)
    elseif alt then
        listbox:drawRect(0, y, listbox.width, listbox.itemheight, 0.06, 1, 1, 1)
    end
    listbox:drawRectBorder(0, y, listbox.width, listbox.itemheight, 0.08, 1, 1, 1)

    local kind = entry.kind == "base" and "BASE" or "EXPANDED"
    local kindColor = entry.kind == "base"
        and { r = 0.72, g = 0.92, b = 0.72 }
        or { r = 0.78, g = 0.82, b = 0.96 }

    listbox:drawText(Utils.safeText(entry.tag), 8, y + 5, 0.92, 0.92, 0.92, 1, UIFont.Small)
    listbox:drawText(kind, 8, y + 21, kindColor.r, kindColor.g, kindColor.b, 1, UIFont.Small)

    return y + listbox.itemheight
end

function Renderers.renderSignatureRow(listbox, y, item, alt)
    local entry = item and item.item or nil
    if not entry then
        return y + listbox.itemheight
    end

    local selected = listbox.selected == item.index
    if selected then
        listbox:drawRect(0, y, listbox.width, listbox.itemheight, 0.24, 0.22, 0.36, 0.26)
    elseif alt then
        listbox:drawRect(0, y, listbox.width, listbox.itemheight, 0.06, 1, 1, 1)
    end
    listbox:drawRectBorder(0, y, listbox.width, listbox.itemheight, 0.08, 1, 1, 1)

    local matchText = entry.matched and "MATCH" or "NO MATCH"
    local color = entry.matched
        and { r = 0.70, g = 0.92, b = 0.70 }
        or { r = 0.84, g = 0.72, b = 0.72 }

    listbox:drawText(Utils.safeText(entry.signature, "?"), 8, y + 4, 0.92, 0.92, 0.92, 1, UIFont.Small)
    listbox:drawText(matchText, 8, y + 21, color.r, color.g, color.b, 1, UIFont.Small)
    listbox:drawTextRight(
        string.format("%.2f", tonumber(entry.confidence) or 0),
        listbox.width - 8,
        y + 4,
        0.72,
        0.86,
        0.98,
        1,
        UIFont.Small
    )
    listbox:drawTextRight(
        Utils.safeText(entry.primary, "Misc.General"),
        listbox.width - 8,
        y + 21,
        0.82,
        0.82,
        0.92,
        1,
        UIFont.Small
    )

    return y + listbox.itemheight
end

return Renderers
