"""Conservative prefilters for bounded category audits.

The Lua classifier remains authoritative.  These hints only decide which
definitions are sent through the expensive availability/property/Lua phases;
the evaluator performs an exact category check on the returned rows afterward.
Only Food currently has a validated source prefilter. Other named categories
deliberately fall back to the complete universe until their source signals are
proven not to omit classifier-derived rows.
"""

from __future__ import annotations

import re
from typing import Any, Iterable

from .models import ItemDefinition


ALL_CATEGORY_LABEL = "All categories"
CATEGORY_SCOPE_CHOICES = (
    ALL_CATEGORY_LABEL,
    "Food",
    "Liquid",
    "Resource",
    "Medical",
    "Weapon",
    "Clothing",
    "Literature",
    "Container",
    "Electronics",
    "Tool",
    "Building",
    "Misc",
)

# A prefilter is allowed only after comparing it with the authoritative Lua
# category output on the current catalog. Food has complete coverage there;
# broader taxonomy roots can be inferred from MarketSense tags that are not
# present in the raw item script, so they stay exact-but-unbounded for now.
PREFILTERED_CATEGORY_CHOICES = frozenset({"Food"})


def _token(value: Any) -> str:
    return re.sub(r"[^a-z0-9]", "", str(value or "").casefold())


def _text(value: Any) -> str:
    if isinstance(value, (list, tuple, set)):
        return " ".join(str(part or "") for part in value).casefold()
    return str(value or "").casefold()


def _truthy(value: Any) -> bool:
    if value in (None, "", False, 0, 0.0):
        return False
    if isinstance(value, str) and value.strip().casefold() in {"false", "no", "0"}:
        return False
    return True


def normalize_category_filter(value: str | None) -> str:
    """Return a canonical root category or an empty value for an unbounded scan."""

    text = str(value or "").strip()
    key = _token(text)
    if not key or key in {"all", "allcategories", "none"}:
        return ""
    for choice in CATEGORY_SCOPE_CHOICES:
        if _token(choice) == key:
            return "" if choice == ALL_CATEGORY_LABEL else choice
    return text


def category_scope_label(value: str | None) -> str:
    category = normalize_category_filter(value)
    return category or ALL_CATEGORY_LABEL


def row_matches_category(row: dict[str, Any], category: str | None) -> bool:
    selected = normalize_category_filter(category)
    return not selected or _token(row.get("category")) == _token(selected)


def _food_candidate(definition: ItemDefinition) -> bool:
    props = definition.props
    display = _token(props.get("displayCategory"))
    item_type = _token(_text(props.get("itemType")).rsplit(":", 1)[-1])
    loot_type = _token(props.get("lootType"))
    tags = _text(props.get("tags"))
    searchable = " ".join(
        [
            definition.full_type,
            *(str(props.get(key) or "") for key in (
                "displayName", "tooltip", "description", "icon",
                "worldStaticModel", "worldObjectSprite", "replaceOnUse",
                "replaceOnCooked", "onCooked", "doubleClickRecipe",
                "evolvedRecipe", "evolvedRecipeName", "eatType", "foodType",
            )),
            tags,
        ]
    ).casefold()

    if display in {"food", "cooking"}:
        return True
    if item_type in {"food", "eat", "eatsmall"}:
        return True
    if loot_type in {"food", "cannedfood"}:
        return True
    if _truthy(props.get("foodType")) or _truthy(props.get("eatType")):
        return True
    if any(
        _truthy(props.get(key))
        for key in (
            "hungerChange", "thirstChange", "calories", "carbohydrates",
            "lipids", "proteins", "daysFresh", "daysRotten", "canAge",
            "cannedFood", "packaged", "spice",
        )
    ):
        return True

    # These are intentionally broad.  A false positive only adds a candidate
    # to the bounded Lua pass; it cannot make a non-Food row appear in output.
    food_markers = (
        "preservedfood", "fishmeat", "animalmeat", "foodtype", "canned",
        "rationcan", "tincan", "emptyjar", "openboxofcannedfood",
        "opencannedfood", "pancakemix", "gravymix", "animalmilkpowder",
        "apple", "banana", "berry", "berries", "cherry", "fruit", "grape",
        "grapefruit", "lemon", "lime", "orange", "peach", "pear", "pineapple",
        "strawberr", "watermelon", "beet", "broccoli", "cabbage", "carrot",
        "corn", "cucumber", "eggplant", "leek", "lettuce", "onion", "pea",
        "pepper", "potato", "radish", "tomato", "vegetable", "zucchini",
        "catfish", "crappie", "fish", "gar", "lobster", "roe", "salmon",
        "sardine", "seafood", "shrimp", "trout", "bacon", "beef", "chicken",
        "meat", "mutton", "pork", "poultry", "rabbit", "sausage", "steak",
        "venison",
    )
    return any(marker in searchable for marker in food_markers)


def _category_candidate(definition: ItemDefinition, category: str) -> bool:
    props = definition.props
    key = _token(category)
    if key == "food":
        return _food_candidate(definition)

    display = _token(props.get("displayCategory"))
    item_type = _token(_text(props.get("itemType")).rsplit(":", 1)[-1])
    loot_type = _token(props.get("lootType"))
    tags = _token(_text(props.get("tags")))
    searchable = " ".join(
        [definition.full_type, _text(props.get("displayName")), tags]
    )

    aliases = {
        "liquid": {"liquid", "fluid"},
        "resource": {"material", "materialweapon", "paint"},
        "medical": {"medical", "firstaid"},
        "weapon": {"weapon", "ammo", "explosives", "weaponpart"},
        "clothing": {"clothing", "protectivegear", "accessory"},
        "literature": {"literature", "skillbook", "cartography", "reciperesource"},
        "container": {"container", "watercontainer", "bag"},
        "electronics": {"electronics", "radio"},
        "tool": {"tool", "tools"},
        "building": {"building", "gardening", "furniture"},
    }
    if display in aliases.get(key, {key}) or item_type == key or loot_type == key:
        return True
    if key == "liquid" and any(
        _truthy(props.get(name))
        for name in ("fluidContainer", "fluidType", "fluidTypes", "canStoreWater")
    ):
        return True
    if key == "resource" and any(
        marker in searchable.casefold()
        for marker in ("paint", "material", "ore", "metalbar", "wood")
    ):
        return True
    if key == "medical" and any(
        _truthy(props.get(name)) for name in ("bandagePower", "reduceInfectionPower")
    ):
        return True
    if key == "weapon" and any(
        _truthy(props.get(name))
        for name in ("maxDamage", "ammoType", "magazineType", "weaponCategories")
    ):
        return True
    if key == "clothing" and any(
        _truthy(props.get(name)) for name in ("bodyLocation", "bloodClothingType")
    ):
        return True
    if key == "literature" and any(
        _truthy(props.get(name)) for name in ("learnedRecipes", "skillTrained", "readType")
    ):
        return True
    if key == "container" and any(
        _truthy(props.get(name)) for name in ("capacity", "canStoreWater", "fluidContainer")
    ):
        return True
    return key in searchable.casefold()


def candidate_definitions(
    definitions: Iterable[ItemDefinition], category: str | None,
) -> list[ItemDefinition]:
    """Select conservative source candidates for a bounded category scan."""

    definitions = list(definitions)
    selected = normalize_category_filter(category)
    if not selected or _token(selected) in {"misc"}:
        return definitions
    if selected not in PREFILTERED_CATEGORY_CHOICES:
        return definitions
    if _token(selected) not in {
        _token(choice) for choice in CATEGORY_SCOPE_CHOICES
        if choice != ALL_CATEGORY_LABEL
    }:
        return definitions
    return [
        definition for definition in definitions
        if _category_candidate(definition, selected)
    ]
