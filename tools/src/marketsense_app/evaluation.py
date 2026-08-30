"""Shared scan pipeline used by both the console and desktop GUI."""

from __future__ import annotations

from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

from .bridge import run_lua_result
from .cache import ResultCache, cache_key
from .config import DEFAULT_GAME_VERSION
from .availability import (
    availability_matches,
    build_acquisition_index,
    normalize_availability_filter,
)
from .models import ItemDefinition
from .heuristics import heuristic_coverage
from .reporting import build_summary
from .recipe_parser import discover_tool_recipe_usage, discover_yield_recipes
from .review import low_confidence_rows, review_row
from .scan_scope import (
    candidate_definitions,
    normalize_category_filter,
    row_matches_category,
)
from .sandbox import (
    effective_sandbox_settings,
    load_sandbox_option_specs,
    sandbox_definition_audit,
)
from .tile_parser import build_tile_property_index
from .workshop import discover_base_items, discover_items, merge_definitions
from .workshop_paths import game_scripts_root


@dataclass(frozen=True)
class ScanOptions:
    workshop_roots: tuple[Path, ...]
    filters: tuple[str, ...] = ()
    game_version: str = DEFAULT_GAME_VERSION
    game_root: Path | None = None
    no_base_game: bool = False
    max_items: int = 0
    cache_dir: Path | None = None
    use_cache: bool = True
    refresh_cache: bool = False
    confidence_threshold: float = 0.5
    sandbox_options: dict[str, int | float] = field(default_factory=dict)
    availability_filter: str = "obtainable"
    category_filter: str = ""


ProgressCallback = Callable[[str], None]


def _progress(callback: ProgressCallback | None, message: str) -> None:
    """Report a bounded phase message without making logging part of the scan."""

    if callback is None:
        return
    try:
        callback(message)
    except Exception:
        # A diagnostic sink must never change evaluator behavior.  This also
        # protects console/CLI callers that do not need progress reporting.
        pass


def merge_scan_definitions(
    base_definitions: dict[str, ItemDefinition],
    workshop_definitions: dict[str, ItemDefinition],
) -> dict[str, ItemDefinition]:
    """Return the full item universe with Workshop patches over vanilla rows."""
    merged: dict[str, ItemDefinition] = {}
    for full_type in sorted(set(base_definitions) | set(workshop_definitions)):
        overlay = workshop_definitions.get(full_type)
        if overlay is None:
            merged[full_type] = base_definitions[full_type]
        else:
            merged[full_type] = merge_definitions(
                base_definitions.get(full_type), overlay
            )
    return merged


def emulate_pz_acquisition_flags(
    definitions: list[ItemDefinition],
    static_records: dict[str, dict],
    sprite_properties: dict[str, dict] | None = None,
) -> list[ItemDefinition]:
    """Project source evidence onto the PZ engine flags used by Lua.

    The real game sets these flags while loading distributions, recipes, and
    foraging data.  The offline bridge has no Java engine, so it supplies a
    PZ-shaped snapshot for the Lua mod to consume.  It intentionally maps
    positive evidence only; exclusions remain an independent comparison so a
    Lua false positive is still visible in the report.
    """
    projected: list[ItemDefinition] = []
    sprite_properties = sprite_properties or {}
    for definition in definitions:
        props = dict(definition.props)
        record = static_records.get(definition.full_type) or {}
        channels = set(record.get("channels") or [])
        if channels & {"loot", "farming", "fishing", "trapping", "animal", "scripted"}:
            props["canSpawnAsLoot"] = True
        if channels & {"craft", "evolved_recipe"}:
            props["isCraftRecipeProduct"] = True
        if "forage" in channels:
            props["canBeForaged"] = True
        sprite_name = str(props.get("worldObjectSprite") or "")
        if sprite_name and sprite_name in sprite_properties:
            # This is the offline equivalent of getSprite(name):
            # getProperties().  Keep the data under its own key so script
            # properties and tile properties cannot accidentally overwrite
            # one another.
            props["spriteProperties"] = dict(sprite_properties[sprite_name])
        projected.append(ItemDefinition(
            full_type=definition.full_type,
            module=definition.module,
            props=props,
            mod=definition.mod,
            script_path=definition.script_path,
            sources=list(definition.sources),
        ))
    return projected


def _cache_for_options(
    lua: str, options: ScanOptions, roots: list[Path], scripts_root: Path | None,
) -> ResultCache | None:
    if not options.use_cache:
        return None
    return ResultCache(
        options.cache_dir,
        cache_key(lua, options, roots, scripts_root),
    )


def _load_cached_result(cache: ResultCache) -> tuple[dict, list[dict]] | None:
    cached = cache.load()
    if not cached or not isinstance(cached.get("summary"), dict):
        return None
    items = cached.get("items")
    if not isinstance(items, list) or not all(isinstance(row, dict) for row in items):
        return None
    summary = dict(cached["summary"])
    # Current cache entries already contain these presentation aggregates.
    # Recomputing them over thousands of verbose rows made GUI startup do a
    # second full pass after JSON deserialization. Keep a compatibility path
    # for older entries that predate one of the aggregate fields.
    if (
        "review_statuses" not in summary
        or "review_count" not in summary
        or "low_confidence_count" not in summary
        or "heuristic_coverage" not in summary
    ):
        valid = [
            row for row in items
            if not row.get("error") and isinstance(row.get("price"), (int, float))
        ]
        threshold = float(summary.get("confidence_threshold", 0.5) or 0.5)
        statuses = Counter(review_row(row)[0] for row in items)
        summary["review_statuses"] = dict(statuses)
        summary["review_count"] = sum(
            count for status, count in statuses.items() if status != "OK"
        )
        summary["low_confidence_count"] = len(low_confidence_rows(items, threshold))
        summary["heuristic_coverage"] = heuristic_coverage(valid)
    summary["cache"] = {"status": "hit", "path": str(cache.path)}
    return summary, items


def load_cached_result(
    lua: str, options: ScanOptions, progress: ProgressCallback | None = None,
) -> tuple[dict, list[dict]] | None:
    """Load an exact cache match without scanning Workshop or invoking Lua.

    This is used by the GUI at startup.  A cache miss deliberately returns
    ``None`` rather than falling through to ``evaluate``; the user must click
    Scan Workshop to create a new result.
    """

    roots = [root.expanduser().resolve() for root in options.workshop_roots if root.is_dir()]
    if not roots or options.refresh_cache:
        _progress(progress, "cache: no exact lookup (missing roots or refresh requested)")
        return None
    _progress(progress, "cache: checking exact master-scan key")
    scripts_root = None if options.no_base_game else game_scripts_root(options.game_root)
    result_cache = _cache_for_options(lua, options, roots, scripts_root)
    cached = _load_cached_result(result_cache) if result_cache else None
    if cached:
        _progress(progress, f"cache: hit ({len(cached[1]):,} master rows)")
    else:
        _progress(progress, "cache: miss")
    return cached


def evaluate(
    lua: str,
    options: ScanOptions,
    progress: ProgressCallback | None = None,
) -> tuple[dict, list[dict]]:
    _progress(progress, "scan: validating Workshop roots")
    roots = [root.expanduser().resolve() for root in options.workshop_roots if root.is_dir()]
    if not roots:
        raise RuntimeError("No Workshop roots found. Use --workshop-root PATH.")

    scripts_root = None if options.no_base_game else game_scripts_root(options.game_root)
    _progress(progress, "cache: checking exact master-scan key")
    result_cache = _cache_for_options(lua, options, roots, scripts_root)
    if result_cache and not options.refresh_cache:
        cached_result = _load_cached_result(result_cache)
        if cached_result:
            _progress(progress, f"cache: hit ({len(cached_result[1]):,} master rows)")
            return cached_result
    _progress(progress, "cache: miss; evaluating source and Lua")

    _progress(progress, "workshop: discovering mod metadata and item scripts")
    mods, definitions_by_type, source_files, definition_count = discover_items(
        roots, list(options.filters), options.game_version
    )
    _progress(progress, (
        f"workshop: found {len(mods):,} mods, {len(definitions_by_type):,} unique "
        f"definitions across {source_files:,} script files"
    ))
    _progress(progress, "base: discovering installed vanilla item scripts")
    base_definitions, base_source_files, base_definition_count = discover_base_items(scripts_root)
    _progress(progress, (
        f"base: found {len(base_definitions):,} definitions across "
        f"{base_source_files:,} script files"
    ))
    merged_definitions = merge_scan_definitions(base_definitions, definitions_by_type)
    all_ordered = [merged_definitions[key] for key in sorted(merged_definitions)]
    category_filter = normalize_category_filter(options.category_filter)
    scoped_ordered = candidate_definitions(all_ordered, category_filter)
    _progress(progress, f"universe: merged {len(all_ordered):,} item definitions")
    if category_filter:
        _progress(progress, (
            f"scope: {category_filter} candidates {len(scoped_ordered):,} / "
            f"{len(all_ordered):,} definitions"
        ))
    _progress(progress, "availability: building acquisition evidence index")
    availability_index = build_acquisition_index(
        scoped_ordered,
        scripts_root,
        (mod.root for mod in mods),
        options.game_version,
    )
    availability_records = availability_index.records(scoped_ordered)
    _progress(progress, (
        f"availability: indexed {len(availability_records):,} rows from "
        f"{availability_index.scanned_files:,} source files"
    ))
    selected_filter = normalize_availability_filter(options.availability_filter)
    # The Lua mod is authoritative for market eligibility and final category.
    # Source hints only reduce the candidate universe; an exact category check
    # below prevents a broad hint from leaking another root into the result.
    ordered = scoped_ordered
    duplicate_count = max(0, definition_count - len(definitions_by_type))
    sandbox_specs = load_sandbox_option_specs(options.game_version)
    effective_sandbox = effective_sandbox_settings(options.sandbox_options, sandbox_specs)
    tile_properties, tile_source_files = build_tile_property_index(
        scripts_root,
        (mod.root for mod in mods),
        options.game_version,
    )
    yield_recipes, yield_stats = discover_yield_recipes(
        scripts_root,
        (mod.root for mod in mods),
        options.game_version,
        merged_definitions,
    )
    _progress(progress, (
        f"recipes: indexed {yield_stats['recipeCount']:,} craft recipes and "
        f"{yield_stats['sourceCount']:,} single-input yield sources"
    ))
    tool_recipe_usage, tool_recipe_stats = discover_tool_recipe_usage(
        scripts_root,
        (mod.root for mod in mods),
        options.game_version,
        merged_definitions,
    )
    _progress(progress, (
        f"tool demand: indexed {tool_recipe_stats['reusableInputCount']:,} reusable "
        f"recipe inputs across {len(tool_recipe_usage):,} items"
    ))
    bridge_definitions = emulate_pz_acquisition_flags(
        all_ordered, availability_records, tile_properties
    )
    _progress(progress, f"lua: evaluating {len(bridge_definitions):,} definitions")
    bridge_result = run_lua_result(
        lua,
        bridge_definitions,
        effective_sandbox,
        yield_recipes=yield_recipes,
        tool_recipe_usage=tool_recipe_usage,
        emitted_types={definition.full_type for definition in ordered},
    )
    _progress(progress, f"lua: returned {len(bridge_result.rows):,} rows")
    all_rows: list[dict] = []
    lua_availability_records: dict[str, dict] = {}
    availability_mismatches: list[dict] = []
    for row in bridge_result.rows:
        enriched = dict(row)
        static_availability = availability_records.get(
            str(row.get("fullType") or ""),
            {
                "status": "uncertain",
                "confidence": 0.0,
                "channels": [],
                "channelLabels": [],
                "references": [],
                "evidence": {},
                "exclusions": [],
                "reason": "no matching item definition was found in the availability index",
            },
        )
        runtime_availability = row.get("availability")
        if not isinstance(runtime_availability, dict):
            runtime_availability = {
                "status": "uncertain",
                "confidence": 0.0,
                "channels": [],
                "channelLabels": [],
                "references": [],
                "exclusions": [],
                "reason": "Lua availability API returned no record",
            }
        enriched["availability"] = runtime_availability
        enriched["harnessAvailability"] = static_availability
        runtime_status = str(runtime_availability.get("status") or "uncertain")
        static_status = str(static_availability.get("status") or "uncertain")
        verification = "match" if runtime_status == static_status else "mismatch"
        enriched["availabilityVerification"] = {
            "status": verification,
            "runtime": runtime_status,
            "staticAudit": static_status,
        }
        full_type = str(row.get("fullType") or "")
        lua_availability_records[full_type] = runtime_availability
        if verification == "mismatch":
            availability_mismatches.append({
                "fullType": full_type,
                "runtime": runtime_status,
                "staticAudit": static_status,
                "runtimeReason": runtime_availability.get("reason", ""),
                "staticReason": static_availability.get("reason", ""),
            })
        all_rows.append(enriched)
    category_rows = [
        row for row in all_rows
        if row_matches_category(row, category_filter)
    ]
    category_omitted = max(0, len(all_rows) - len(category_rows))
    runtime_eligible = [
        row for row in category_rows
        if availability_matches(row.get("availability") or {}, selected_filter)
    ]
    rows = runtime_eligible
    _progress(progress, (
        f"availability: {len(runtime_eligible):,} eligible / {len(all_rows):,} "
        f"runtime rows for scan-time filter {selected_filter}"
    ))
    max_items_omitted = 0
    if options.max_items > 0:
        rows = rows[:options.max_items]
        max_items_omitted = max(0, len(runtime_eligible) - len(rows))
    summary = build_summary(
        rows,
        mods,
        definition_count,
        source_files,
        duplicate_count,
        base_definition_count,
        base_source_files,
        scripts_root,
        options.game_version,
        options.confidence_threshold,
        availability_records=lua_availability_records,
        runtime_evaluated=len(all_rows),
        availability_filter=selected_filter,
        availability_candidates=len(category_rows),
        availability_eligible=len(runtime_eligible),
        max_items_omitted=max_items_omitted,
        availability_source_files=availability_index.scanned_files,
        availability_source_roots=availability_index.source_roots,
        tile_definition_files=len(tile_source_files),
        tile_sprite_properties=len(tile_properties),
    )
    summary["category_filter"] = category_filter or "all"
    summary["category_scope"] = {
        "requested": category_filter or "all",
        "discovered_definitions": len(all_ordered),
        "candidate_definitions": len(scoped_ordered),
        "pruned_definitions": max(0, len(all_ordered) - len(scoped_ordered)),
        "evaluated_candidates": len(all_rows),
        "excluded_by_exact_category": category_omitted,
    }
    summary["yield_recipe_graph"] = dict(yield_stats)
    summary["tool_recipe_demand_graph"] = dict(tool_recipe_stats)
    summary["availability_verification"] = {
        "authority": "MarketSense.ItemAvailability (Lua runtime)",
        "static_audit": "offline source scan (comparison only)",
        "checked": len(all_rows),
        "matches": len(all_rows) - len(availability_mismatches),
        "mismatch_count": len(availability_mismatches),
        "mismatches": availability_mismatches[:100],
    }
    summary["world_object_evidence"] = {
        "tile_definition_files": tile_source_files,
        "tile_sprite_properties": len(tile_properties),
        "bridge": "PZ getSprite(name):getProperties() shape",
    }
    summary["static_availability_counts"] = {
        status: sum(
            1 for record in availability_records.values()
            if str(record.get("status") or "uncertain") == status
        )
        for status in ("obtainable", "uncertain", "excluded")
    }
    summary["sandbox"] = bridge_result.metadata or {
        "requested": dict(effective_sandbox),
    }
    summary["sandbox"].setdefault("requested", dict(effective_sandbox))
    summary["sandbox"]["overrides"] = dict(options.sandbox_options)
    sandbox_audit = sandbox_definition_audit(options.game_version)
    # Keep cached summaries and terminal output bounded.  The GUI performs a
    # fresh full audit on demand, while the scan result carries enough context
    # to warn without serializing every missing taxonomy option.
    summary["sandbox"]["definitionAudit"] = {
        key: sandbox_audit.get(key)
        for key in (
            "status", "declaredCount", "recommendedCount",
            "recommendationGapCount", "generatedOptionCount",
            "staleGeneratedCount",
        )
    }
    summary["sandbox"]["definitionAudit"]["warnings"] = (
        sandbox_audit.get("warnings") or []
    )[:24]
    cache_status = "disabled"
    if result_cache is not None:
        cache_status = "miss" if not options.refresh_cache else "refreshed"
        try:
            _progress(progress, f"cache: saving {len(rows):,} master rows")
            result_cache.save(summary, rows)
            _progress(progress, "cache: save complete")
        except OSError:
            cache_status = "unavailable"
            _progress(progress, "cache: save failed (continuing with in-memory result)")
        summary["cache"] = {"status": cache_status, "path": str(result_cache.path)}
    _progress(progress, "scan: evaluation complete")
    return summary, rows
