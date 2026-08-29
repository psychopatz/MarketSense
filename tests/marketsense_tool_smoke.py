#!/usr/bin/env python3
"""Focused smoke tests for the packaged offline MarketSense application."""

from __future__ import annotations

import sys
from pathlib import Path
from tempfile import TemporaryDirectory


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools" / "src"))

from marketsense_app.cache import ResultCache, clear_cache
from marketsense_app.evaluation import merge_scan_definitions
from marketsense_app.models import ItemDefinition, WorkshopMod
from marketsense_app.review import review_count, review_row, searchable_text
from marketsense_app.reporting import write_low_confidence_report
from marketsense_app.sandbox import (
    effective_sandbox_settings,
    load_sandbox_option_specs,
    load_sandbox_settings,
    save_sandbox_settings,
)
from marketsense_app.workshop import merge_definitions
from marketsense_app.workshop_paths import item_script_paths, pz_version_int


def main() -> int:
    assert pz_version_int("42.20") == 42020
    assert pz_version_int("42") == 42000
    assert pz_version_int("42.1200") == 42999
    assert pz_version_int("not-a-version") == 0

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
    assert review_count([flagged, {
        "category": "Tool", "primary": "ToolCraft", "confidence": 0.9,
        "expandedTags": ["Tool", "ToolCraft"],
    }]) == 1
    assert "unknown test item" in searchable_text(flagged)
    mismatch_status, mismatch_reason = review_row({
        "category": "Food", "primary": "FoodStaple", "confidence": 0.9,
        "expandedTags": ["Tool", "ToolCraft"],
    })
    assert mismatch_status == "REVIEW" and "absent from expanded tags" in mismatch_reason
    assert review_row({"error": "bridge failed"})[0] == "ERROR"

    specs = load_sandbox_option_specs()
    assert len(specs) >= 3
    assert next(spec for spec in specs if spec.key == "PriceMultiplier").default == 1.0
    effective = effective_sandbox_settings({"PriceGlobalValue": 123}, specs)
    assert effective["PriceGlobalValue"] == 123
    assert effective["PriceMultiplier"] == 1.0

    with TemporaryDirectory(prefix="marketsense-result-cache-") as temp_dir:
        cache = ResultCache(Path(temp_dir), "fixture-key")
        assert cache.load() is None
        cache.save({"evaluated": 1}, [{"fullType": "Test.One", "price": 2}])
        assert cache.load() == {
            "summary": {"evaluated": 1},
            "items": [{"fullType": "Test.One", "price": 2}],
        }
        assert clear_cache(Path(temp_dir)) == 1

    with TemporaryDirectory(prefix="marketsense-settings-") as temp_dir:
        settings_path = Path(temp_dir) / "settings.json"
        save_sandbox_settings(settings_path, {"PriceGlobalValue": 123}, specs)
        assert load_sandbox_settings(settings_path, specs) == {"PriceGlobalValue": 123}
        low_path = Path(temp_dir) / "low.jsonl"
        write_low_confidence_report(low_path, [flagged], 0.5)
        assert len(low_path.read_text(encoding="utf-8").splitlines()) == 1

    print("marketsense_tool_smoke: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
