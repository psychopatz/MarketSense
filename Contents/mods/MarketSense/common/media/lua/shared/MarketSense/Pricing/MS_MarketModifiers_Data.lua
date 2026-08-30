-- Typed market modifiers.  These values are deliberately separate from the
-- heuristic anchors: an anchor describes usefulness, while a modifier describes
-- a meaningful market distinction such as rarity, quality, or a registered
-- special item.
return {
    version = 1,
    tagModifiers = {
        ["Rarity.Common"] = { add = 11, reason = "Common rarity baseline" },
        ["Rarity.Uncommon"] = { add = 14, reason = "Uncommon rarity premium" },
        ["Rarity.Rare"] = { add = 17, reason = "Rare rarity premium" },
        ["Rarity.Legendary"] = { add = 20, reason = "Legendary rarity premium" },
        ["Rarity.UltraRare"] = { add = 27, reason = "Ultra-rare rarity premium" },
        ["Quality.Waste"] = { add = -10, reason = "Waste quality discount" },
        ["Quality.Luxury"] = { add = 40, reason = "Luxury quality premium" },
        ["Quality.Sterile"] = { add = 14, reason = "Sterile quality premium" },
        ["Theme.Combat"] = { add = 17, reason = "Combat theme premium" },
        ["Theme.Industrial"] = { add = 15, reason = "Industrial theme premium" },
        ["Theme.Militia"] = { add = 20, reason = "Militia theme premium" },
        ["Theme.Police"] = { add = 13, reason = "Police theme premium" },
        ["Theme.Primitive"] = { add = 7, reason = "Primitive theme premium" },
        ["Theme.Survival"] = { add = 20, reason = "Survival theme premium" },
        ["Theme.Winter"] = { add = 15, reason = "Winter theme premium" },
    },
    categoryModifiers = {},
    itemModifiers = {},
}
