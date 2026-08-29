"""Deterministic fixtures for checking the real MarketSense Lua evaluator."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from .bridge import run_lua, run_lua_result
from .models import ItemDefinition, WorkshopMod


def mock_definitions() -> list[ItemDefinition]:
    """Return stable fixtures that exercise the real evaluator, not a clone."""
    fixture_mod = WorkshopMod(
        root=Path("<offline-fixture>"),
        workshop_id="fixture",
        mod_id="MarketSenseFixture",
        name="MarketSense offline fixture",
        source_kind="fixture",
    )

    def make(name: str, props: dict[str, Any]) -> ItemDefinition:
        return ItemDefinition(
            full_type=f"MarketSenseFixture.{name}",
            module="MarketSenseFixture",
            props=props,
            mod=fixture_mod,
            script_path="<offline-fixture>",
        )

    return [
        make("FoodLow", {
            "itemType": "Food", "displayCategory": "Food", "foodType": "Meat",
            "hungerChange": -0.05, "calories": 50, "daysFresh": 1, "daysRotten": 2,
            "actualWeight": 0.2, "description": "a small portion of meat",
            "canSpawnAsLoot": True,
        }),
        make("FoodHigh", {
            "itemType": "Food", "displayCategory": "Food", "foodType": "Meat",
            "hungerChange": -0.8, "calories": 800, "daysFresh": 10, "daysRotten": 20,
            "actualWeight": 0.2, "description": "a large portion of meat",
            "canSpawnAsLoot": True,
        }),
        make("CannedMeal", {
            "itemType": "Food", "displayCategory": "Food", "hungerChange": -0.2,
            "calories": 250, "daysFresh": 20, "daysRotten": 40, "actualWeight": 0.5,
            "description": "Canned preserved bean meal", "isCraftRecipeProduct": True,
        }),
        make("VanillaReceipt", {
            "itemType": "base:literature", "displayCategory": "Junk",
            "tags": ["base:uninteresting"], "readType": "photo",
            "description": "a small receipt", "canSpawnAsLoot": True,
        }),
        make("NarcoticsSeedPacket", {
            "itemType": "Base:Literature", "displayCategory": "Drugs",
            "tags": ["Base:FastRead"], "readType": "photo",
            "learnedRecipes": "Weed Growing Season", "isCraftRecipeProduct": True,
            "description": "a packet of growing seeds", "canSpawnAsLoot": True,
        }),
        ItemDefinition(
            full_type="Base.Flier_Nolans", module="Base",
            props={
                "itemType": "base:literature", "displayCategory": "Junk",
                "tags": ["base:fastread", "base:picture"], "readType": "photo",
            }, mod=fixture_mod, script_path="<offline-fixture>",
        ),
        make("Bandage", {
            "displayCategory": "FirstAid", "bandagePower": 1, "actualWeight": 0.1,
            "description": "sterile medical dressing", "canBeForaged": True,
        }),
        make("Axe", {
            "itemType": "Weapon", "displayCategory": "Weapon", "weaponCategories": ["Axe"],
            "minDamage": 1, "maxDamage": 2, "maxRange": 1, "conditionMax": 10,
            "actualWeight": 1.5, "description": "a heavy hand axe", "canSpawnAsLoot": True,
        }),
        make("Bag", {
            "itemType": "Container", "capacity": 20, "weightReduction": 80,
            "actualWeight": 1, "description": "a canvas carrying bag", "canSpawnAsLoot": True,
        }),
        make("DebugDummy", {
            "displayCategory": "Hidden", "displayName": "DUMMY ITEM", "hidden": True,
            "canSpawnAsLoot": True,
        }),
    ]


def self_test(lua: str) -> tuple[bool, list[dict[str, Any]]]:
    rows = run_lua(lua, mock_definitions())
    by_type = {row.get("fullType"): row for row in rows}
    checks: list[dict[str, Any]] = []

    def check(name: str, passed: bool, detail: str) -> None:
        checks.append({"name": name, "passed": bool(passed), "detail": detail})

    expected_types = {
        "MarketSenseFixture.FoodLow", "MarketSenseFixture.FoodHigh",
        "MarketSenseFixture.CannedMeal", "MarketSenseFixture.VanillaReceipt",
        "MarketSenseFixture.NarcoticsSeedPacket", "MarketSenseFixture.Bandage",
        "Base.Flier_Nolans",
        "MarketSenseFixture.Axe", "MarketSenseFixture.Bag",
        "MarketSenseFixture.DebugDummy",
    }
    check(
        "all fixture rows evaluated",
        set(by_type) == expected_types and all(not row.get("error") for row in rows),
        f"{len(rows)}/{len(expected_types)} rows, errors={sum(1 for row in rows if row.get('error'))}",
    )

    expected_categories = {
        "MarketSenseFixture.FoodLow": "Food",
        "MarketSenseFixture.FoodHigh": "Food",
        "MarketSenseFixture.CannedMeal": "Food",
        "MarketSenseFixture.VanillaReceipt": "Literature",
        "MarketSenseFixture.NarcoticsSeedPacket": "Building",
        "Base.Flier_Nolans": "Literature",
        "MarketSenseFixture.Bandage": "Medical",
        "MarketSenseFixture.Axe": "Weapon",
        "MarketSenseFixture.Bag": "Container",
        "MarketSenseFixture.DebugDummy": "Misc",
    }
    category_ok = all(
        by_type.get(item, {}).get("category") == category
        for item, category in expected_categories.items()
    )
    check(
        "root categories",
        category_ok,
        ", ".join(
            f"{item.rsplit('.', 1)[-1]}={by_type.get(item, {}).get('category', '?')}"
            for item in sorted(expected_categories)
        ),
    )

    receipt = by_type.get("MarketSenseFixture.VanillaReceipt", {})
    receipt_detection = receipt.get("detection") or {}
    check(
        "vanilla junk literature is not a photo",
        (
            receipt.get("primary") == "LiteratureOrJunk"
            and receipt_detection.get("resolverSource") == "root_literature"
            and (receipt_detection.get("classifier") or {}).get("details", {}).get("source")
            == "lit_uninteresting"
        ),
        f"primary={receipt.get('primary', '?')} source="
        f"{((receipt_detection.get('classifier') or {}).get('details') or {}).get('source', '?')}",
    )

    flier = by_type.get("Base.Flier_Nolans", {})
    check(
        "vanilla flier uses its explicit literature subtype",
        flier.get("primary") == "LiteratureFlier",
        f"primary={flier.get('primary', '?')} source={flier.get('source', '?')}",
    )

    seed = by_type.get("MarketSenseFixture.NarcoticsSeedPacket", {})
    seed_context = seed.get("context") or {}
    seed_detection = seed.get("detection") or {}
    check(
        "literature-backed seed packet is gardening stock",
        (
            seed.get("category") == "Building"
            and seed.get("primary") == "GardeningSeedPacket"
            and seed_detection.get("root") == "Building"
            and (seed_detection.get("classifier") or {}).get("signature") == "Gardening"
            and seed_context.get("learnedRecipes") == ["Weed Growing Season"]
        ),
        f"category={seed.get('category', '?')} primary={seed.get('primary', '?')} "
        f"root={seed_detection.get('root', '?')} recipes={seed_context.get('learnedRecipes', '?')}",
    )

    availability = {
        item: by_type.get(item, {}).get("availability") or {}
        for item in expected_types
    }
    check(
        "Lua runtime availability gate",
        (
            availability["MarketSenseFixture.FoodLow"].get("status") == "obtainable"
            and availability["MarketSenseFixture.CannedMeal"].get("status") == "obtainable"
            and availability["MarketSenseFixture.Bandage"].get("status") == "obtainable"
            and availability["MarketSenseFixture.DebugDummy"].get("status") == "excluded"
            and availability["MarketSenseFixture.DebugDummy"].get("obtainable") is False
        ),
        ", ".join(
            f"{item.rsplit('.', 1)[-1]}={availability[item].get('status', '?')}"
            for item in sorted(expected_types)
        ),
    )

    low = by_type.get("MarketSenseFixture.FoodLow", {})
    high = by_type.get("MarketSenseFixture.FoodHigh", {})
    check(
        "price responds to food stats",
        high.get("price", 0) > low.get("price", 0),
        f"FoodLow={low.get('price', '?')} FoodHigh={high.get('price', '?')}",
    )
    check(
        "description reaches context",
        low.get("description") == "a small portion of meat",
        f"description={low.get('description', '?')!r}",
    )
    canned = by_type.get("MarketSenseFixture.CannedMeal", {})
    check(
        "description affects subtype",
        canned.get("primary") == "FoodNonPerishableCanned",
        f"CannedMeal primary={canned.get('primary', '?')}",
    )
    canned_hierarchy = canned.get("hierarchy") or {}
    canned_detection = canned.get("detection") or {}
    check(
        "Lua hierarchy and detector provenance",
        (
            canned.get("categoryPath") == "Food > NonPerishable > Canned"
            and canned_hierarchy.get("subcategory") == "NonPerishable"
            and canned_hierarchy.get("leaf") == "Canned"
            and (canned_detection.get("classifier") or {}).get("signature") == "Food"
            and (canned_detection.get("final") or {}).get("primary") == "FoodNonPerishableCanned"
            and canned.get("evaluator", {}).get("api") == "DynamicTrading.GetPriceDetails"
        ),
        f"path={canned.get('categoryPath', '?')}, detector={(canned_detection.get('classifier') or {}).get('signature', '?')}",
    )
    check(
        "runtime variables and price audit",
        (
            canned.get("context", {}).get("calories") == 250
            and canned.get("context", {}).get("hunger") == 0.2
            and isinstance(canned.get("priceAudit"), list)
            and any(entry.get("label") == "raw score" for entry in canned.get("priceAudit") or [])
        ),
        f"calories={canned.get('context', {}).get('calories', '?')}, audit_steps={len(canned.get('priceAudit') or [])}",
    )
    check(
        "numeric method bridge",
        (
            abs(float(low.get("hunger", 0)) - 0.05) < 1e-9
            and abs(float(by_type.get("MarketSenseFixture.Axe", {}).get("maxDamage", 0)) - 2) < 1e-9
            and abs(float(by_type.get("MarketSenseFixture.Bag", {}).get("capacity", 0)) - 20) < 1e-9
        ),
        "hunger, weapon damage, and container capacity",
    )
    overridden = run_lua_result(
        lua, mock_definitions(), {"PriceGlobalValue": 100}
    )
    overridden_by_type = {row.get("fullType"): row for row in overridden.rows}
    check(
        "sandbox override reaches Lua pricing",
        (
            overridden.metadata.get("requested", {}).get("PriceGlobalValue") == 100
            and overridden.metadata.get("runtime", {}).get("pricing", {}).get("globalValue") == 100
            and overridden_by_type.get("MarketSenseFixture.CannedMeal", {}).get("price", 0)
            == canned.get("price", 0) + 100
        ),
        f"base={canned.get('price', '?')} overridden="
        f"{overridden_by_type.get('MarketSenseFixture.CannedMeal', {}).get('price', '?')}",
    )
    return all(check["passed"] for check in checks), checks


def print_self_test(checks: list[dict[str, Any]]) -> None:
    print("MarketSense offline harness self-test")
    for check in checks:
        status = "PASS" if check["passed"] else "FAIL"
        print(f"  {status:<4} {check['name']}: {check['detail']}")
    passed = sum(1 for check in checks if check["passed"])
    print(f"Result: {'PASS' if passed == len(checks) else 'FAIL'} ({passed}/{len(checks)} checks)")
