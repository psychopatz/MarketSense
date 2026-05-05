#!/usr/bin/env python3
"""
External Market Sense prebuild pipeline.

This script is an optional maintenance tool for regenerating DT_Items from
Project Zomboid item scripts. It scans vanilla plus active mod script files,
resolves a single primary root per item, derives subcategory and descriptor
tags, computes base price variations and stock ranges, and rewrites the runtime
cache files consumed by MarketSense and DynamicTrading.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from collections import Counter, OrderedDict, defaultdict
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple

from market_sense_taxonomy import (
    CATEGORY_ORDER,
    DEFAULT_PRICE_ADDITIONS,
    DEFAULT_STOCK_MULTIPLIERS,
    FILE_SCHEMA,
    GENERATOR_VERSION,
    PRICING_HEURISTIC_VERSION,
    SCHEMA_VERSION,
    SIGNATURE_VERSION,
    build_taxonomy_export,
    category_from_primary,
    expand_hierarchy,
    iter_exposed_tags,
    option_key,
    option_label,
    option_tooltip,
    page_name_for_tag,
    page_title_for_root,
    primary_root,
    sanitize_origin_tag,
    to_file_entry,
    unique_tags,
)


REPO_ROOT = Path(__file__).resolve().parents[1]
WORKSHOP_ROOT = REPO_ROOT.parent
HOME_ROOT = Path.home()
ZOMBOID_ROOT = HOME_ROOT / "Zomboid"
VANILLA_SCRIPTS_DIR = (
    HOME_ROOT
    / ".steam"
    / "steam"
    / "steamapps"
    / "common"
    / "ProjectZomboid"
    / "projectzomboid"
    / "media"
    / "scripts"
    / "generated"
    / "items"
)
if not VANILLA_SCRIPTS_DIR.exists():
    VANILLA_SCRIPTS_DIR = (
        HOME_ROOT
        / ".steam"
        / "steamapps"
        / "common"
        / "ProjectZomboid"
        / "projectzomboid"
        / "media"
        / "scripts"
        / "generated"
        / "items"
    )

DEFAULT_OUTPUT_ROOT = ZOMBOID_ROOT / "Lua" / "DT_Items"
DEFAULT_REQUEST_FILE = DEFAULT_OUTPUT_ROOT / "DT_RebuildRequest.json"
DEFAULT_AUDIT_FILE = DEFAULT_OUTPUT_ROOT / "DT_PrebuildAudit.json"
DEFAULT_SERVER_INI = ZOMBOID_ROOT / "Server" / "modv2-Colony.ini"
DEFAULT_STANDALONE_ROOT = REPO_ROOT / "Contents" / "mods" / "MarketSense" / "42.16" / "media"
DEFAULT_TAXONOMY_LUA = (
    REPO_ROOT
    / "Contents"
    / "mods"
    / "MarketSense"
    / "common"
    / "media"
    / "lua"
    / "shared"
    / "DT"
    / "MarketSense"
    / "Taxonomy"
    / "MS_TagTaxonomy_Data.lua"
)
DEFAULT_TAG_ADDITION_LUA = (
    REPO_ROOT
    / "Contents"
    / "mods"
    / "MarketSense"
    / "common"
    / "media"
    / "lua"
    / "shared"
    / "DT"
    / "Common"
    / "Pricing"
    / "DT_TagPriceAdditions_Data.lua"
)
DEFAULT_RUNTIME_RULES_LUA = (
    REPO_ROOT
    / "Contents"
    / "mods"
    / "MarketSense"
    / "common"
    / "media"
    / "lua"
    / "shared"
    / "DT"
    / "MarketSense"
    / "Items"
    / "MS_RuntimeRules_Data.lua"
)
DEFAULT_CACHE_DIR = REPO_ROOT / "Scripts" / "Output"


LIGHTER_EXCLUDES = {
    "candle",
    "candlelit",
    "lighter",
    "lighterbbq",
    "lighterdisposable",
    "lighterfluid",
}
CONTAINER_BODY_BAGS = {
    "back",
    "satchel",
    "fannypackfront",
    "fannypackback",
    "webbing",
    "ammostrap",
    "shoulderholster",
    "ankleholster",
}
CONTAINER_BAG_PATTERNS = (
    "bag_",
    "backpack",
    "rucksack",
    "duffel",
    "satchel",
    "handbag",
    "purse",
    "briefcase",
    "cooler",
    "sack",
    "fannypack",
    "ammo",
    "toolbox",
)
COOKWARE_PATTERNS = (
    "saucepan",
    "cookingpot",
    "pot",
    "kettle",
    "fryingpan",
    "roastingpan",
    "bakingpan",
    "bakingtray",
    "griddlepan",
    "gridlepan",
)
WEAPON_PATTERNS = (
    "axe",
    "hatchet",
    "knife",
    "blade",
    "machete",
    "sword",
    "katana",
    "bat",
    "club",
    "hammer",
    "crowbar",
    "wrench",
    "firecracker",
    "grenade",
    "bomb",
    "molotov",
    "pistol",
    "rifle",
    "shotgun",
    "revolver",
)
FOOD_PATTERNS = (
    "food",
    "meat",
    "fish",
    "fruit",
    "vegetable",
    "drink",
    "beverage",
    "alcohol",
    "beer",
    "wine",
    "juice",
    "coffee",
    "tea",
    "milk",
    "soda",
    "water",
    "candy",
    "chocolate",
    "cookie",
    "cake",
    "soup",
    "stew",
    "cereal",
    "bread",
    "rice",
    "pasta",
    "can",
)
MEDICAL_PATTERNS = (
    "bandage",
    "bandaid",
    "pills",
    "antibiotics",
    "disinfectant",
    "alcoholwipe",
    "vitamin",
    "splint",
    "comfrey",
    "plantain",
    "ginseng",
    "garlic",
    "tobacco",
    "cigarette",
    "cigar",
)
ELECTRONICS_PATTERNS = (
    "radio",
    "walkie",
    "generator",
    "battery",
    "television",
    "tv",
    "phone",
    "camera",
    "flashlight",
    "torch",
    "lightbulb",
    "alarm",
    "clock",
)
LITERATURE_PATTERNS = (
    "book",
    "magazine",
    "comic",
    "newspaper",
    "journal",
    "vhs",
    "cd",
    "cassette",
    "carddeck",
    "cards",
)
TOOL_PATTERNS = (
    "hammer",
    "saw",
    "drill",
    "wrench",
    "screwdriver",
    "shovel",
    "rake",
    "hoe",
    "trowel",
    "pickaxe",
    "flashlight",
    "rope",
    "crowbar",
    "tweezers",
    "forceps",
    "scalpel",
    "spatula",
    "ladle",
    "whisk",
)
RESOURCE_PATTERNS = (
    "scrap",
    "sheet",
    "ingot",
    "nails",
    "nail",
    "screws",
    "wire",
    "plank",
    "log",
    "glue",
    "adhesive",
    "fuel",
    "charcoal",
    "propane",
    "paper",
    "cloth",
    "leather",
    "fabric",
    "fertilizer",
    "seed",
)
BUILDING_PATTERNS = (
    "mov_",
    "sink",
    "shower",
    "toilet",
    "fridge",
    "freezer",
    "oven",
    "stove",
    "microwave",
    "washer",
    "dryer",
    "dishwasher",
    "locker",
    "vending",
    "mattress",
    "chair",
    "table",
    "cabinet",
    "dresser",
    "shelf",
    "tent",
    "sleepingbag",
    "bedroll",
    "trap",
)


ITEM_BLOCK_RE = re.compile(r"item\s+([A-Za-z_]\w*)\s*\{(.*?)\}", re.DOTALL)
KEY_VALUE_RE = re.compile(r"^\s*([A-Za-z_]\w*)\s*=\s*(.*?)\s*,?\s*$")
NUMBER_RE = re.compile(r"^-?\d+(?:\.\d+)?$")


@dataclass
class SourceFile:
    path: Path
    origin: str
    kind: str


@dataclass
class ParsedItem:
    full_type: str
    type_name: str
    origin: str
    source_path: str
    props: Dict[str, object]


def utc_timestamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def stable_hash(parts: Iterable[str]) -> str:
    value = 5381
    for part in parts:
        for char in str(part):
            value = ((value * 33) + ord(char)) % 4294967296
        value = ((value * 33) + 124) % 4294967296
    return f"{value:08x}"


def json_dump(path: Path, payload) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def sha1_text(text: str) -> str:
    return hashlib.sha1(text.encode("utf-8")).hexdigest()


def file_sha1(path: Path) -> str:
    return hashlib.sha1(path.read_bytes()).hexdigest()


def lower_text(value) -> str:
    return str(value or "").strip().lower()


def clean_text(value) -> str:
    text = str(value or "").strip()
    if len(text) >= 2 and text[0] == '"' and text[-1] == '"':
        return text[1:-1]
    return text


def parse_scalar(raw: str):
    text = clean_text(raw).strip()
    if not text:
        return ""
    lowered = text.lower()
    if lowered == "true":
        return True
    if lowered == "false":
        return False
    if NUMBER_RE.match(text):
        if "." in text:
            try:
                return float(text)
            except ValueError:
                return text
        try:
            return int(text)
        except ValueError:
            return text
    return text


def parse_tags(value: str) -> List[str]:
    text = clean_text(value)
    if not text:
        return []
    text = text.replace(",", ";")
    tags = []
    for part in text.split(";"):
        clean = clean_text(part).strip()
        if clean:
            tags.append(clean)
    return unique_tags(tags)


def parse_properties(block: str) -> Dict[str, object]:
    props: Dict[str, object] = {}
    for line in block.splitlines():
        line = line.strip()
        if not line or line.startswith("//"):
            continue
        match = KEY_VALUE_RE.match(line)
        if not match:
            continue
        key = match.group(1)
        raw_value = match.group(2)
        if key == "Tags":
            props[key] = parse_tags(raw_value)
        else:
            props[key] = parse_scalar(raw_value)
    return props


def parse_item_file_text(text: str, origin: str, source_path: str) -> List[ParsedItem]:
    items: List[ParsedItem] = []
    for match in ITEM_BLOCK_RE.finditer(text):
        type_name = match.group(1)
        block = match.group(2)
        props = parse_properties(block)
        module = clean_text(props.get("module", props.get("Module", ""))) or ("Base" if origin == "Vanilla" else origin)
        full_type = f"{module}.{type_name}"
        items.append(
            ParsedItem(
                full_type=full_type,
                type_name=type_name,
                origin=origin,
                source_path=source_path,
                props=props,
            )
        )
    return items


def load_json(path: Path, default):
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return default


def parse_with_cache(source_files: List[SourceFile], cache_path: Path):
    cache_payload = load_json(cache_path, {"version": 1, "files": {}})
    cache_files = cache_payload.get("files", {})
    updated_cache = {"version": 1, "files": {}}
    parsed: List[ParsedItem] = []
    manifest_parts: List[str] = []

    for source in source_files:
        digest = file_sha1(source.path)
        manifest_parts.append(f"{source.origin}|{source.path}|{digest}")
        cached = cache_files.get(str(source.path))
        if cached and cached.get("hash") == digest:
            for item in cached.get("items", []):
                parsed.append(
                    ParsedItem(
                        full_type=item["full_type"],
                        type_name=item["type_name"],
                        origin=item["origin"],
                        source_path=item["source_path"],
                        props=item["props"],
                    )
                )
            updated_cache["files"][str(source.path)] = cached
            continue

        text = source.path.read_text(encoding="utf-8", errors="ignore")
        items = parse_item_file_text(text, source.origin, str(source.path))
        parsed.extend(items)
        updated_cache["files"][str(source.path)] = {
            "hash": digest,
            "origin": source.origin,
            "items": [
                {
                    "full_type": item.full_type,
                    "type_name": item.type_name,
                    "origin": item.origin,
                    "source_path": item.source_path,
                    "props": item.props,
                }
                for item in items
            ],
        }

    json_dump(cache_path, updated_cache)
    return parsed, stable_hash(sorted(manifest_parts))


def contains_any(text: str, needles: Iterable[str]) -> bool:
    source = lower_text(text)
    return any(needle in source for needle in needles)


def has_any_tag(tags: Iterable[str], needles: Iterable[str]) -> bool:
    lowered = {lower_text(tag) for tag in tags or []}
    for needle in needles:
        if lower_text(needle) in lowered:
            return True
    return False


def get_number(props: Dict[str, object], *keys: str, default: float = 0.0) -> float:
    for key in keys:
        value = props.get(key)
        if isinstance(value, (int, float)):
            return float(value)
    return float(default)


def get_text(props: Dict[str, object], *keys: str) -> str:
    for key in keys:
        value = props.get(key)
        if value is None:
            continue
        text = clean_text(value).strip()
        if text:
            return text
    return ""


def get_bool(props: Dict[str, object], *keys: str) -> bool:
    for key in keys:
        value = props.get(key)
        if isinstance(value, bool):
            return value
        if isinstance(value, str):
            lowered = value.strip().lower()
            if lowered == "true":
                return True
            if lowered == "false":
                return False
    return False


def normalize_facts(item: ParsedItem) -> Dict[str, object]:
    props = item.props
    display_category = get_text(props, "DisplayCategory", "Categories", "Type")
    item_type = get_text(props, "ItemType", "Type")
    body_location = get_text(props, "BodyLocation")
    can_be_equipped = get_text(props, "CanBeEquipped")
    accept_item_function = get_text(props, "AcceptItemFunction")
    tags = unique_tags(props.get("Tags", []))

    facts = {
        "fullType": item.full_type,
        "origin": item.origin,
        "typeName": item.type_name,
        "props": props,
        "displayCategory": display_category,
        "displayCategoryLower": lower_text(display_category),
        "itemType": item_type,
        "itemTypeLower": lower_text(item_type),
        "bodyLocation": body_location,
        "bodyLocationLower": lower_text(body_location).replace("base:", ""),
        "canBeEquipped": can_be_equipped,
        "canBeEquippedLower": lower_text(can_be_equipped).replace("base:", ""),
        "acceptItemFunction": accept_item_function,
        "acceptItemFunctionLower": lower_text(accept_item_function),
        "idLower": lower_text(item.type_name),
        "fullLower": lower_text(item.full_type),
        "tags": tags,
        "tagsLower": {lower_text(tag) for tag in tags},
        "weight": max(0.0, get_number(props, "Weight", "ActualWeight")),
        "capacity": max(0.0, get_number(props, "Capacity")),
        "weightReduction": max(0.0, get_number(props, "WeightReduction")),
        "hunger": abs(get_number(props, "HungerChange")),
        "thirst": abs(get_number(props, "ThirstChange")),
        "calories": max(0.0, get_number(props, "Calories")),
        "daysFresh": max(0.0, get_number(props, "DaysFresh")),
        "daysRotten": max(0.0, get_number(props, "DaysTotallyRotten")),
        "unhappy": abs(get_number(props, "UnhappyChange", "Unhappy")),
        "boredom": abs(get_number(props, "BoredomChange", "Boredom")),
        "stress": abs(get_number(props, "StressChange", "Stress")),
        "minDamage": max(0.0, get_number(props, "MinDamage")),
        "maxDamage": max(0.0, get_number(props, "MaxDamage")),
        "maxRange": max(0.0, get_number(props, "MaxRange")),
        "maxHit": max(0.0, get_number(props, "MaxHitCount")),
        "conditionMax": max(0.0, get_number(props, "ConditionMax")),
        "useDelta": max(0.0, get_number(props, "UseDelta")),
        "biteDefense": max(0.0, get_number(props, "BiteDefense")),
        "scratchDefense": max(0.0, get_number(props, "ScratchDefense")),
        "bulletDefense": max(0.0, get_number(props, "BulletDefense")),
        "insulation": max(0.0, get_number(props, "Insulation")),
        "windResistance": max(0.0, get_number(props, "WindResistance")),
        "bandagePower": max(0.0, get_number(props, "BandagePower")),
        "reduceInfectionPower": max(0.0, get_number(props, "ReduceInfectionPower")),
        "ammoType": get_text(props, "AmmoType"),
        "ammoTypeLower": lower_text(get_text(props, "AmmoType")),
        "magazineType": get_text(props, "MagazineType"),
        "magazineTypeLower": lower_text(get_text(props, "MagazineType")),
        "partType": get_text(props, "PartType"),
        "partTypeLower": lower_text(get_text(props, "PartType")),
        "mountOn": get_text(props, "MountOn"),
        "mountOnLower": lower_text(get_text(props, "MountOn")),
        "micRange": max(0.0, get_number(props, "MicRange")),
        "transmitRange": max(0.0, get_number(props, "TransmitRange")),
        "isCookable": get_bool(props, "IsCookable", "Cookable"),
        "isDrainable": get_bool(props, "IsDrainable"),
        "canStoreWater": get_bool(props, "CanStoreWater"),
        "usesBattery": get_bool(props, "UsesBattery"),
        "twoWay": get_bool(props, "TwoWay"),
        "isPortable": get_bool(props, "IsPortable"),
        "isMoveable": item.type_name.startswith("Mov_"),
        "medical": get_bool(props, "Medical"),
        "flammable": get_bool(props, "CanBeActivated", "CanBePlaced"),
        "fuelValue": max(0.0, get_number(props, "FuelValue", "FireFuelRatio")),
        "metalValue": max(0.0, get_number(props, "MetalValue")),
        "learnedRecipes": get_text(props, "LearnedRecipes"),
        "skillTrained": get_text(props, "SkillTrained"),
    }
    return facts


def is_container_root(facts: Dict[str, object]) -> bool:
    item_lower = facts["idLower"]
    display = facts["displayCategoryLower"]
    item_type = facts["itemTypeLower"]
    body = facts["bodyLocationLower"]
    has_structure = (
        facts["capacity"] > 0
        or facts["weightReduction"] > 0
        or facts["canStoreWater"]
        or item_type in {"container", "base:container"}
        or display in {"container", "bag"}
        or bool(facts["acceptItemFunctionLower"])
    )
    wearable_bag = body in CONTAINER_BODY_BAGS or facts["canBeEquippedLower"] in CONTAINER_BODY_BAGS
    bag_name = contains_any(item_lower, CONTAINER_BAG_PATTERNS)
    cookware_liquid = facts["canStoreWater"] and display in {"cooking", "cookingweapon"} and contains_any(item_lower, COOKWARE_PATTERNS)
    return not cookware_liquid and (has_structure or wearable_bag or bag_name)


def is_clothing_root(facts: Dict[str, object]) -> bool:
    body = facts["bodyLocationLower"]
    display = facts["displayCategoryLower"]
    item_type = facts["itemTypeLower"]
    if body in {"wound", "bandage", "zeddmg"}:
        return False
    return bool(body) or display in {"clothing", "accessory", "protectivegear"} or item_type in {
        "clothing",
        "base:clothing",
        "base:alarmclockclothing",
    }


def is_electronics_root(facts: Dict[str, object]) -> bool:
    item_lower = facts["idLower"]
    display = facts["displayCategoryLower"]
    item_type = facts["itemTypeLower"]
    if item_lower in LIGHTER_EXCLUDES:
        return False
    return (
        item_type in {"base:radio", "radio"}
        or display in {"communications", "electronics", "lightsource"}
        or facts["usesBattery"]
        or facts["twoWay"]
        or facts["micRange"] > 0
        or facts["transmitRange"] > 0
        or facts["isPortable"]
        or contains_any(item_lower, ELECTRONICS_PATTERNS)
    )


def is_literature_root(facts: Dict[str, object]) -> bool:
    item_lower = facts["idLower"]
    display = facts["displayCategoryLower"]
    item_type = facts["itemTypeLower"]
    return (
        item_type in {"base:literature", "literature"}
        or display in {"literature", "book", "media", "writing"}
        or bool(facts["skillTrained"])
        or bool(facts["learnedRecipes"])
        or contains_any(item_lower, LITERATURE_PATTERNS)
    )


def is_weapon_root(facts: Dict[str, object]) -> bool:
    item_lower = facts["idLower"]
    display = facts["displayCategoryLower"]
    item_type = facts["itemTypeLower"]
    explicit_damage = any(key in facts["props"] for key in ("MinDamage", "MaxDamage", "MaxRange", "MaxHitCount"))
    explicit_weapon = (
        item_type in {"weapon", "base:weapon"}
        or display in {"weapon", "ammo", "weaponpart"}
        or bool(facts["ammoTypeLower"])
        or bool(facts["magazineTypeLower"])
        or bool(facts["partTypeLower"])
        or bool(facts["mountOnLower"])
    )
    return explicit_weapon or explicit_damage or contains_any(item_lower, WEAPON_PATTERNS)


def is_food_root(facts: Dict[str, object]) -> bool:
    item_lower = facts["idLower"]
    display = facts["displayCategoryLower"]
    item_type = facts["itemTypeLower"]
    return (
        facts["hunger"] > 0
        or facts["thirst"] > 0
        or facts["calories"] > 0
        or facts["daysFresh"] > 0
        or facts["daysRotten"] > 0
        or facts["isCookable"]
        or item_type in {"food", "base:food", "eat", "eatsmall"}
        or display == "food"
        or contains_any(item_lower, FOOD_PATTERNS)
    )


def is_medical_root(facts: Dict[str, object]) -> bool:
    item_lower = facts["idLower"]
    display = facts["displayCategoryLower"]
    if display == "firstaidweapon":
        return False
    return (
        facts["medical"]
        or facts["bandagePower"] > 0
        or facts["reduceInfectionPower"] > 0
        or display in {"firstaid", "bandage"}
        or contains_any(item_lower, MEDICAL_PATTERNS)
        or has_any_tag(facts["tags"], ["Base:Consumable", "Base:Comfrey", "Base:Plantain"])
    )


def is_tool_root(facts: Dict[str, object]) -> bool:
    item_lower = facts["idLower"]
    display = facts["displayCategoryLower"]
    item_type = facts["itemTypeLower"]
    if facts["capacity"] > 0 or facts["weightReduction"] > 0:
        return False
    return (
        display in {"tool", "toolweapon", "cooking", "cookingweapon", "firstaidweapon"}
        or item_type in {"drainable"}
        or contains_any(item_lower, TOOL_PATTERNS)
        or has_any_tag(facts["tags"], ["Base:CanOpener", "Base:BottleOpener", "Base:RemoveBullet", "Base:Tweezers"])
    )


def is_resource_root(facts: Dict[str, object]) -> bool:
    item_lower = facts["idLower"]
    display = facts["displayCategoryLower"]
    return (
        display in {"material", "reciperesource", "materialweapon"}
        or facts["fuelValue"] > 0
        or facts["metalValue"] > 0
        or has_any_tag(facts["tags"], ["Base:HasMetal", "Base:SteelMaterial", "Base:Glass", "Base:Ingot"])
        or contains_any(item_lower, RESOURCE_PATTERNS)
    )


def is_building_root(facts: Dict[str, object]) -> bool:
    item_lower = facts["idLower"]
    display = facts["displayCategoryLower"]
    return facts["isMoveable"] or display in {
        "furniture",
        "vehiclemaintenance",
        "gardening",
        "camping",
        "trapping",
        "household",
    } or contains_any(item_lower, BUILDING_PATTERNS)


def resolve_root(facts: Dict[str, object]) -> str:
    if is_container_root(facts):
        return "Container"
    if is_clothing_root(facts):
        return "Clothing"
    if is_electronics_root(facts):
        return "Electronics"
    if is_literature_root(facts):
        return "Literature"
    if is_weapon_root(facts):
        return "Weapon"
    if is_food_root(facts):
        return "Food"
    if is_medical_root(facts):
        return "Medical"
    if is_tool_root(facts):
        return "Tool"
    if is_resource_root(facts):
        return "Resource"
    if is_building_root(facts):
        return "Building"
    return "Misc"


def add_once(tags: List[str], tag: Optional[str]) -> None:
    if tag and tag not in tags:
        tags.append(tag)


def classify_container(facts: Dict[str, object]) -> Tuple[str, List[str]]:
    item_lower = facts["idLower"]
    body = facts["bodyLocationLower"]
    can_equip = facts["canBeEquippedLower"]
    tags: List[str] = []
    primary = "Container.Utility"

    if facts["canStoreWater"]:
        if body in {"back", "satchel"} or can_equip in {"back", "satchel"}:
            primary = "Container.Liquid.Wearable"
        elif "bucket" in item_lower or "pail" in item_lower:
            primary = "Container.Liquid.Bucket"
        elif "jar" in item_lower:
            primary = "Container.Liquid.Jar"
        elif "bottle" in item_lower or "canteen" in item_lower or "flask" in item_lower or "waterbag" in item_lower:
            primary = "Container.Liquid.Bottle"
        elif any(token in item_lower for token in ("mug", "cup", "glass", "goblet", "bowl")):
            primary = "Container.Liquid.Cup"
        else:
            primary = "Container.Liquid.General"
        add_once(tags, "Container.Liquid")
    elif "keyring" in item_lower or "acceptitemfunction.keyring" in facts["acceptItemFunctionLower"]:
        primary = "Container.Utility.KeyRing"
    elif "hollowbook" in item_lower:
        primary = "Container.Stash.Book"
    elif body == "fannypackfront" or body == "fannypackback":
        primary = "Container.Bag.Fanny"
    elif body == "webbing":
        primary = "Container.Bag.Rig"
    elif body == "ammostrap" or "ammocase" in facts["tagsLower"]:
        primary = "Container.Bag.Bandolier"
    elif body in {"shoulderholster", "ankleholster"}:
        primary = "Container.Bag.Holster"
    elif "duffel" in item_lower or "doctorbag" in item_lower or "toolbag" in item_lower:
        primary = "Container.Bag.Duffel"
    elif "satchel" in item_lower:
        primary = "Container.Bag.Satchel"
    elif "purse" in item_lower or "handbag" in item_lower:
        primary = "Container.Bag.Handbag"
    elif "cooler" in item_lower:
        primary = "Container.Bag.Cooler"
    elif "sack" in item_lower or "sandbag" in item_lower:
        primary = "Container.Bag.Sack"
    elif body == "back" or can_equip == "back" or "backpack" in item_lower or "rucksack" in item_lower:
        primary = "Container.Bag.Backpack"
    elif facts["displayCategoryLower"] == "bag" or contains_any(item_lower, CONTAINER_BAG_PATTERNS):
        primary = "Container.Bag.General"
    elif any(token in item_lower for token in ("case", "box", "tin", "cache", "parcel", "present", "album")):
        primary = "Container.Stash.Case"

    add_once(tags, primary)
    cap = facts["capacity"]
    if cap >= 20:
        add_once(tags, "Container.Capacity.High")
    elif cap >= 10:
        add_once(tags, "Container.Capacity.Medium")
    elif cap > 3:
        add_once(tags, "Container.Capacity.Low")
    else:
        add_once(tags, "Container.Capacity.Tiny")

    wr = facts["weightReduction"]
    if wr >= 80:
        add_once(tags, "Container.WeightReduction.High")
    elif wr >= 50:
        add_once(tags, "Container.WeightReduction.Medium")
    elif wr > 0:
        add_once(tags, "Container.WeightReduction.Low")

    if facts["bodyLocationLower"] or facts["canBeEquippedLower"]:
        add_once(tags, "Container.Wearable")
    if facts["medical"]:
        add_once(tags, "Medical.Healthcare")
        add_once(tags, "Medical.Consumable")
    return primary, tags


def classify_clothing(facts: Dict[str, object]) -> Tuple[str, List[str]]:
    body = facts["bodyLocationLower"]
    item_lower = facts["idLower"]
    tags: List[str] = []
    armor_score = facts["biteDefense"] + facts["scratchDefense"] + facts["bulletDefense"]
    is_armor = facts["displayCategoryLower"] == "protectivegear" or armor_score > 0 or contains_any(
        item_lower, ("armor", "armour", "bulletvest", "helmet", "greave", "gorget", "cuirass")
    )

    if is_armor:
        slot = "Torso"
        if body in {"hat", "fullhat", "jackethat", "sweaterhat"}:
            slot = "Head"
        elif body in {"mask", "maskeyes", "maskfull", "scba", "scbanotank"}:
            slot = "Face"
        elif "arm" in body or "shoulder" in body:
            slot = "Arms"
        elif "calf" in body or "thigh" in body or "knee" in body:
            slot = "Legs"
        elif body == "gorget":
            slot = "Neck"
        elif body in {"hands", "handsleft", "handsright"}:
            slot = "Hands"
        primary = f"Clothing.Armor.{slot}"
        add_once(tags, "Clothing.Armor")
        if armor_score >= 90:
            add_once(tags, "Clothing.Armor.Heavy")
        elif armor_score >= 60:
            add_once(tags, "Clothing.Armor.Medium")
        else:
            add_once(tags, "Clothing.Armor.Light")
    else:
        primary = "Clothing.General"
        if body in {"ears", "eartop"}:
            primary = "Clothing.Accessory.Jewelry.Ears"
        elif body in {"necklace", "necklace_long"}:
            primary = "Clothing.Accessory.Jewelry.Necklace"
        elif body in {"left_middlefinger", "right_middlefinger", "left_ringfinger", "right_ringfinger"}:
            primary = "Clothing.Accessory.Jewelry.Ring"
        elif body in {"leftwrist", "rightwrist"} and "watch" in item_lower:
            primary = "Clothing.Accessory.Wrist.Watch"
            add_once(tags, "Clothing.Accessory.Wrist")
        elif body in {"leftwrist", "rightwrist"}:
            primary = "Clothing.Accessory.Wrist"
        elif body in {"scarf", "neck"}:
            primary = "Clothing.Accessory.Neck"
        elif body in {"belt", "beltextra", "webbing", "ammostrap", "shoulderholster", "ankleholster"}:
            primary = "Clothing.Accessory.Utility"
        elif body in {"tshirt", "shirt", "shortsleeveshirt", "tanktop", "sweater", "jersey", "fulltop"} or contains_any(
            item_lower, ("shirt", "tshirt", "sweater", "jumper", "blouse", "jersey")
        ):
            primary = "Clothing.Top"
        elif body in {"pants", "pants_skinny", "shortpants", "shortsshort", "skirt", "longskirt", "legs1", "pantsextra"} or contains_any(
            item_lower, ("pants", "trousers", "shorts", "skirt")
        ):
            primary = "Clothing.Bottom"
        elif body in {"dress", "longdress"} or contains_any(item_lower, ("dress", "gown")):
            primary = "Clothing.Dress"
        elif body in {"hands", "handsleft", "handsright"} or contains_any(item_lower, ("glove", "mitt")):
            primary = "Clothing.Hands"
        elif contains_any(item_lower, ("police", "sheriff", "military", "army", "swat")):
            primary = "Clothing.Authority"

    add_once(tags, primary)
    if armor_score >= 25 and not is_armor:
        add_once(tags, "Clothing.Protective")
    if facts["medical"]:
        add_once(tags, "Clothing.Medical")
    if facts["biteDefense"] > 0:
        add_once(tags, "Clothing.BiteResistant")
    if facts["bulletDefense"] > 0:
        add_once(tags, "Clothing.BulletResistant")
    if contains_any(item_lower, ("tactical", "swat", "military")):
        add_once(tags, "Clothing.Tactical")
    return primary, tags


def classify_electronics(facts: Dict[str, object]) -> Tuple[str, List[str]]:
    item_lower = facts["idLower"]
    display = facts["displayCategoryLower"]
    tags: List[str] = []
    primary = "Electronics.Gadget.General"

    is_radio = (
        facts["itemTypeLower"] in {"base:radio", "radio"}
        or display == "communications"
        or any(token in item_lower for token in ("radio", "walkie", "hamradio"))
    )
    if "television" in item_lower or item_lower.startswith("tv") or "tv" == item_lower:
        primary = "Electronics.Television"
    elif is_radio:
        if facts["twoWay"] or facts["micRange"] > 0 or facts["transmitRange"] > 0 or "walkie" in item_lower or "ham" in item_lower:
            if "walkie" in item_lower:
                primary = "Electronics.Radio.TwoWay.Walkie"
            elif "ham" in item_lower or not facts["isPortable"]:
                primary = "Electronics.Radio.TwoWay.Ham"
            else:
                primary = "Electronics.Radio.TwoWay.Portable"
            add_once(tags, "Electronics.Radio.TwoWay")
        else:
            primary = "Electronics.Radio.Broadcast"
            add_once(tags, "Electronics.Radio.Broadcast")
        add_once(tags, "Electronics.Communicator")
        if facts["micRange"] > 0 or facts["transmitRange"] > 0:
            add_once(tags, "Electronics.Transmitter")
    elif display == "lightsource" or contains_any(item_lower, ("flashlight", "torch", "penlight", "lantern")):
        if "lantern" in item_lower:
            primary = "Electronics.Light.Lantern"
        else:
            primary = "Electronics.Light.Flashlight"
        add_once(tags, "Electronics.LightSource")
    elif "lightbulb" in item_lower or display == "electronics" and "bulb" in item_lower:
        primary = "Electronics.Light.Component"
    elif "battery" in item_lower or "cell" in item_lower:
        primary = "Electronics.Battery"
        add_once(tags, "Electronics.PowerSource")
    elif "generator" in item_lower or "solar" in item_lower:
        primary = "Electronics.Generator"
        add_once(tags, "Electronics.PowerGenerator")
    elif contains_any(item_lower, ("phone", "camera", "computer")):
        primary = "Electronics.Gadget.Communication"
        add_once(tags, "Electronics.Communicator")

    add_once(tags, primary)
    if facts["isPortable"] or contains_any(item_lower, ("walkie", "phone", "camera", "flashlight", "radio", "torch")):
        add_once(tags, "Electronics.Portable")
    return primary, tags


def classify_literature(facts: Dict[str, object]) -> Tuple[str, List[str]]:
    item_lower = facts["idLower"]
    display = facts["displayCategoryLower"]
    primary = "Literature.Book"
    if facts["skillTrained"] or contains_any(item_lower, ("skillbook", "beginners", "intermediate", "advanced", "expert", "master")):
        primary = "Literature.SkillBook"
    elif facts["learnedRecipes"] or "recipe" in display or "recipe" in item_lower:
        primary = "Literature.Recipe"
    elif contains_any(item_lower, ("vhs", "cd", "cassette", "tape")) or display == "media":
        primary = "Literature.Media"
    elif contains_any(item_lower, ("carddeck", "cards", "tarot")):
        primary = "Literature.Cards"
    return primary, [primary]


def classify_weapon(facts: Dict[str, object]) -> Tuple[str, List[str]]:
    item_lower = facts["idLower"]
    display = facts["displayCategoryLower"]
    primary = "Weapon.Melee.Blunt"
    if display == "weaponpart" or facts["partTypeLower"] or facts["mountOnLower"]:
        if facts["magazineTypeLower"] or "magazine" in item_lower or "clip" in item_lower or "drum" in item_lower:
            primary = "Weapon.Part.Ammo"
        else:
            primary = "Weapon.Part.Accessory"
    elif display == "ammo" or facts["ammoTypeLower"]:
        if facts["magazineTypeLower"] or "magazine" in item_lower or "clip" in item_lower or "drum" in item_lower:
            primary = "Weapon.Part.Ammo"
        else:
            primary = "Weapon.Ranged.Ammo"
    elif contains_any(item_lower, ("grenade", "bomb", "explosive", "molotov", "smokebomb", "firecracker", "pipebomb")):
        primary = "Weapon.Explosive"
    elif facts["ammoTypeLower"] or facts["itemTypeLower"] == "base:weapon" and contains_any(item_lower, ("pistol", "rifle", "shotgun", "revolver")):
        primary = "Weapon.Ranged.Firearm"
    elif contains_any(item_lower, ("axe", "hatchet", "pickaxe")):
        primary = "Weapon.Melee.Axe"
    elif contains_any(item_lower, ("blade", "knife", "machete", "sword", "katana", "scalpel", "cleaver")):
        primary = "Weapon.Melee.Blade"
    return primary, [primary]


def classify_food(facts: Dict[str, object]) -> Tuple[str, List[str]]:
    item_lower = facts["idLower"]
    tags: List[str] = []
    is_drink = facts["thirst"] > 0 and facts["hunger"] == 0 or contains_any(
        item_lower, ("drink", "beverage", "juice", "coffee", "tea", "soda", "cola", "milk", "water", "beer", "wine", "vodka", "whiskey")
    )
    perishable = facts["daysFresh"] > 0 and (facts["daysFresh"] < 30 or facts["daysRotten"] > 0)
    primary = "Food.NonPerishable.General"
    if is_drink:
        if contains_any(item_lower, ("beer", "wine", "vodka", "whiskey", "rum", "tequila", "gin", "brandy", "cider")):
            primary = "Food.Drink.Alcohol"
        else:
            primary = "Food.Drink.NonAlcoholic"
    elif any(token in item_lower for token in ("spice", "salt", "pepper", "basil", "thyme", "oregano", "rosemary", "sage", "bouillon")):
        primary = "Food.Cooking.Spice"
    elif "canned" in item_lower or "rationcan" in item_lower or item_lower.endswith("can") or "_can" in item_lower:
        primary = "Food.NonPerishable.Canned"
    elif contains_any(item_lower, ("meat", "fish", "chicken", "pork", "beef", "bacon", "sausage")):
        subtype = "Fish" if "fish" in item_lower else "Meat"
        family = "Perishable" if perishable else "NonPerishable"
        primary = f"Food.{family}.{subtype}"
    elif contains_any(item_lower, ("apple", "banana", "orange", "berry", "avocado", "peach", "pear", "lemon", "lime", "fruit")):
        primary = f"Food.{'Perishable' if perishable else 'NonPerishable'}.Fruit"
    elif contains_any(item_lower, ("carrot", "potato", "lettuce", "tomato", "broccoli", "cabbage", "pepper", "leek", "onion", "vegetable")):
        primary = f"Food.{'Perishable' if perishable else 'NonPerishable'}.Vegetable"
    elif contains_any(item_lower, ("candy", "chocolate", "cookie", "cake", "dessert", "sweet", "donut", "muffin", "gummy")):
        primary = f"Food.{'Perishable' if perishable else 'NonPerishable'}.Sweets"
    elif contains_any(item_lower, ("bread", "grain", "cereal", "rice", "pasta", "noodle", "oat", "flour", "bun", "barley", "corn", "bagel", "baguette")):
        primary = f"Food.{'Perishable' if perishable else 'NonPerishable'}.Grain"
    elif facts["isCookable"] or contains_any(item_lower, ("dough", "batter", "mix", "soup", "stew", "chili", "sauce")):
        primary = "Food.Cooking.Ingredient"
    elif perishable:
        primary = "Food.Perishable.General"

    add_once(tags, primary)
    nutrition = (facts["hunger"] * 100.0) + (facts["calories"] * 0.01)
    if nutrition >= 25:
        add_once(tags, "Food.HighNutrition")
    elif nutrition >= 10:
        add_once(tags, "Food.MediumNutrition")
    else:
        add_once(tags, "Food.LowNutrition")
    if facts["unhappy"] + facts["boredom"] >= 20:
        add_once(tags, "Food.LowQuality")
    if contains_any(item_lower, ("weed", "cannabis", "marijuana", "hash", "gummy", "brownie", "cookie")) and (
        facts["hunger"] > 0 or facts["calories"] > 0 or facts["isCookable"]
    ):
        add_once(tags, "Medical.General.Drug")
        add_once(tags, "Medical.Consumable")
    return primary, tags


def classify_medical(facts: Dict[str, object]) -> Tuple[str, List[str]]:
    item_lower = facts["idLower"]
    primary = "Medical.Healthcare"
    if contains_any(item_lower, ("cigarette", "cigar", "tobacco", "weed", "cannabis", "marijuana", "hash", "opium", "heroin", "meth")):
        primary = "Medical.General.Drug"
    elif "vitamin" in item_lower:
        primary = "Medical.General.Vitamin"
    elif contains_any(item_lower, ("pills", "antibiotics", "tablet", "capsule")):
        primary = "Medical.General.Pills"
    elif contains_any(item_lower, ("comfrey", "plantain", "garlic", "mallow", "ginseng", "cataplasm")):
        primary = "Medical.Healthcare.Botanical"
    tags = [primary]
    add_once(tags, "Medical.Consumable")
    return primary, tags


def classify_tool(facts: Dict[str, object]) -> Tuple[str, List[str]]:
    item_lower = facts["idLower"]
    display = facts["displayCategoryLower"]
    primary = "Tool.General"
    if display in {"cooking", "cookingweapon"} or contains_any(item_lower, COOKWARE_PATTERNS + ("canopener", "spatula", "ladle", "whisk", "grater", "bottleopener")):
        primary = "Tool.Cookware"
    elif display == "firstaidweapon" or contains_any(item_lower, ("tweezers", "forceps", "scalpel", "suture")):
        primary = "Tool.Medical.Surgical" if contains_any(item_lower, ("scalpel", "forceps", "suture")) else "Tool.Medical"
    elif contains_any(item_lower, ("hammer", "saw", "drill", "wrench", "screwdriver", "welder")):
        primary = "Tool.Crafting"
    elif contains_any(item_lower, ("shovel", "rake", "hoe", "trowel", "pitchfork", "pickaxe", "sickle", "scythe")):
        primary = "Tool.Farming"
    elif contains_any(item_lower, ("fishingrod", "fishingline", "hook", "lure", "net")):
        primary = "Tool.Fishing"
    elif contains_any(item_lower, ("crowbar", "lock", "key", "rope", "flashlight", "torch")):
        primary = "Tool.Utility"
    tags = [primary]
    if facts["conditionMax"] > 50:
        add_once(tags, "Tool.Durable")
    elif 0 < facts["conditionMax"] < 15:
        add_once(tags, "Tool.Fragile")
    return primary, tags


def classify_resource(facts: Dict[str, object]) -> Tuple[str, List[str]]:
    item_lower = facts["idLower"]
    display = facts["displayCategoryLower"]
    primary = "Resource.Material.General"
    if facts["fuelValue"] > 0 or contains_any(item_lower, ("fuel", "gas", "propane", "charcoal", "coal", "kindling")):
        primary = "Resource.Fuel"
    elif contains_any(item_lower, ("hook", "line", "lure", "net", "fishing")):
        primary = "Resource.Fishing"
    elif display == "weaponpart" or contains_any(item_lower, ("part", "receiver", "barrel", "stock", "slide")):
        primary = "Resource.Parts"
    elif contains_any(item_lower, ("glue", "adhesive", "epoxy", "paste", "ducttape")):
        primary = "Resource.Material.Adhesive"
    elif contains_any(item_lower, ("ceramic", "clay", "pottery", "mugshard")):
        primary = "Resource.Material.Ceramic"
    elif contains_any(item_lower, ("leather", "hide")):
        primary = "Resource.Material.Leather"
    elif contains_any(item_lower, ("cloth", "fabric", "thread", "yarn", "sheetrope", "denim", "wool")):
        primary = "Resource.Material.Textile"
    elif contains_any(item_lower, ("nail", "screw", "bolt", "nut", "hinge", "wire", "spring")):
        primary = "Resource.Material.Hardware"
    elif contains_any(item_lower, ("sand", "stone", "gravel", "ore", "limestone", "concrete", "cement", "brick")):
        primary = "Resource.Material.Mineral"
    elif contains_any(item_lower, ("glass", "windowpane", "jarlid")) or "base:glass" in facts["tagsLower"]:
        primary = "Resource.Material.Glass"
    elif contains_any(item_lower, ("scrap", "sheet", "metal", "steel", "iron", "ingot", "chain", "pipe")) or has_any_tag(
        facts["tags"], ["Base:HasMetal", "Base:SteelMaterial", "Base:Ingot"]
    ):
        primary = "Resource.Material.Metal"
    elif contains_any(item_lower, ("plank", "log", "lumber", "branch", "twig", "stick", "wood")):
        primary = "Resource.Material.Wood"
    elif contains_any(item_lower, ("bleach", "chemical", "powder", "acid", "solvent", "fertilizer")):
        primary = "Resource.Material.Chemical"
    elif contains_any(item_lower, ("paper", "card", "cardboard", "notepaper", "newspaper")):
        primary = "Resource.Material.Paper"
    elif item_lower.endswith("_empty") or contains_any(item_lower, ("box", "packaging", "bagseed", "wrapper")):
        primary = "Resource.Material.Packaging"
    tags = [primary]
    add_once(tags, "Resource.Craftable")
    return primary, tags


def classify_building(facts: Dict[str, object]) -> Tuple[str, List[str]]:
    item_lower = facts["idLower"]
    display = facts["displayCategoryLower"]
    primary = "Building.Moveable"
    if facts["isMoveable"]:
        if any(token in item_lower for token in ("sink", "shower", "toilet", "fridge", "freezer", "oven", "stove", "microwave", "washer", "dryer", "dishwasher")):
            primary = "Building.Fixture.Appliance"
        elif any(token in item_lower for token in ("chair", "stool")):
            primary = "Building.Furniture.Chair"
        elif any(token in item_lower for token in ("mattress", "bed", "futon", "coffin")):
            primary = "Building.Furniture.Bed"
        elif any(token in item_lower for token in ("cabinet", "drawers", "dresser", "shelf", "bookcase", "wardrobe", "crate", "mailbox")):
            primary = "Building.Furniture.Storage"
        elif any(token in item_lower for token in ("table",)):
            primary = "Building.Furniture.Table"
        elif any(token in item_lower for token in ("counter",)):
            primary = "Building.Furniture.Counter"
        else:
            primary = "Building.Moveable"
    elif display == "trapping" or "trap" in item_lower:
        primary = "Building.Survival.Trap"
    elif display == "camping" or contains_any(item_lower, ("tent", "sleepingbag", "bedroll")):
        primary = "Building.Survival"
    elif display == "vehiclemaintenance" or contains_any(item_lower, ("jack", "lugwrench", "brakefluid", "coolant", "enginedoor", "engineparts")):
        primary = "Building.Vehicle"
    elif display == "gardening":
        primary = "Building.Garden.Seed" if "seed" in item_lower else "Building.Garden"
    elif display == "household":
        primary = "Building.Fixture.Plumbing" if any(token in item_lower for token in ("sink", "shower", "toilet", "pipe", "valve", "plumbing")) else "Building.Fixture.Appliance"
    elif display == "furniture":
        primary = "Building.Furniture.Chair" if "chair" in item_lower else "Building.Furniture.General"
    return primary, [primary]


def classify_misc(_facts: Dict[str, object]) -> Tuple[str, List[str]]:
    return "Misc.General", ["Misc.General"]


def resolve_primary_and_tags(facts: Dict[str, object]) -> Tuple[str, List[str], str]:
    root = resolve_root(facts)
    if root == "Container":
        primary, tags = classify_container(facts)
    elif root == "Clothing":
        primary, tags = classify_clothing(facts)
    elif root == "Electronics":
        primary, tags = classify_electronics(facts)
    elif root == "Literature":
        primary, tags = classify_literature(facts)
    elif root == "Weapon":
        primary, tags = classify_weapon(facts)
    elif root == "Food":
        primary, tags = classify_food(facts)
    elif root == "Medical":
        primary, tags = classify_medical(facts)
    elif root == "Tool":
        primary, tags = classify_tool(facts)
    elif root == "Resource":
        primary, tags = classify_resource(facts)
    elif root == "Building":
        primary, tags = classify_building(facts)
    else:
        primary, tags = classify_misc(facts)
    return primary, unique_tags(tags), root


def derive_rarity(facts: Dict[str, object], primary: str) -> str:
    item_lower = facts["idLower"]
    if contains_any(item_lower, ("artifact", "relic")):
        return "Legendary"
    if primary.startswith("Weapon.Ranged.Firearm") or primary.startswith("Electronics.Generator") or contains_any(
        item_lower, ("katana", "diamond", "gold", "military", "generator")
    ):
        return "Rare"
    if primary.startswith("Container.Bag.Backpack") or primary.startswith("Electronics.Radio") or primary.startswith(
        "Medical"
    ) or contains_any(item_lower, ("pistol", "rifle", "shotgun", "revolver", "walkie", "radio", "backpack")):
        return "Uncommon"
    return "Common"


def derive_quality(facts: Dict[str, object]) -> str:
    item_lower = facts["idLower"]
    if contains_any(item_lower, ("broken", "trash", "junk", "worn", "dirty")):
        return "Waste"
    if facts["medical"] and contains_any(item_lower, ("sterile",)):
        return "Sterile"
    if contains_any(item_lower, ("gold", "diamond", "luxury", "premium", "whiskey", "wine", "champagne")):
        return "Luxury"
    return "Standard"


def derive_theme_tags(facts: Dict[str, object], primary: str) -> List[str]:
    item_lower = facts["idLower"]
    tags = []
    if contains_any(item_lower, ("police", "sheriff")):
        tags.append("Theme.Police")
    if contains_any(item_lower, ("military", "army", "ammo", "combat", "tactical")) or primary.startswith("Weapon"):
        tags.append("Theme.Militia" if "military" in item_lower or "army" in item_lower else "Theme.Combat")
    if facts["medical"] or primary.startswith("Medical"):
        tags.append("Theme.Clinical")
    if primary.startswith("Resource") or contains_any(item_lower, ("generator", "welder", "wrench", "scrap", "metal", "wire")):
        tags.append("Theme.Industrial")
    if contains_any(item_lower, ("bone", "stone", "primitive", "handmade", "forged")):
        tags.append("Theme.Primitive")
    if contains_any(item_lower, ("winter", "snow", "scarf", "beanie", "gloves")):
        tags.append("Theme.Winter")
    if primary.startswith("Building.Survival") or primary.startswith("Tool.Fishing") or primary.startswith("Resource.Fishing"):
        tags.append("Theme.Survival")
    return unique_tags(tags)


def build_item_tags(facts: Dict[str, object], primary: str, root_tags: List[str]) -> List[str]:
    tags = [primary]
    for tag in root_tags:
        add_once(tags, tag)

    rarity = derive_rarity(facts, primary)
    quality = derive_quality(facts)
    add_once(tags, f"Origin.{sanitize_origin_tag(facts['origin'])}")
    add_once(tags, f"Rarity.{rarity}")
    add_once(tags, f"Quality.{quality}")
    for theme_tag in derive_theme_tags(facts, primary):
        add_once(tags, theme_tag)
    return unique_tags(tags)


def rarity_bonus(tag: str) -> int:
    return {
        "Rarity.Common": 0,
        "Rarity.Uncommon": 4,
        "Rarity.Rare": 10,
        "Rarity.Legendary": 20,
        "Rarity.UltraRare": 30,
    }.get(tag, 0)


def quality_bonus(tag: str) -> int:
    return {
        "Quality.Waste": -6,
        "Quality.Standard": 0,
        "Quality.Sterile": 5,
        "Quality.Luxury": 12,
    }.get(tag, 0)


def theme_bonus(tag: str) -> int:
    return {
        "Theme.Police": 3,
        "Theme.Militia": 5,
        "Theme.Clinical": 4,
        "Theme.Industrial": 3,
        "Theme.Primitive": 2,
        "Theme.Winter": 2,
        "Theme.Survival": 4,
        "Theme.Combat": 4,
    }.get(tag, 0)


def score_base_variation(facts: Dict[str, object], primary: str, tags: List[str]) -> int:
    category = category_from_primary(primary)
    weight = facts["weight"]
    score = 2.0

    if category == "Food":
        shelf_life = min(90.0, facts["daysFresh"] + facts["daysRotten"])
        score = 7.0 + (facts["hunger"] * 1.8) + (facts["thirst"] * 1.1) + (facts["calories"] * 0.015) + (shelf_life * 0.12)
        score -= weight * 1.2
        score -= (facts["unhappy"] + facts["boredom"] + (facts["stress"] * 2.0)) * 0.15
        if primary == "Food.NonPerishable.Canned":
            score += 8
        if primary.startswith("Food.Drink.Alcohol"):
            score += 10
    elif category == "Medical":
        score = 12.0 + (facts["bandagePower"] * 4.0) + (facts["reduceInfectionPower"] * 3.0) - (weight * 0.8)
        if primary.endswith(".Pills"):
            score += 8
        if primary.endswith(".Vitamin"):
            score += 4
        if primary.endswith(".Drug"):
            score += 6
    elif category == "Weapon":
        avg_damage = (facts["minDamage"] + facts["maxDamage"]) * 0.5
        score = 14.0 + (avg_damage * 18.0) + (facts["maxRange"] * 3.0) + (facts["maxHit"] * 6.0) + (facts["conditionMax"] * 1.0)
        score -= weight * 1.5
        if primary.startswith("Weapon.Ranged.Firearm"):
            score += 18
        elif primary.startswith("Weapon.Ranged.Ammo"):
            score = 10 + (facts["conditionMax"] * 0.2)
        elif primary.startswith("Weapon.Explosive"):
            score += 22
        elif primary.startswith("Weapon.Part"):
            score = 16 + (facts["conditionMax"] * 0.3)
    elif category == "Tool":
        score = 10.0 + (facts["conditionMax"] * 0.9) + (facts["useDelta"] > 0 and 6.0 or 0.0) - (weight * 1.0)
        if primary.startswith("Tool.Cookware"):
            score += 6
        if primary.startswith("Tool.Medical"):
            score += 9
        if primary.startswith("Tool.Crafting"):
            score += 7
        if primary.startswith("Tool.Farming"):
            score += 6
    elif category == "Container":
        score = 14.0 + (facts["capacity"] * 1.2) + (facts["weightReduction"] * 0.18) - (weight * 1.2)
        if primary.startswith("Container.Liquid"):
            score += 4
    elif category == "Clothing":
        defense = (facts["biteDefense"] * 1.6) + (facts["scratchDefense"] * 1.2) + (facts["bulletDefense"] * 2.4)
        score = 5.0 + defense + (facts["insulation"] * 8.0) + (facts["windResistance"] * 6.0) - (weight * 1.2)
    elif category == "Electronics":
        score = 14.0 - (weight * 1.2)
        if primary.startswith("Electronics.Generator"):
            score += 28
        if primary.startswith("Electronics.Battery"):
            score += 8
        if primary.startswith("Electronics.Radio"):
            score += 14
        if primary.startswith("Electronics.Television"):
            score += 12
    elif category == "Resource":
        score = 6.0 - (weight * 0.6)
        if primary.startswith("Resource.Fuel"):
            score += 16
        if primary.startswith("Resource.Material.Metal"):
            score += 6
        if primary.startswith("Resource.Material.Chemical"):
            score += 8
        if primary.startswith("Resource.Parts"):
            score += 10
    elif category == "Building":
        score = 8.0 + (facts["capacity"] * 0.4) - (weight * 0.8)
        if primary.startswith("Building.Fixture.Appliance"):
            score += 10
        if primary.startswith("Building.Vehicle"):
            score += 8
        if primary.startswith("Building.Survival"):
            score += 6
    else:
        score = 3.0 - (weight * 0.5)

    for tag in tags:
        score += rarity_bonus(tag)
        score += quality_bonus(tag)
        score += theme_bonus(tag)

    return max(1, int(round(score)))


def base_stock_for_weight(weight: float) -> int:
    if weight <= 0.05:
        return 50
    if weight <= 0.2:
        return 25
    if weight <= 0.5:
        return 15
    if weight <= 1.5:
        return 10
    if weight <= 5.0:
        return 5
    return 2


def calculate_stock_range(facts: Dict[str, object], primary: str, tags: List[str]) -> Dict[str, int]:
    base_max = base_stock_for_weight(facts["weight"])
    mult = DEFAULT_STOCK_MULTIPLIERS.get(category_from_primary(primary), 1.0)
    for tag in tags:
        if tag in DEFAULT_STOCK_MULTIPLIERS:
            mult *= DEFAULT_STOCK_MULTIPLIERS[tag]
    if primary.startswith("Food.Perishable"):
        mult *= 0.75
    if primary.startswith("Weapon.Ranged.Ammo"):
        mult *= 1.5
    if primary.startswith("Container.Bag"):
        mult *= 0.7
    if primary.startswith("Electronics.Generator") or primary.startswith("Weapon.Explosive"):
        mult *= 0.5
    max_stock = max(0, int(round(base_max * mult)))
    min_ratio = 0.2
    if primary.startswith("Weapon.Ranged.Firearm") or primary.startswith("Weapon.Explosive"):
        min_ratio = 0.0
    elif primary.startswith("Food.Perishable"):
        min_ratio = 0.1
    min_stock = max(0, int(max_stock * min_ratio))
    return {"min": min_stock, "max": max_stock}


def parse_runtime_rules(runtime_rules_path: Path):
    text = runtime_rules_path.read_text(encoding="utf-8", errors="ignore") if runtime_rules_path.exists() else ""
    blacklisted = set()
    whitelisted = set()
    for list_name, target in (("blacklist", blacklisted), ("whitelist", whitelisted)):
        match = re.search(rf"{list_name}\s*=\s*\{{(.*?)\}}", text, re.DOTALL)
        if not match:
            continue
        for quoted in re.findall(r'"([^"]+)"', match.group(1)):
            target.add(quoted.strip())
    return blacklisted, whitelisted


def build_mod_index(workshop_root: Path) -> Dict[str, Path]:
    index: Dict[str, Path] = {}
    for mod_info in workshop_root.glob("*/Contents/mods/*/42.16/mod.info"):
        mod_id = mod_info.parent.parent.name
        index[mod_id] = mod_info.parent
    return index


def discover_source_files(active_mods: List[str], workshop_root: Path) -> Tuple[List[SourceFile], List[str]]:
    sources: List[SourceFile] = []
    missing_mods: List[str] = []
    if VANILLA_SCRIPTS_DIR.exists():
        for path in sorted(VANILLA_SCRIPTS_DIR.rglob("*.txt")):
            sources.append(SourceFile(path=path, origin="Vanilla", kind="vanilla"))

    mod_index = build_mod_index(workshop_root)
    for mod_id in active_mods:
        mod_root = mod_index.get(mod_id)
        if not mod_root:
            missing_mods.append(mod_id)
            continue
        seen = set()
        for path in sorted(mod_root.rglob("*.txt")):
            if "media/scripts" not in str(path).replace("\\", "/"):
                continue
            if path in seen:
                continue
            seen.add(path)
            sources.append(SourceFile(path=path, origin=mod_id, kind="mod"))
    return sources, missing_mods


def load_active_mods_from_server_ini(server_ini: Optional[Path]) -> List[str]:
    if not server_ini or not server_ini.exists():
        return []
    for line in server_ini.read_text(encoding="utf-8", errors="ignore").splitlines():
        if line.startswith("Mods="):
            mods = [part.strip() for part in line.split("=", 1)[1].split(";")]
            return [mod for mod in mods if mod]
    return []


def load_rebuild_request(path: Optional[Path]) -> Dict[str, object]:
    if not path or not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def serialize_lua_string(value: str) -> str:
    text = str(value)
    text = text.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{text}"'


def write_index_file(path: Path, generated_at: str, active_mods: List[str], active_mods_hash: str, source_manifest_hash: str, files: List[Dict[str, str]]) -> None:
    lines = [
        "return {",
        f"    schemaVersion = {SCHEMA_VERSION},",
        f"    generatedAt = {serialize_lua_string(generated_at)},",
        f"    activeModsHash = {serialize_lua_string(active_mods_hash)},",
        f"    generatorVersion = {GENERATOR_VERSION},",
        f"    signatureVersion = {serialize_lua_string(SIGNATURE_VERSION)},",
        f"    pricingHeuristicVersion = {PRICING_HEURISTIC_VERSION},",
        f"    sourceManifestHash = {serialize_lua_string(source_manifest_hash)},",
        "    activeMods = {",
    ]
    for mod_id in active_mods:
        lines.append(f"        {serialize_lua_string(mod_id)},")
    lines.extend(
        [
            "    },",
            "",
            "    files = {",
        ]
    )
    for file_entry in files:
        lines.append(
            "        { category = %s, subcategory = %s, path = %s },"
            % (
                serialize_lua_string(file_entry["category"]),
                serialize_lua_string(file_entry["subcategory"]),
                serialize_lua_string(file_entry["path"]),
            )
        )
    lines.extend(["    }", "}", ""])
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\r\n".join(lines), encoding="utf-8")


def write_grouped_files(output_root: Path, items: Dict[str, Dict[str, object]], generated_at: str):
    grouped = OrderedDict()
    for full_type in sorted(items):
        item = items[full_type]
        file_entry = to_file_entry(item["primary"])
        path = file_entry["path"]
        payload = grouped.setdefault(
            path,
            {
                "category": file_entry["category"],
                "subcategory": file_entry["subcategory"],
                "groups": OrderedDict(),
            },
        )
        group_key = (item["origin"], tuple(item["tags"]))
        bucket = payload["groups"].setdefault(
            group_key,
            {
                "origin": item["origin"],
                "tags": list(item["tags"]),
                "items": [],
            },
        )
        bucket["items"].append(item)

    files = []
    for path, payload in grouped.items():
        lines = [
            f"# schema={FILE_SCHEMA}",
            f"# category={payload['category']}",
            f"# subcategory={payload['subcategory']}",
            f"# generatedAt={generated_at}",
            "",
        ]
        for (_, _), group in payload["groups"].items():
            lines.append(f"@origin={group['origin']}")
            lines.append("@tags=" + "|".join(group["tags"]))
            for item in sorted(group["items"], key=lambda row: row["item"]):
                lines.append(f"{item['item']}|{int(item['basePrice'])}|{int(item['stockRange']['min'])}|{int(item['stockRange']['max'])}")
            lines.append("")
        out_path = output_root / path
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text("\r\n".join(lines), encoding="utf-8")
        files.append({"category": payload["category"], "subcategory": payload["subcategory"], "path": path})

    files.sort(key=lambda entry: (CATEGORY_ORDER.get(entry["category"], 999), entry["category"], entry["subcategory"], entry["path"]))
    return files


def write_sandbox_assets(standalone_root: Path, price_additions: Dict[str, int], stock_defaults: Dict[str, float]) -> None:
    sandbox_path = standalone_root / "sandbox-options.txt"
    translation_path = standalone_root / "lua" / "shared" / "Translate" / "EN" / "Sandbox.json"

    option_lines = [
        "VERSION = 1,",
        "",
        "option MarketSense.PriceMultiplier",
        "{",
        "    type = double,",
        "    default = 1.0,",
        "    min = 0.0,",
        "    max = 100.0,",
        "    page = MarketSenseGlobal,",
        "    translation = MarketSense.PriceMultiplier,",
        "}",
        "",
        "option MarketSense.PriceGlobalValue",
        "{",
        "    type = integer,",
        "    default = 0,",
        "    min = -1000000,",
        "    max = 1000000,",
        "    page = MarketSenseGlobal,",
        "    translation = MarketSense.PriceGlobalValue,",
        "}",
        "",
        "option MarketSense.StockMultiplier",
        "{",
        "    type = double,",
        "    default = 0.9,",
        "    min = 0.0,",
        "    max = 100.0,",
        "    page = MarketSenseGlobal,",
        "    translation = MarketSense.StockMultiplier,",
        "}",
        "",
    ]
    translations = {
        "Sandbox_MarketSenseGlobal": "Market Sense: Global",
        "Sandbox_MarketSense.PriceMultiplier": "Price Multiplier: Global",
        "Sandbox_MarketSense.PriceMultiplier_tooltip": "Secondary multiplier applied AFTER additive values.",
        "Sandbox_MarketSense.PriceGlobalValue": "Price Addition: Global",
        "Sandbox_MarketSense.PriceGlobalValue_tooltip": "Flat price addition applied to ALL items.",
        "Sandbox_MarketSense.StockMultiplier": "Stock: Global",
        "Sandbox_MarketSense.StockMultiplier_tooltip": "Base stock multiplier applied to ALL items.",
    }

    used_pages = set(["MarketSenseGlobal"])
    for tag in iter_exposed_tags():
        root = primary_root(tag)
        page = page_name_for_tag(tag)
        used_pages.add(page)
        if f"Sandbox_{page}" not in translations:
            translations[f"Sandbox_{page}"] = page_title_for_root(root)

        price_key = option_key("Price", tag, "Value")
        stock_key = option_key("Stock", tag, "Mult")
        option_lines.extend(
            [
                f"option {price_key}",
                "{",
                "    type = integer,",
                f"    default = {int(price_additions.get(tag, 0))},",
                "    min = -1000000,",
                "    max = 1000000,",
                f"    page = {page},",
                f"    translation = {price_key},",
                "}",
                "",
                f"option {stock_key}",
                "{",
                "    type = double,",
                f"    default = {float(stock_defaults.get(tag, 1.0))},",
                "    min = 0.0,",
                "    max = 100.0,",
                f"    page = {page},",
                f"    translation = {stock_key},",
                "}",
                "",
            ]
        )
        translations[f"Sandbox_{price_key}"] = option_label("Price", tag)
        translations[f"Sandbox_{price_key}_tooltip"] = option_tooltip("Price", tag)
        translations[f"Sandbox_{stock_key}"] = option_label("Stock", tag)
        translations[f"Sandbox_{stock_key}_tooltip"] = option_tooltip("Stock", tag)

    sandbox_path.parent.mkdir(parents=True, exist_ok=True)
    sandbox_path.write_text("\n".join(option_lines), encoding="utf-8")
    translation_path.parent.mkdir(parents=True, exist_ok=True)
    translation_path.write_text(json.dumps(dict(sorted(translations.items())), indent=4, sort_keys=True) + "\n", encoding="utf-8")


def write_taxonomy_lua(path: Path) -> None:
    export = build_taxonomy_export()
    lines = [
        "-- Market Sense Tag Taxonomy",
        "-- Auto-generated by market_sense_prebuild.py",
        "",
        "return {",
        f"    generatorVersion = {export['generatorVersion']},",
        f"    schemaVersion = {export['schemaVersion']},",
        f"    signatureVersion = {serialize_lua_string(export['signatureVersion'])},",
        f"    pricingHeuristicVersion = {export['pricingHeuristicVersion']},",
        "    categoryOrder = {",
    ]
    for key, value in export["categoryOrder"].items():
        lines.append(f"        [{serialize_lua_string(key)}] = {int(value)},")
    lines.extend(["    },", "    descriptorRoots = {"])
    for root in export["descriptorRoots"]:
        lines.append(f"        {serialize_lua_string(root)},")
    lines.extend(["    },", "    priceTags = {"])
    for tag in export["priceTags"]:
        lines.append(f"        {serialize_lua_string(tag)},")
    lines.extend(["    },", "    stockMultipliers = {"])
    for key, value in sorted(export["stockMultipliers"].items()):
        lines.append(f"        [{serialize_lua_string(key)}] = {float(value)},")
    lines.extend(["    },", "}", ""])
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines), encoding="utf-8")


def write_tag_additions_lua(path: Path, price_additions: Dict[str, int]) -> None:
    lines = [
        "-- DynamicTrading Tag Price Additions",
        "-- Auto-generated by market_sense_prebuild.py",
        "",
        "return {",
        "    tagAdditions = {",
    ]
    for key, value in price_additions.items():
        lines.append(f"        [{serialize_lua_string(key)}] = {int(value)},")
    lines.extend(["    },", "}", ""])
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines), encoding="utf-8")


def group_and_classify(parsed_items: List[ParsedItem], blacklisted: set, whitelisted: set):
    items_by_full_type: OrderedDict[str, Dict[str, object]] = OrderedDict()
    overrides = []
    fallback_items = []
    skipped = []

    for parsed in parsed_items:
        facts = normalize_facts(parsed)
        short_name = parsed.type_name
        if short_name in blacklisted or parsed.full_type in blacklisted:
            if parsed.full_type not in whitelisted and short_name not in whitelisted:
                skipped.append(parsed.full_type)
                continue

        primary, root_tags, root = resolve_primary_and_tags(facts)
        tags = build_item_tags(facts, primary, root_tags)
        if root == "Misc":
            fallback_items.append(parsed.full_type)

        entry = {
            "item": parsed.full_type,
            "origin": parsed.origin,
            "primary": primary,
            "tags": tags,
            "expandedTags": expand_hierarchy(tags),
            "basePrice": score_base_variation(facts, primary, tags),
            "stockRange": calculate_stock_range(facts, primary, tags),
            "facts": facts,
            "sourcePath": parsed.source_path,
        }
        if parsed.full_type in items_by_full_type:
            overrides.append(parsed.full_type)
        items_by_full_type[parsed.full_type] = entry

    return items_by_full_type, overrides, fallback_items, skipped


def build_audit_report(
    generated_at: str,
    active_mods: List[str],
    active_mods_hash: str,
    source_manifest_hash: str,
    items: Dict[str, Dict[str, object]],
    missing_mods: List[str],
    overrides: List[str],
    fallback_items: List[str],
    skipped_items: List[str],
    golden_results: Dict[str, Dict[str, object]],
):
    category_counts = Counter()
    primary_counts = Counter()
    origin_counts = Counter()
    for item in items.values():
        category_counts[category_from_primary(item["primary"])] += 1
        primary_counts[item["primary"]] += 1
        origin_counts[item["origin"]] += 1

    return {
        "generatedAt": generated_at,
        "generatorVersion": GENERATOR_VERSION,
        "schemaVersion": SCHEMA_VERSION,
        "signatureVersion": SIGNATURE_VERSION,
        "pricingHeuristicVersion": PRICING_HEURISTIC_VERSION,
        "activeMods": active_mods,
        "activeModsHash": active_mods_hash,
        "sourceManifestHash": source_manifest_hash,
        "totals": {
            "items": len(items),
            "missingMods": len(missing_mods),
            "overrides": len(overrides),
            "fallbackItems": len(fallback_items),
            "skippedItems": len(skipped_items),
        },
        "countsByCategory": dict(sorted(category_counts.items())),
        "countsByOrigin": dict(sorted(origin_counts.items())),
        "topPrimaries": dict(primary_counts.most_common(40)),
        "missingMods": missing_mods,
        "overrides": sorted(set(overrides)),
        "fallbackItems": sorted(set(fallback_items)),
        "skippedItems": sorted(set(skipped_items)),
        "goldenResults": golden_results,
    }


def verify_golden_cases(items: Dict[str, Dict[str, object]]) -> Dict[str, Dict[str, object]]:
    expectations = {
        "Base.Bag_DuffelBag": "Container.Bag.Duffel",
        "Base.FirstAidKit": "Container",
        "Base.Bandage": "Medical",
        "Base.WalkieTalkie1": "Electronics.Radio.TwoWay.Walkie",
        "Base.Battery": "Electronics.Battery",
    }
    results = {}
    for full_type, expected in expectations.items():
        item = items.get(full_type)
        actual = item["primary"] if item else None
        ok = False
        if actual:
            ok = actual == expected or actual.startswith(expected + ".")
        results[full_type] = {
            "expected": expected,
            "actual": actual,
            "ok": ok,
        }
    for full_type in ("Base.Firecracker", "Base.BareHands"):
        item = items.get(full_type)
        actual = item["primary"] if item else None
        results[full_type] = {
            "expected": "Weapon root if script evidence says so",
            "actual": actual,
            "ok": bool(actual and actual.startswith("Weapon.")),
        }
    return results


def read_active_mods(args, request_payload) -> List[str]:
    if args.mods:
        mods = []
        for token in args.mods.split(";"):
            clean = token.strip()
            if clean:
                mods.append(clean)
        return mods
    request_mods = request_payload.get("activeMods")
    if isinstance(request_mods, list):
        mods = [str(mod).strip() for mod in request_mods if str(mod).strip()]
        if mods:
            return mods
    ini_mods = load_active_mods_from_server_ini(args.server_config)
    if ini_mods:
        return ini_mods
    return []


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Regenerate DT_Items data for MarketSense maintenance and audits.")
    parser.add_argument("--mods", help="Semicolon-separated active mod list.")
    parser.add_argument("--server-config", type=Path, default=DEFAULT_SERVER_INI, help="Server ini file used to resolve active mods.")
    parser.add_argument("--request-file", type=Path, default=DEFAULT_REQUEST_FILE, help="Optional DT rebuild request JSON.")
    parser.add_argument("--output-root", type=Path, default=DEFAULT_OUTPUT_ROOT, help="Target Zomboid/Lua/DT_Items root.")
    parser.add_argument("--audit-file", type=Path, default=DEFAULT_AUDIT_FILE, help="Audit report output path.")
    parser.add_argument("--workshop-root", type=Path, default=WORKSHOP_ROOT, help="Workshop root containing local mod checkouts.")
    parser.add_argument("--cache-dir", type=Path, default=DEFAULT_CACHE_DIR, help="Persistent parser cache directory.")
    parser.add_argument("--standalone-root", type=Path, default=DEFAULT_STANDALONE_ROOT, help="Standalone MarketSense media root.")
    parser.add_argument("--taxonomy-lua", type=Path, default=DEFAULT_TAXONOMY_LUA, help="Generated taxonomy Lua export path.")
    parser.add_argument("--tag-additions-lua", type=Path, default=DEFAULT_TAG_ADDITION_LUA, help="Generated tag additions Lua export path.")
    parser.add_argument("--runtime-rules-lua", type=Path, default=DEFAULT_RUNTIME_RULES_LUA, help="Runtime rules source used for blacklist support.")
    parser.add_argument("--skip-asset-sync", action="store_true", help="Do not regenerate standalone sandbox assets or shared taxonomy exports.")
    args = parser.parse_args(argv)

    request_payload = load_rebuild_request(args.request_file)
    active_mods = read_active_mods(args, request_payload)
    active_mods = sorted(unique_tags(active_mods))
    active_mods_hash = stable_hash(active_mods)
    generated_at = utc_timestamp()

    source_files, missing_mods = discover_source_files(active_mods, args.workshop_root)
    if not source_files:
        print("No source files discovered. Check your vanilla/scripts path or active mod list.", file=sys.stderr)
        return 1

    args.cache_dir.mkdir(parents=True, exist_ok=True)
    parse_cache = args.cache_dir / "parse_cache.json"
    parsed_items, source_manifest_hash = parse_with_cache(source_files, parse_cache)

    blacklisted, whitelisted = parse_runtime_rules(args.runtime_rules_lua)
    items, overrides, fallback_items, skipped_items = group_and_classify(parsed_items, blacklisted, whitelisted)

    files = write_grouped_files(args.output_root, items, generated_at)
    write_index_file(
        args.output_root / "DT_ItemsIndex.lua",
        generated_at=generated_at,
        active_mods=active_mods,
        active_mods_hash=active_mods_hash,
        source_manifest_hash=source_manifest_hash,
        files=files,
    )

    golden_results = verify_golden_cases(items)
    audit_report = build_audit_report(
        generated_at=generated_at,
        active_mods=active_mods,
        active_mods_hash=active_mods_hash,
        source_manifest_hash=source_manifest_hash,
        items=items,
        missing_mods=missing_mods,
        overrides=overrides,
        fallback_items=fallback_items,
        skipped_items=skipped_items,
        golden_results=golden_results,
    )
    json_dump(args.audit_file, audit_report)

    if not args.skip_asset_sync:
        write_taxonomy_lua(args.taxonomy_lua)
        write_tag_additions_lua(args.tag_additions_lua, DEFAULT_PRICE_ADDITIONS)
        write_sandbox_assets(args.standalone_root, DEFAULT_PRICE_ADDITIONS, DEFAULT_STOCK_MULTIPLIERS)

    if args.request_file and args.request_file.exists():
        try:
            args.request_file.unlink()
        except OSError:
            pass

    summary = {
        "items": len(items),
        "files": len(files),
        "activeMods": active_mods,
        "missingMods": missing_mods,
        "fallbackItems": len(fallback_items),
        "goldenFailures": [key for key, row in golden_results.items() if not row["ok"]],
    }
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
