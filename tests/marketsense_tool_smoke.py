#!/usr/bin/env python3
"""Focused smoke tests for the packaged offline MarketSense application."""

from __future__ import annotations

import json
import sys
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools" / "src"))

from marketsense_app.cache import ResultCache, cache_key, clear_cache
from marketsense_app.availability import (
    availability_counts,
    build_acquisition_index,
)
from marketsense_app.evaluation import ScanOptions, load_cached_result, merge_scan_definitions
from marketsense_app.heuristics import heuristic_coverage, heuristic_gap
from marketsense_app.gui_filters import filter_rows, view_summary
from marketsense_app.gui_items import ItemsMixin, category_metadata, metadata_label
from marketsense_app.gui_overview import OverviewMixin
from marketsense_app.lua_rules import (
    load_rules,
    remove_all_item_rules,
    remove_item_override,
    save_rules,
    set_item_override,
    set_membership_rule,
)
from marketsense_app.liquid_pricing import (
    LiquidPricingCatalog,
    load_liquid_catalog,
    render_liquid_overrides,
    save_liquid_overrides,
)
from marketsense_app.models import ItemDefinition, WorkshopMod
from marketsense_app.review import review_count, review_row, searchable_text
from marketsense_app.scan_scope import (
    candidate_definitions,
    normalize_category_filter,
)
from marketsense_app.runtime_comparison import compare_harness_to_runtime
from marketsense_app.reporting import write_heuristic_gap_report, write_low_confidence_report
from marketsense_app.recipe_parser import discover_yield_recipes
from marketsense_app.preferences import load_preferences, normalize_preferences, save_preferences
from marketsense_app.script_parser import parse_script
from marketsense_app.sandbox import (
    effective_sandbox_settings,
    load_sandbox_option_specs,
    load_sandbox_settings,
    recommended_sandbox_settings,
    sandbox_definition_audit,
    save_sandbox_settings,
)
from marketsense_app.workshop import discover_items, discover_mods, merge_definitions
from marketsense_app.workshop_paths import item_script_paths, pz_version_int
from marketsense_app.tile_parser import build_tile_property_index, parse_tile_definitions


def main() -> int:
    assert pz_version_int("42.20") == 42020
    assert pz_version_int("42") == 42000
    assert pz_version_int("42.1200") == 42999
    assert pz_version_int("not-a-version") == 0

    scope_mod = WorkshopMod(Path("scope-fixture"), "scope", "Scope", "Scope", "fixture")
    scope_food = ItemDefinition(
        "Base.ScopeFood", "Base", {"displayCategory": "Cooking"}, scope_mod, "food.txt"
    )
    scope_weapon = ItemDefinition(
        "Base.ScopeWeapon", "Base", {"displayCategory": "Weapon"}, scope_mod, "weapon.txt"
    )
    assert normalize_category_filter("all categories") == ""
    assert [item.full_type for item in candidate_definitions(
        [scope_food, scope_weapon], "Food"
    )] == ["Base.ScopeFood"]
    assert len(candidate_definitions([scope_food, scope_weapon], "Weapon")) == 2
    assert len(candidate_definitions([scope_food, scope_weapon], "unknown")) == 2

    liquid_catalog = LiquidPricingCatalog(
        {
            "defaultPricePerLiter": 5.0,
            "liquids": {
                "Water": {"pricePerLiter": 5.0, "primary": "LiquidWater"},
            },
            "primaryDefaults": {"LiquidWater": 5.0},
        },
        {},
        Path("base.lua"),
        Path("overrides.lua"),
    )
    water = next(row for row in liquid_catalog.rows() if row.key == "Water")
    liquid_catalog.set_price(water, 7.5)
    assert water.price_per_liter == 7.5 and water.source == "override"
    rendered_liquids = render_liquid_overrides(liquid_catalog.override_payload())
    assert '["Water"]' in rendered_liquids and '"pricePerLiter"] = 7.5' in rendered_liquids
    liquid_catalog.clear_price(water)
    assert water.price_per_liter == 5.0 and not water.overridden

    with TemporaryDirectory(prefix="marketsense-liquid-smoke-") as liquid_temp:
        liquid_root = Path(liquid_temp)
        liquid_base = liquid_root / "base.lua"
        liquid_override = liquid_root / "overrides.lua"
        liquid_base.write_text(
            "return { defaultPricePerLiter = 5, "
            "liquids = { Water = { pricePerLiter = 5, primary = 'LiquidWater' } }, "
            "primaryDefaults = { LiquidWater = 5 } }\n",
            encoding="utf-8",
        )
        round_trip = load_liquid_catalog(
            "lua", liquid_base, liquid_override
        )
        round_trip_water = next(
            row for row in round_trip.rows() if row.key == "Water"
        )
        round_trip.set_price(round_trip_water, 8.25)
        save_liquid_overrides(round_trip, liquid_override)
        loaded_override = load_liquid_catalog(
            "lua", liquid_base, liquid_override
        )
        loaded_water = next(
            row for row in loaded_override.rows() if row.key == "Water"
        )
        assert loaded_water.price_per_liter == 8.25
        assert loaded_water.source == "override"

    with TemporaryDirectory(prefix="marketsense-tool-smoke-") as temp_dir:
        root = Path(temp_dir)
        direct = root / "direct" / "media" / "scripts"
        direct.mkdir(parents=True)
        (direct / "items.txt").write_text("module Test { item One { Type = Normal, } }", encoding="utf-8")
        paths, selected = item_script_paths(root / "direct", "42.20")
        assert selected == "direct" and len(paths) == 1

        versioned = root / "versioned"
        for version in ("42.15", "42.20", "42.21"):
            scripts = versioned / version / "media" / "scripts"
            scripts.mkdir(parents=True)
            (scripts / "items.txt").write_text(
                f"module Test {{ item {version.replace('.', '_')} {{ Type = Normal, }} }}",
                encoding="utf-8",
            )
        paths, selected = item_script_paths(versioned, "42.20")
        assert selected == "42.20" and len(paths) == 1

        first = versioned / "common" / "media" / "scripts"
        first.mkdir(parents=True)
        (first / "common.txt").write_text("module Test { item Common { Type = Normal, } }", encoding="utf-8")
        paths, selected = item_script_paths(versioned, "42.20")
        assert selected == "common+42.20" and len(paths) == 2

        parser_root = root / "parser" / "media" / "scripts"
        parser_root.mkdir(parents=True)
        parser_script = parser_root / "weapons.txt"
        parser_script.write_text(
            """module Base {
    item SpearCrafted {
        Type = Weapon,
        Categories = base:improvised;base:spear,
        SubCategory = Spear,
    }
}
""",
            encoding="utf-8",
        )
        parser_mod = WorkshopMod(parser_root.parent.parent, "base", "Base", "Base", "base")
        parsed_weapon = parse_script(parser_script, parser_mod)
        assert parsed_weapon[0].props["weaponCategories"] == "base:improvised;base:spear"

        workshop = root / "workshop"
        narcotics = workshop / "123" / "mods" / "Narcotics"
        other = workshop / "456" / "mods" / "Other"
        for mod_root, mod_id in ((narcotics, "Narcotics"), (other, "Other")):
            scripts = mod_root / "media" / "scripts"
            scripts.mkdir(parents=True)
            (mod_root / "mod.info").write_text(
                f"id={mod_id}\nname={mod_id} Test\n", encoding="utf-8"
            )
            (scripts / "items.txt").write_text(
                f"module {mod_id} {{ item Sample {{ Type = Normal, }} }}",
                encoding="utf-8",
            )
        discovered_mods = discover_mods((workshop,))
        assert {mod.mod_id for mod in discovered_mods} == {"Narcotics", "Other"}
        all_mods, all_items, _all_files, _all_definitions = discover_items(
            (workshop,), [], "42.20"
        )
        selected_mods, selected_items, _selected_files, _selected_definitions = discover_items(
            (workshop,), ["Narcotics"], "42.20"
        )
        assert len(all_mods) == 2 and len(all_items) == 2
        assert [mod.mod_id for mod in selected_mods] == ["Narcotics"]
        assert set(selected_items) == {"Narcotics.Sample"}

        tile_file = root / "tile-mod" / "media" / "newtiledefinitions.tiles.txt"
        tile_file.parent.mkdir(parents=True)
        tile_file.write_text(
            """version = 1
tileset {
    file = test
    // test_0
    tile {
        CustomName = Light Round Table
        GenericCraftingSurface = true
        IsTable =
        Surface = 27
    }
}
""",
            encoding="utf-8",
        )
        parsed_tiles = parse_tile_definitions(tile_file)
        assert parsed_tiles["test_0"] == {
            "CustomName": "Light Round Table",
            "GenericCraftingSurface": True,
            "IsTable": True,
            "Surface": 27,
        }
        indexed_tiles, tile_sources = build_tile_property_index(
            None, (tile_file.parents[1],), "42.20"
        )
        assert indexed_tiles["test_0"]["IsTable"] is True and tile_sources

        media = root / "availability" / "media"
        scripts_root = media / "scripts"
        (media / "lua" / "server" / "Items").mkdir(parents=True)
        (media / "lua" / "shared" / "Foraging" / "Categories").mkdir(parents=True)
        (scripts_root / "generated" / "recipes").mkdir(parents=True)
        (media / "lua" / "server" / "Items" / "ProceduralDistributions.lua").write_text(
            'items = { "Looted", "9mmClip", 10, }', encoding="utf-8"
        )
        (media / "lua" / "shared" / "Foraging" / "Categories" / "Fruit.lua").write_text(
            'type = "Base.Foraged",', encoding="utf-8"
        )
        (media / "lua" / "server" / "Traps").mkdir(parents=True)
        (media / "lua" / "server" / "Traps" / "TrapDefinition.lua").write_text(
            'rabbit.item = "Base.Trapped",', encoding="utf-8"
        )
        (scripts_root / "generated" / "recipes" / "recipes.txt").write_text(
            """module Base { craftRecipe MakeCrafted { outputs { item 1 Base.Crafted, } } }""",
            encoding="utf-8",
        )
        (scripts_root / "generated" / "recipes" / "yield.txt").write_text(
            """module Base {
    craftRecipe OpenEggCarton {
        inputs { item 1 Base.EggCarton flags[InheritFoodAge], }
        outputs { item 12 Base.Egg, }
    }
    craftRecipe OpenChanceBox {
        inputs { item 1 Base.ChanceBox, }
        outputs { item 1 Base.Egg chance:0.5, }
    }
    craftRecipe OpenVariableBox {
        inputs { item 1 Base.VariableBox, }
        outputs { item variable[1:2] Base.Egg, }
    }
}
""",
            encoding="utf-8",
        )
        availability_mod = WorkshopMod(media.parent, "base", "Base", "Base", "base")
        availability_definitions = {
            "Base.Looted": ItemDefinition("Base.Looted", "Base", {}, availability_mod, "looted.txt"),
            "Base.9mmClip": ItemDefinition("Base.9mmClip", "Base", {}, availability_mod, "ammo.txt"),
            "Base.Foraged": ItemDefinition("Base.Foraged", "Base", {}, availability_mod, "foraged.txt"),
            "Base.Trapped": ItemDefinition("Base.Trapped", "Base", {}, availability_mod, "trapped.txt"),
            "Base.Crafted": ItemDefinition("Base.Crafted", "Base", {}, availability_mod, "crafted.txt"),
            "Base.DebugThing": ItemDefinition(
                "Base.DebugThing", "Base", {"displayCategory": "Hidden"}, availability_mod, "debug.txt"
            ),
        }
        yield_definitions = dict(availability_definitions)
        for full_type in (
            "Base.EggCarton", "Base.Egg", "Base.ChanceBox", "Base.VariableBox",
        ):
            yield_definitions[full_type] = ItemDefinition(
                full_type, "Base", {}, availability_mod, "yield.txt"
            )
        yield_index, yield_stats = discover_yield_recipes(
            scripts_root, (), "42.20", yield_definitions
        )
        assert yield_stats["recipeCount"] >= 1
        egg_yield = yield_index["Base.EggCarton"][0]
        assert egg_yield["recipe"] == "OpenEggCarton"
        assert egg_yield["outputs"][0] == {
            "fullType": "Base.Egg", "quantity": 12.0, "chance": 1.0,
            "maxQuantity": 12.0, "outputFlags": [], "inheritFoodAge": True,
            "resolution": "exact",
            "inputFlags": ["InheritFoodAge"],
        }
        assert yield_index["Base.ChanceBox"][0]["resolution"] == "probabilistic"
        assert yield_index["Base.VariableBox"][0]["resolution"] == "unresolved"
        availability_index = build_acquisition_index(
            availability_definitions.values(), scripts_root, (), "42.20"
        )
        availability_records = availability_index.records(availability_definitions.values())
        assert availability_records["Base.Looted"]["status"] == "obtainable"
        assert availability_records["Base.9mmClip"]["status"] == "obtainable"
        assert availability_records["Base.Foraged"]["status"] == "obtainable"
        assert availability_records["Base.Crafted"]["status"] == "obtainable"
        assert availability_records["Base.Trapped"]["status"] == "obtainable"
        assert availability_records["Base.DebugThing"]["status"] == "excluded"
        assert availability_counts(availability_records.values()) == {
            "obtainable": 5, "uncertain": 0, "excluded": 1
        }
        cache_options = SimpleNamespace(
            filters=(), game_version="42.20", game_root=None, no_base_game=False,
            max_items=0, confidence_threshold=0.5, sandbox_options={},
            availability_filter="obtainable",
        )
        key_before = cache_key(
            str(root / "marketsense.lua"), cache_options,
            (media.parent,), scripts_root,
        )
        marker = media / "lua" / "server" / "Items" / "cache-marker.lua"
        marker.write_text('items = { "Looted", 11, }', encoding="utf-8")
        key_after = cache_key(
            str(root / "marketsense.lua"), cache_options,
            (media.parent,), scripts_root,
        )
        assert key_before != key_after
        unscoped_options = ScanOptions(
            workshop_roots=(media.parent,), category_filter="",
        )
        scoped_options = ScanOptions(
            workshop_roots=(media.parent,), category_filter="Food",
        )
        lowercase_scoped_options = ScanOptions(
            workshop_roots=(media.parent,), category_filter="food",
        )
        assert cache_key(
            str(root / "marketsense.lua"), unscoped_options,
            (media.parent,), scripts_root,
        ) != cache_key(
            str(root / "marketsense.lua"), scoped_options,
            (media.parent,), scripts_root,
        )
        assert cache_key(
            str(root / "marketsense.lua"), scoped_options,
            (media.parent,), scripts_root,
        ) == cache_key(
            str(root / "marketsense.lua"), lowercase_scoped_options,
            (media.parent,), scripts_root,
        )
        progress_messages: list[str] = []
        no_root_options = ScanOptions(workshop_roots=(root / "missing",))
        assert load_cached_result(
            "lua", no_root_options, progress_messages.append
        ) is None
        assert progress_messages and "no exact lookup" in progress_messages[0]

    mod = WorkshopMod(Path("fixture"), "fixture", "Fixture", "Fixture", "fixture")
    base = ItemDefinition("Test.One", "Test", {"tags": ["Base"], "capacity": 1}, mod, "base.txt")
    overlay = ItemDefinition("Test.One", "Test", {"tags": ["Overlay"], "capacity": 2}, mod, "overlay.txt")
    merged = merge_definitions(base, overlay)
    assert merged.props == {"tags": ["Base", "Overlay"], "capacity": 2}
    assert merged.sources == ["base.txt", "overlay.txt"]
    vanilla_only = ItemDefinition("Test.Vanilla", "Test", {"capacity": 3}, mod, "vanilla.txt")
    scan_definitions = merge_scan_definitions(
        {base.full_type: base, vanilla_only.full_type: vanilla_only},
        {overlay.full_type: overlay},
    )
    assert set(scan_definitions) == {"Test.One", "Test.Vanilla"}
    assert scan_definitions["Test.One"].props["capacity"] == 2
    assert scan_definitions["Test.Vanilla"].props["capacity"] == 3

    assert review_row({
        "fullType": "Test.Safe", "category": "Food", "primary": "FoodStaple",
        "confidence": 0.9, "expandedTags": ["Food", "FoodStaple"],
    })[0] == "OK"
    flagged = {
        "fullType": "Test.Unknown", "category": "Misc", "primary": "Misc",
        "confidence": 0.2, "source": "root_fallback",
        "expandedTags": ["Misc"], "description": "unknown test item",
    }
    status, reason = review_row(flagged)
    assert status == "REVIEW"
    assert "fallback resolver" in reason and "low confidence" in reason
    assert review_row({
        "category": "Misc", "primary": "Memento", "confidence": 0.9,
        "expandedTags": ["Misc", "Memento"],
    })[0] == "OK"
    assert review_row({
        "category": "Misc", "primary": "Junk", "confidence": 0.9,
        "expandedTags": ["Misc", "Junk"],
    })[0] == "OK"
    assert review_count([flagged, {
        "category": "Tool", "primary": "ToolCraft", "confidence": 0.9,
        "expandedTags": ["Tool", "ToolCraft"],
    }]) == 1
    assert "unknown test item" in searchable_text(flagged)
    assert heuristic_gap({
        "fullType": "Base.Unknown", "category": "Misc", "subcategory": "General",
        "primary": "Misc", "detector": "RootArbiter", "resolver": "root_fallback",
        "confidence": 0.2,
    })["kind"] == "fallback"
    assert heuristic_gap({
        "fullType": "Base.Material", "category": "Resource", "subcategory": "Material",
        "primary": "MaterialButchering", "detector": "RootArbiter",
        "resolver": "root_fallback", "confidence": 0.9,
    }) is None
    assert heuristic_gap({
        "fullType": "Base.Bag", "category": "Container", "subcategory": "General",
        "primary": "Container", "detector": "Container", "resolver": "root_container",
        "confidence": 0.8,
    })["kind"] == "root_only"
    coverage = heuristic_coverage([
        flagged,
        {
            "fullType": "Base.Moveable", "category": "Building",
            "subcategory": "Moveable", "primary": "BuildingMoveable",
            "detector": "Building", "resolver": "root_building", "confidence": 0.78,
        },
    ], example_limit=1)
    assert coverage["candidate_count"] == 2
    assert coverage["examples"] and coverage["examples"][0]["fullType"]
    assert "loot/distribution" in searchable_text({
        "fullType": "Base.CannedLeek",
        "availability": {
            "status": "obtainable",
            "channelLabels": ["loot/distribution"],
        },
    })
    mismatch_status, mismatch_reason = review_row({
        "category": "Food", "primary": "FoodStaple", "confidence": 0.9,
        "expandedTags": ["Tool", "ToolCraft"],
    })
    assert mismatch_status == "REVIEW" and "absent from expanded tags" in mismatch_reason
    assert review_row({"error": "bridge failed"})[0] == "ERROR"
    assert review_row({
        "category": "Food", "primary": "Food", "confidence": 0.9,
        "yieldResolution": {"status": "probabilistic", "recipe": "OpenBox"},
    }) == ("REVIEW", "yield probabilistic (OpenBox)")

    descriptor_row = {
        "expandedTags": [
            "Weapon", "Quality.Standard", "Rarity.Rare",
            "Theme.Combat", "Origin.Vanilla",
        ],
    }
    assert category_metadata(descriptor_row) == {
        "quality": "Standard", "rarity": "Rare",
        "theme": "Combat", "origin": "Vanilla",
    }
    assert "Theme=Combat" in metadata_label(descriptor_row)
    assert ItemsMixin._item_rule_prefix({"membership": "blacklist", "override": {}}) == "(Blacklisted)"
    assert ItemsMixin._item_rule_prefix({"membership": "whitelist", "override": {"price": 10}}) == "(Whitelisted) (Overridden)"
    assert OverviewMixin._availability_filter_matches(
        "changed", "obtainable", {"membership": "blacklist", "override": {}}
    )
    assert OverviewMixin._availability_filter_matches(
        "overridden", "excluded", {"membership": None, "override": {"price": 99}}
    )
    assert not OverviewMixin._availability_filter_matches(
        "whitelisted", "obtainable", {"membership": "blacklist", "override": {}}
    )
    rule_state = {
        "Base.VanillaThing": {"membership": "blacklist", "override": {}},
        "Narcotics.CraftedThing": {"membership": None, "override": {"price": 99}},
    }

    cached_view_rows = [
        {
            "fullType": "Base.VanillaThing", "workshopMod": "Base",
            "availability": {"status": "obtainable"}, "price": 10,
            "category": "Tool", "primary": "ToolCraft", "confidence": 0.9,
        },
        {
            "fullType": "Narcotics.CraftedThing", "workshopMod": "Narcotics",
            "workshopName": "Narcotics Test",
            "availability": {"status": "obtainable"}, "price": 20,
            "category": "Misc", "primary": "Misc", "confidence": 0.7,
        },
        {
            "fullType": "Narcotics.UncertainThing", "workshopMod": "Narcotics",
            "workshopName": "Narcotics Test",
            "availability": {"status": "uncertain"}, "price": 30,
            "category": "Misc", "primary": "Misc", "confidence": 0.7,
        },
        {
            "fullType": "Other.ExcludedThing", "workshopMod": "Other",
            "workshopName": "Other Test",
            "availability": {"status": "excluded"}, "price": 40,
            "category": "Misc", "primary": "Misc", "confidence": 0.7,
        },
    ]
    assert len(filter_rows(cached_view_rows, "All items")) == 4
    assert len(filter_rows(cached_view_rows, "Obtainable only")) == 2
    assert len(filter_rows(cached_view_rows, "All items", ("Narcotics",))) == 2
    assert len(filter_rows(cached_view_rows, "Obtainable only", ("Narcotics",))) == 1
    assert len(filter_rows(cached_view_rows, "All items", (), True)) == 3
    assert [row["fullType"] for row in filter_rows(
        cached_view_rows, "Changed only", (), False, 0, rule_state
    )] == ["Base.VanillaThing", "Narcotics.CraftedThing"]
    assert [row["fullType"] for row in filter_rows(
        cached_view_rows, "Blacklisted only", (), False, 0, rule_state
    )] == ["Base.VanillaThing"]
    assert [row["fullType"] for row in filter_rows(
        cached_view_rows, "All items", (), False, 2
    )] == ["Base.VanillaThing", "Narcotics.CraftedThing"]
    master_summary = {
        "confidence_threshold": 0.5,
        "workshop_mods": 2,
        "mods": [],
        "cache": {"status": "hit"},
    }
    narrowed_summary = view_summary(
        master_summary, filter_rows(cached_view_rows, "Uncertain only"),
        cached_view_rows, "Uncertain only",
    )
    assert narrowed_summary["evaluated"] == 1
    assert narrowed_summary["prices"]["median"] == 30
    assert narrowed_summary["view_filtered_out"] == 3

    specs = load_sandbox_option_specs()
    assert len(specs) >= 3
    assert next(spec for spec in specs if spec.key == "PriceMultiplier").default == 1.0
    assert not any(spec.key.startswith("PriceLiterature") for spec in specs)
    assert not any(spec.key == "PriceWeaponValue" for spec in specs)
    assert not any(spec.key == "PriceWeaponExplosiveValue" for spec in specs)
    assert not any(spec.key.startswith("PriceClothing") for spec in specs)
    assert next(spec for spec in specs if spec.key == "StockWeaponSpearMult").default == 1.0
    recommendations = recommended_sandbox_settings(specs)
    assert not any(key.startswith("PriceLiterature") for key in recommendations)
    assert not any(key.startswith("PriceClothing") for key in recommendations)
    assert recommendations["StockWeaponSpearMult"] == 1.0
    sandbox_audit = sandbox_definition_audit()
    assert sandbox_audit["status"] == "warning"
    assert sandbox_audit["recommendationGapCount"] > 0
    assert not any(
        warning["key"].startswith("PriceLiterature")
        for warning in sandbox_audit["warnings"]
    )
    assert not any(
        warning["key"].startswith("PriceClothing")
        for warning in sandbox_audit["warnings"]
    )
    effective = effective_sandbox_settings({"PriceGlobalValue": 123}, specs)
    assert effective["PriceGlobalValue"] == 123
    assert effective["PriceMultiplier"] == 1.0
    assert "PriceWeaponSpearValue" not in effective

    with TemporaryDirectory(prefix="marketsense-result-cache-") as temp_dir:
        cache = ResultCache(Path(temp_dir), "fixture-key")
        assert cache.load() is None
        cache.save({"evaluated": 1}, [{"fullType": "Test.One", "price": 2}])
        assert cache.load() == {
            "summary": {"evaluated": 1},
            "items": [{"fullType": "Test.One", "price": 2}],
        }
        assert clear_cache(Path(temp_dir)) == 1

    with TemporaryDirectory(prefix="marketsense-cache-lookup-") as temp_dir:
        root = Path(temp_dir) / "workshop"
        root.mkdir()
        lua_path = Path(temp_dir) / "lua"
        lua_path.write_text("-- fixture", encoding="utf-8")
        options = ScanOptions(
            workshop_roots=(root,), no_base_game=True,
            cache_dir=Path(temp_dir) / "cache", use_cache=True,
        )
        cache = ResultCache(
            options.cache_dir,
            cache_key(str(lua_path), options, (root,), None),
        )
        cache.save({"evaluated": 1}, [{"fullType": "Test.Cached", "price": 7}])
        cached = load_cached_result(str(lua_path), options)
        assert cached and cached[0]["cache"]["status"] == "hit"
        assert load_cached_result(
            str(lua_path), options.__class__(**{
                **options.__dict__, "refresh_cache": True,
            })
        ) is None

    with TemporaryDirectory(prefix="marketsense-preferences-") as temp_dir:
        settings_path = Path(temp_dir) / "inspector.json"
        saved = save_preferences(settings_path, {
            "workshopRoots": ["/tmp/workshop"], "gameRoot": "/tmp/game",
            "useCache": True, "maxItems": 12,
        })
        assert saved == settings_path.resolve()
        loaded = normalize_preferences(load_preferences(settings_path))
        assert loaded["workshopRoots"] == ["/tmp/workshop"]
        assert loaded["gameRoot"] == "/tmp/game" and loaded["maxItems"] == 12
        assert loaded["itemColumns"] == {"order": [], "visible": []}
        saved = save_preferences(settings_path, {
            "itemColumns": {
                "order": ["stock", "price"],
                "visible": ["stock"],
            },
        })
        loaded = normalize_preferences(load_preferences(settings_path))
        assert loaded["itemColumns"] == {
            "order": ["stock", "price"], "visible": ["stock"]
        }

    with TemporaryDirectory(prefix="marketsense-settings-") as temp_dir:
        settings_path = Path(temp_dir) / "settings.json"
        save_sandbox_settings(settings_path, {"PriceGlobalValue": 123}, specs)
        assert load_sandbox_settings(settings_path, specs) == {"PriceGlobalValue": 123}
        low_path = Path(temp_dir) / "low.jsonl"
        write_low_confidence_report(low_path, [flagged], 0.5)
        assert len(low_path.read_text(encoding="utf-8").splitlines()) == 1
        gap_path = Path(temp_dir) / "gaps.json"
        write_heuristic_gap_report(gap_path, [flagged])
        gap_report = json.loads(gap_path.read_text(encoding="utf-8"))
        assert gap_report["count"] == 1

    with TemporaryDirectory(prefix="marketsense-runtime-rules-") as temp_dir:
        rules_path = Path(temp_dir) / "MS_RuntimeRules_Data.lua"
        rules_path.write_text(
            """return {
                blacklist = { "Base.Blocked" },
                whitelist = { "Base.Allowed" },
                overrides = { { id = "Base.Tool", add = 4 } },
                overridesById = {
                    ["Base.Tool"] = { price = 99, stock = { min = 1, max = 2 } },
                },
            }
            """,
            encoding="utf-8",
        )
        rules = load_rules(rules_path, "lua")
        assert rules["blacklist"] == ["Base.Blocked"]
        assert rules["whitelist"] == ["Base.Allowed"]
        assert rules["overrides"] == [{
            "id": "Base.Tool", "add": 4, "price": 99,
            "stock": {"min": 1, "max": 2},
        }]
        set_membership_rule(rules, "Base.Blocked", "whitelist")
        set_item_override(rules, "Base.Tool", tags=["Tool", "ToolCraft"])
        save_rules(rules, rules_path)
        round_trip = load_rules(rules_path, "lua")
        assert "Base.Blocked" not in round_trip["blacklist"]
        assert "Base.Blocked" in round_trip["whitelist"]
        assert round_trip["overrides"][0]["price"] == 99
        assert round_trip["overrides"][0]["tags"] == ["Tool", "ToolCraft"]
        assert remove_item_override(round_trip, "Base.Tool") is True
        assert remove_all_item_rules(round_trip, "Base.Blocked") is True
        assert "Base.Blocked" not in round_trip["whitelist"]

    with TemporaryDirectory(prefix="marketsense-runtime-compare-") as temp_dir:
        runtime_dir = Path(temp_dir) / "MS_Items" / "Weapon" / "Ranged"
        runtime_dir.mkdir(parents=True)
        runtime_file = runtime_dir / "Ammo.txt"
        runtime_file.write_text(
            """# schema=MS_ITEMS_V1
# root=Weapon
# category=Weapon
# subcategory=Ranged
# leaf=Ammo
# primaryPrefix=Weapon.Ranged.Ammo
@origin=Vanilla
@tags=Ammo|Quality.Standard
Base.Shell|12|2|10
""",
            encoding="utf-8",
        )
        harness_rows = [{
            "fullType": "Base.Shell",
            "availability": {"status": "obtainable"},
            "tags": ["Ammo", "Quality.Standard"],
            "primary": "Ammo",
            "category": "Weapon",
            "subcategory": "Ranged",
            "leaf": "Ammo",
            "primaryPrefix": "Weapon.Ranged.Ammo",
            "basePrice": 12,
            "baseStock": {"min": 2, "max": 10},
        }]
        comparison = compare_harness_to_runtime(harness_rows, Path(temp_dir) / "MS_Items")
        assert comparison["status"] == "match"
        assert comparison["matches"] == 1 and not comparison["differences"]

        (Path(temp_dir) / "MS_Items" / "MS_ItemsIndex.txt").write_text(
            'return { files = { { path = "Weapon/Ranged/Ammo.txt" } } }\n',
            encoding="utf-8",
        )
        comparison = compare_harness_to_runtime(harness_rows, Path(temp_dir) / "MS_Items")
        assert comparison["status"] == "match"
        assert comparison["runtime"]["index"]["indexedFileCount"] == 1

        stale_file = Path(temp_dir) / "MS_Items" / "Weapon" / "Stale.txt"
        stale_file.write_text(
            "# schema=MS_ITEMS_V1\n"
            "@origin=Vanilla\n"
            "@tags=Stale\n"
            "Base.Stale|1|1|1\n",
            encoding="utf-8",
        )
        comparison = compare_harness_to_runtime(harness_rows, Path(temp_dir) / "MS_Items")
        assert comparison["status"] == "mismatch"
        assert comparison["fieldMismatches"] == {"index": 1}
        stale_file.unlink()

        runtime_file.write_text(
            runtime_file.read_text(encoding="utf-8").replace(
                "Base.Shell|12|2|10", "Base.Shell|13|2|10"
            ),
            encoding="utf-8",
        )
        comparison = compare_harness_to_runtime(harness_rows, Path(temp_dir) / "MS_Items")
        assert comparison["status"] == "mismatch"
        assert comparison["fieldMismatches"] == {"basePrice": 1}

    print("marketsense_tool_smoke: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
