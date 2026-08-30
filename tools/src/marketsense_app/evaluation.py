"""Shared scan pipeline used by both the console and desktop GUI."""

from __future__ import annotations

from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path

from .cache import ResultCache, cache_key
from .config import DEFAULT_GAME_VERSION
from .heuristics import heuristic_coverage
from .reporting import build_summary
from .review import low_confidence_rows, review_row
from .sandbox import sandbox_definition_audit
from .scan_phases import (
    ProgressCallback,
    emulate_pz_acquisition_flags,
    enrich_runtime_rows,
    merge_scan_definitions,
    report_progress as _progress,
    run_discovery_phase,
    run_evidence_phase,
    run_runtime_phase,
)
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

    discovery = run_discovery_phase(
        roots,
        options.filters,
        options.game_version,
        scripts_root,
        options.category_filter,
        progress,
    )
    evidence = run_evidence_phase(
        discovery,
        scripts_root,
        options.game_version,
        options.sandbox_options,
        options.availability_filter,
        progress,
    )
    runtime = run_runtime_phase(lua, discovery, evidence, progress)
    enriched = enrich_runtime_rows(
        runtime.bridge_result.rows,
        evidence.availability_records,
        discovery.category_filter,
        evidence.selected_filter,
    )
    mods = discovery.mods
    source_files = discovery.source_files
    definition_count = discovery.definition_count
    base_source_files = discovery.base_source_files
    base_definition_count = discovery.base_definition_count
    all_ordered = discovery.all_ordered
    scoped_ordered = discovery.scoped_ordered
    category_filter = discovery.category_filter
    duplicate_count = discovery.duplicate_count
    availability_index = evidence.availability_index
    availability_records = evidence.availability_records
    selected_filter = evidence.selected_filter
    effective_sandbox = evidence.effective_sandbox
    tile_properties = evidence.tile_properties
    tile_source_files = evidence.tile_source_files
    yield_stats = evidence.yield_stats
    tool_recipe_stats = evidence.tool_recipe_stats
    bridge_result = runtime.bridge_result
    all_rows = enriched.all_rows
    lua_availability_records = enriched.lua_availability_records
    availability_mismatches = enriched.availability_mismatches
    category_rows = enriched.category_rows
    runtime_eligible = enriched.runtime_eligible
    category_omitted = enriched.category_omitted
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
