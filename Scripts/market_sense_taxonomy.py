#!/usr/bin/env python3
"""
Canonical Market Sense taxonomy helpers.

This module is shared by the external prebuild pipeline and the asset generators
that keep the standalone MarketSense sandbox options aligned with the item
hierarchy used by Dynamic Trading.
"""

from __future__ import annotations

from collections import OrderedDict


GENERATOR_VERSION = 1
SCHEMA_VERSION = 3
FILE_SCHEMA = "DT_ITEMS_V2"
SIGNATURE_VERSION = "market-sense-prebuild-v1"
PRICING_HEURISTIC_VERSION = 2


CATEGORY_ORDER = OrderedDict(
    [
        ("Food", 1),
        ("Weapon", 2),
        ("Resource", 3),
        ("Tool", 4),
        ("Container", 5),
        ("Clothing", 6),
        ("Medical", 7),
        ("Electronics", 8),
        ("Literature", 9),
        ("Building", 10),
        ("Misc", 11),
    ]
)


DESCRIPTOR_ROOTS = {"Origin", "Quality", "Rarity", "Theme"}


DEFAULT_PRICE_ADDITIONS = OrderedDict(
    [
        ("Building", 14),
        ("Building.Fixture", 7),
        ("Building.Fixture.Appliance", 5),
        ("Building.Fixture.Plumbing", 6),
        ("Building.Furniture", 8),
        ("Building.Furniture.Bed", 17),
        ("Building.Furniture.Chair", 4),
        ("Building.Garden", 13),
        ("Building.Garden.Seed", 21),
        ("Building.Moveable", 18),
        ("Building.Survival", 18),
        ("Building.Survival.Trap", 6),
        ("Building.Vehicle", 12),
        ("Clothing", 199),
        ("Clothing.Accessory.Jewelry", 20),
        ("Clothing.Accessory.Jewelry.Ears", 5),
        ("Clothing.Accessory.Jewelry.Necklace", 13),
        ("Clothing.Accessory.Jewelry.Nose", 14),
        ("Clothing.Accessory.Jewelry.Ring", 7),
        ("Clothing.Accessory.Neck", 7),
        ("Clothing.Accessory.Utility", 5),
        ("Clothing.Accessory.Wrist", 0),
        ("Clothing.Accessory.Wrist.Watch", 7),
        ("Clothing.Armor", 252),
        ("Clothing.Armor.Arms", 8),
        ("Clothing.Armor.Face", 6),
        ("Clothing.Armor.Hands", 18),
        ("Clothing.Armor.Head", 13),
        ("Clothing.Armor.Heavy", 18),
        ("Clothing.Armor.Legs", 7),
        ("Clothing.Armor.Light", 15),
        ("Clothing.Armor.Medium", 14),
        ("Clothing.Armor.Neck", 21),
        ("Clothing.Armor.Torso", 12),
        ("Clothing.Authority", 19),
        ("Clothing.BiteResistant", 10),
        ("Clothing.Bottom", 11),
        ("Clothing.BulletResistant", 18),
        ("Clothing.Dress", 8),
        ("Clothing.Hands", 8),
        ("Clothing.Medical", 12),
        ("Clothing.Protective", 9),
        ("Clothing.Tactical", 16),
        ("Container", 214),
        ("Container.Bag", 343),
        ("Container.Bag.Backpack", 22),
        ("Container.Bag.Bandolier", 24),
        ("Container.Bag.Duffel", 24),
        ("Container.Bag.Fanny", 15),
        ("Container.Capacity", 182),
        ("Container.WeightReduction", 17),
        ("Electronics.Battery", 10),
        ("Electronics.Communicator", 24),
        ("Electronics.Generator", 100),
        ("Electronics.PowerGenerator", 150),
        ("Electronics.Radio.TwoWay", 45),
        ("Electronics.Television", 24),
        ("Electronics.Transmitter", 50),
        ("Food", 194),
        ("Food.MediumNutrition", 15),
        ("Food.NonPerishable", 30),
        ("Literature", 465),
        ("Literature.Book", -325),
        ("Literature.Cards", -236),
        ("Literature.Media", -258),
        ("Literature.Recipe", 348),
        ("Literature.SkillBook", 468),
        ("Medical", 40),
        ("Misc", 17),
        ("Quality.Luxury", 40),
        ("Rarity.Common", 11),
        ("Rarity.Rare", 17),
        ("Rarity.Uncommon", 14),
        ("Resource.Fuel", 50),
        ("Resource.Material", 16),
        ("Theme.Combat", 17),
        ("Theme.Industrial", 15),
        ("Theme.Militia", 20),
        ("Theme.Police", 13),
        ("Theme.Primitive", 7),
        ("Theme.Survival", 20),
        ("Theme.Winter", 15),
        ("Tool.Cookware", 9),
        ("Weapon", 13),
        ("Weapon.Explosive", 17),
    ]
)


DEFAULT_STOCK_MULTIPLIERS = {
    "Building": 0.9,
    "Clothing": 0.95,
    "Container": 0.9,
    "Electronics": 0.55,
    "Food": 0.9,
    "Food.Perishable": 0.55,
    "Food.NonPerishable": 1.15,
    "Food.Drink": 1.15,
    "Food.Cooking": 1.05,
    "Literature": 1.0,
    "Medical": 0.75,
    "Medical.Healthcare": 0.75,
    "Medical.Consumable": 0.95,
    "Medical.General.Pills": 0.95,
    "Misc": 1.0,
    "Resource": 1.1,
    "Resource.Fuel": 1.2,
    "Tool": 0.8,
    "Weapon": 0.6,
    "Weapon.Ranged.Ammo": 1.5,
    "Weapon.Ranged.Firearm": 0.55,
    "Weapon.Explosive": 0.3,
}


ROOT_PAGE_ORDER = [
    "Global",
    "Building",
    "Clothing",
    "Container",
    "Electronics",
    "Food",
    "Literature",
    "Medical",
    "Misc",
    "Quality",
    "Rarity",
    "Resource",
    "Theme",
    "Tool",
    "Weapon",
]


def sanitize_origin_tag(origin: str) -> str:
    text = (origin or "").strip()
    if text in ("", "Base", "Vanilla"):
        return "Vanilla"
    clean = "".join(ch for ch in text if ch.isalnum() or ch in "_-")
    return clean or "Modded"


def unique_tags(tags):
    seen = set()
    result = []
    for tag in tags or []:
        text = str(tag or "").strip()
        if text and text not in seen:
            seen.add(text)
            result.append(text)
    return result


def expand_hierarchy(tags):
    result = []
    seen = set()
    for tag in unique_tags(tags):
        probe = tag
        while probe:
            if probe not in seen:
                seen.add(probe)
                result.append(probe)
            if "." not in probe:
                break
            probe = probe.rsplit(".", 1)[0]
    return result


def primary_root(primary: str) -> str:
    text = str(primary or "").strip()
    if not text:
        return "Misc"
    return text.split(".", 1)[0]


def category_from_primary(primary: str) -> str:
    root = primary_root(primary)
    return root if root not in DESCRIPTOR_ROOTS else "Misc"


def _food_subcategory(sub1: str, sub2: str) -> str:
    if sub1 in ("Perishable", "NonPerishable", "Drink", "Cooking"):
        return sub1
    if sub1 in ("Fruit", "Vegetable", "Meat", "Fish", "Grain", "Sweets"):
        return "Perishable"
    if sub2 in ("Fruit", "Vegetable", "Meat", "Fish", "Grain", "Sweets"):
        return sub1 if sub1 in ("Perishable", "NonPerishable") else "Perishable"
    if sub1 == "Spice":
        return "Cooking"
    if sub1 in ("Alcohol", "NonAlcoholic"):
        return "Drink"
    return "NonPerishable"


def _weapon_subcategory(sub1: str, sub2: str) -> str:
    if sub1 == "Ranged" and sub2 == "Ammo":
        return "Ammo"
    if sub1 == "Ammo":
        return "Ammo"
    if sub1 in ("Melee", "Ranged", "Explosive", "Part"):
        return sub1
    return "Melee"


def _resource_subcategory(sub1: str, _sub2: str) -> str:
    if sub1 == "Fuel":
        return "Fuel"
    if sub1 in ("Parts", "Part"):
        return "Parts"
    if sub1 == "Fishing":
        return "Fishing"
    return "Material"


def _tool_subcategory(sub1: str, _sub2: str) -> str:
    if sub1 in ("Crafting", "Farming", "Fishing", "Cookware"):
        return sub1
    return "General"


def _container_subcategory(sub1: str, _sub2: str) -> str:
    if sub1 in ("Bag", "Liquid", "Stash", "Utility"):
        return sub1
    return "Utility"


def _clothing_subcategory(sub1: str, _sub2: str) -> str:
    if sub1 in ("Armor", "Accessory", "Top", "Bottom"):
        return sub1
    return "General"


def _medical_subcategory(sub1: str, sub2: str) -> str:
    if sub1 == "Drug" or sub2 == "Drug":
        return "Drug"
    if sub1 == "Consumable":
        return "Consumable"
    return "Healthcare"


def _electronics_subcategory(sub1: str, _sub2: str) -> str:
    if sub1 in ("Radio", "Light", "Battery", "Generator", "Gadget", "Television"):
        return "Radio" if sub1 == "Television" else sub1
    if sub1 == "PowerGenerator":
        return "Generator"
    if sub1 == "Communicator":
        return "Radio"
    return "Gadget"


def _literature_subcategory(sub1: str, _sub2: str) -> str:
    if sub1 in ("Book", "SkillBook", "Recipe", "Media", "Cards"):
        return sub1
    return "Book"


def _building_subcategory(sub1: str, _sub2: str) -> str:
    if sub1 in ("Furniture", "Fixture", "Garden", "Survival", "Vehicle", "Moveable"):
        return sub1
    return "Moveable"


def to_file_entry(primary: str):
    main = str(primary or "Misc.General").strip() or "Misc.General"
    parts = main.split(".")
    root = parts[0] if parts else "Misc"
    sub1 = parts[1] if len(parts) > 1 else "General"
    sub2 = parts[2] if len(parts) > 2 else ""

    if root == "Food":
        category = "Food"
        subcategory = _food_subcategory(sub1, sub2)
    elif root == "Weapon":
        category = "Weapon"
        subcategory = _weapon_subcategory(sub1, sub2)
    elif root == "Resource":
        category = "Resource"
        subcategory = _resource_subcategory(sub1, sub2)
    elif root == "Tool":
        category = "Tool"
        subcategory = _tool_subcategory(sub1, sub2)
    elif root == "Container":
        category = "Container"
        subcategory = _container_subcategory(sub1, sub2)
    elif root == "Clothing":
        category = "Clothing"
        subcategory = _clothing_subcategory(sub1, sub2)
    elif root == "Medical":
        category = "Medical"
        subcategory = _medical_subcategory(sub1, sub2)
    elif root == "Electronics":
        category = "Electronics"
        subcategory = _electronics_subcategory(sub1, sub2)
    elif root == "Literature":
        category = "Literature"
        subcategory = _literature_subcategory(sub1, sub2)
    elif root == "Building":
        category = "Building"
        subcategory = _building_subcategory(sub1, sub2)
    else:
        category = "Misc"
        subcategory = "General"

    return {
        "category": category,
        "subcategory": subcategory,
        "path": f"{category}/DT_{subcategory}.txt",
    }


def page_name_for_tag(tag: str) -> str:
    root = primary_root(tag)
    if root in DESCRIPTOR_ROOTS:
        return f"MarketSense{root}"
    return f"MarketSense{root or 'Misc'}"


def page_title_for_root(root: str) -> str:
    return f"Market Sense: {root}"


def option_key(prefix: str, tag: str, suffix: str) -> str:
    return f"MarketSense.{prefix}{tag.replace('.', '')}{suffix}"


def option_label(prefix: str, tag: str) -> str:
    parts = tag.split(".")
    return f"{prefix}: " + " > ".join(parts)


def option_tooltip(prefix: str, tag: str) -> str:
    if prefix == "Price":
        return f"Flat price addition for {tag} items."
    return f"Stock multiplier for {tag} items."


def iter_exposed_tags():
    seen = set()
    for tag in DEFAULT_PRICE_ADDITIONS.keys():
        if tag not in seen:
            seen.add(tag)
            yield tag


def build_taxonomy_export():
    return {
        "generatorVersion": GENERATOR_VERSION,
        "schemaVersion": SCHEMA_VERSION,
        "signatureVersion": SIGNATURE_VERSION,
        "pricingHeuristicVersion": PRICING_HEURISTIC_VERSION,
        "categoryOrder": dict(CATEGORY_ORDER),
        "descriptorRoots": sorted(DESCRIPTOR_ROOTS),
        "priceTags": list(DEFAULT_PRICE_ADDITIONS.keys()),
        "stockMultipliers": dict(DEFAULT_STOCK_MULTIPLIERS),
    }
