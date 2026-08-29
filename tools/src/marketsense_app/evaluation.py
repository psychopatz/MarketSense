"""Shared scan pipeline used by both the console and desktop GUI."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

from .bridge import run_lua_result
from .cache import ResultCache, cache_key
from .config import DEFAULT_GAME_VERSION
from .availability import (
    availability_matches,
    build_acquisition_index,
    normalize_availability_filter,
)
from .models import ItemDefinition
from .reporting import build_summary
from .sandbox import effective_sandbox_settings, load_sandbox_option_specs
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
) -> list[ItemDefinition]:
    """Project source evidence onto the PZ engine flags used by Lua.

    The real game sets these flags while loading distributions, recipes, and
    foraging data.  The offline bridge has no Java engine, so it supplies a
    PZ-shaped snapshot for the Lua mod to consume.  It intentionally maps
    positive evidence only; exclusions remain an independent comparison so a
    Lua false positive is still visible in the report.
    """
    projected: list[ItemDefinition] = []
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
        projected.append(ItemDefinition(
            full_type=definition.full_type,
            module=definition.module,
            props=props,
            mod=definition.mod,
            script_path=definition.script_path,
            sources=list(definition.sources),
        ))
    return projected


def evaluate(lua: str, options: ScanOptions) -> tuple[dict, list[dict]]:
    roots = [root.expanduser().resolve() for root in options.workshop_roots if root.is_dir()]
    if not roots:
        raise RuntimeError("No Workshop roots found. Use --workshop-root PATH.")

    scripts_root = None if options.no_base_game else game_scripts_root(options.game_root)
    result_cache = None
    if options.use_cache:
        result_cache = ResultCache(
            options.cache_dir,
            cache_key(lua, options, roots, scripts_root),
        )
        if not options.refresh_cache:
            cached = result_cache.load()
            if cached and isinstance(cached.get("summary"), dict) and isinstance(cached.get("items"), list):
                summary = dict(cached["summary"])
                summary["cache"] = {"status": "hit", "path": str(result_cache.path)}
                return summary, cached["items"]

    mods, definitions_by_type, source_files, definition_count = discover_items(
        roots, list(options.filters), options.game_version
    )
    base_definitions, base_source_files, base_definition_count = discover_base_items(scripts_root)
    merged_definitions = merge_scan_definitions(base_definitions, definitions_by_type)
    all_ordered = [merged_definitions[key] for key in sorted(merged_definitions)]
    availability_index = build_acquisition_index(
        all_ordered,
        scripts_root,
        (mod.root for mod in mods),
        options.game_version,
    )
    availability_records = availability_index.records(all_ordered)
    selected_filter = normalize_availability_filter(options.availability_filter)
    # The Lua mod is authoritative for market eligibility.  Evaluate the
    # complete discovered universe first so the harness can compare the live
    # Lua result with this independent source audit and expose mismatches.
    # ``max_items`` is applied after that comparison, not before it.
    ordered = all_ordered
    duplicate_count = max(0, definition_count - len(definitions_by_type))
    sandbox_specs = load_sandbox_option_specs(options.game_version)
    effective_sandbox = effective_sandbox_settings(options.sandbox_options, sandbox_specs)
    bridge_definitions = emulate_pz_acquisition_flags(ordered, availability_records)
    bridge_result = run_lua_result(lua, bridge_definitions, effective_sandbox)
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
    runtime_eligible = [
        row for row in all_rows
        if availability_matches(row.get("availability") or {}, selected_filter)
    ]
    rows = runtime_eligible
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
        availability_candidates=len(all_ordered),
        availability_eligible=len(runtime_eligible),
        max_items_omitted=max_items_omitted,
        availability_source_files=availability_index.scanned_files,
        availability_source_roots=availability_index.source_roots,
    )
    summary["availability_verification"] = {
        "authority": "MarketSense.ItemAvailability (Lua runtime)",
        "static_audit": "offline source scan (comparison only)",
        "checked": len(all_rows),
        "matches": len(all_rows) - len(availability_mismatches),
        "mismatch_count": len(availability_mismatches),
        "mismatches": availability_mismatches[:100],
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
    cache_status = "disabled"
    if result_cache is not None:
        cache_status = "miss" if not options.refresh_cache else "refreshed"
        try:
            result_cache.save(summary, rows)
        except OSError:
            cache_status = "unavailable"
        summary["cache"] = {"status": cache_status, "path": str(result_cache.path)}
    return summary, rows
