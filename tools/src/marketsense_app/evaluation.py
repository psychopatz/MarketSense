"""Shared scan pipeline used by both the console and desktop GUI."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

from .bridge import run_lua_result
from .cache import ResultCache, cache_key
from .config import DEFAULT_GAME_VERSION
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
    ordered = [merged_definitions[key] for key in sorted(merged_definitions)]
    if options.max_items > 0:
        ordered = ordered[:options.max_items]
    duplicate_count = max(0, definition_count - len(definitions_by_type))
    sandbox_specs = load_sandbox_option_specs(options.game_version)
    effective_sandbox = effective_sandbox_settings(options.sandbox_options, sandbox_specs)
    bridge_result = run_lua_result(lua, ordered, effective_sandbox)
    rows = bridge_result.rows
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
    )
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
