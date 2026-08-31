"""Explicit phases for the offline MarketSense scan.

The public evaluator still owns cache and report compatibility, but the work
inside a scan is represented by small contracts.  Keeping these boundaries in
one module makes it possible for the GUI, CLI, and later diagnostics to reuse
the same discovery/evidence/runtime stages without importing the evaluator's
orchestration details.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

from .availability import (
    availability_matches,
    build_acquisition_index,
    normalize_availability_filter,
)
from .bridge import BridgeResult, run_lua_result
from .models import ItemDefinition, WorkshopMod
from .recipe_parser import discover_tool_recipe_usage, discover_yield_recipes
from .scan_scope import candidate_definitions, normalize_category_filter, row_matches_category
from .sandbox import effective_sandbox_settings, load_sandbox_option_specs
from .tile_parser import build_tile_property_index
from .workshop import discover_base_items, discover_items, merge_definitions


ProgressCallback = Callable[[str], None]


@dataclass(frozen=True)
class DiscoveryPhase:
    """The ordered item universe and its source-discovery accounting."""

    mods: list[WorkshopMod]
    definitions_by_type: dict[str, ItemDefinition]
    source_files: int
    definition_count: int
    base_definitions: dict[str, ItemDefinition]
    base_source_files: int
    base_definition_count: int
    merged_definitions: dict[str, ItemDefinition]
    all_ordered: list[ItemDefinition]
    scoped_ordered: list[ItemDefinition]
    category_filter: str
    duplicate_count: int


@dataclass(frozen=True)
class EvidencePhase:
    """Static source evidence prepared for the Lua runtime bridge."""

    availability_index: Any
    availability_records: dict[str, dict]
    selected_filter: str
    effective_sandbox: dict[str, int | float]
    tile_properties: dict[str, dict]
    tile_source_files: int
    yield_recipes: dict[str, list[dict[str, Any]]]
    yield_stats: dict[str, Any]
    tool_recipe_usage: dict[str, list[dict[str, Any]]]
    tool_recipe_stats: dict[str, Any]


@dataclass(frozen=True)
class RuntimePhase:
    """The projected definitions and rows returned by the Lua evaluator."""

    bridge_definitions: list[ItemDefinition]
    bridge_result: BridgeResult


@dataclass(frozen=True)
class RowEnrichmentPhase:
    """Runtime rows enriched with static-audit and filtering information."""

    all_rows: list[dict]
    lua_availability_records: dict[str, dict]
    availability_mismatches: list[dict]
    category_rows: list[dict]
    runtime_eligible: list[dict]
    category_omitted: int


def report_progress(callback: ProgressCallback | None, message: str) -> None:
    """Report a bounded phase message without making logging part of a scan."""

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
    """Project source evidence onto the PZ engine flags used by Lua."""

    projected: list[ItemDefinition] = []
    sprite_properties = sprite_properties or {}
    for definition in definitions:
        props = dict(definition.props)
        record = static_records.get(definition.full_type) or {}
        channels = set(record.get("channels") or [])
        loot_evidence = record.get("rarityEvidence")
        if isinstance(loot_evidence, dict) and loot_evidence.get("status") == "observed":
            props["marketSenseLootEvidence"] = {
                "status": loot_evidence.get("status"),
                "source": loot_evidence.get("source"),
                "sourceCount": loot_evidence.get("sourceCount"),
                "entryCount": loot_evidence.get("entryCount"),
                "weightedEntryCount": loot_evidence.get("weightedEntryCount"),
                "weightSum": loot_evidence.get("weightSum"),
                "relativeWeight": loot_evidence.get("relativeWeight"),
                "references": loot_evidence.get("references") or [],
            }
        if channels & {"loot", "farming", "fishing", "trapping", "animal", "scripted"}:
            props["canSpawnAsLoot"] = True
        if channels & {"craft", "evolved_recipe"}:
            props["isCraftRecipeProduct"] = True
        if "forage" in channels:
            props["canBeForaged"] = True
        sprite_name = str(props.get("worldObjectSprite") or "")
        if sprite_name and sprite_name in sprite_properties:
            # This is the offline equivalent of getSprite(name):
            # getProperties(). Keep the data under its own key so script
            # properties and tile properties cannot overwrite one another.
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


def run_discovery_phase(
    roots: list[Path],
    filters: tuple[str, ...] | list[str],
    game_version: str,
    scripts_root: Path | None,
    category_filter: str,
    progress: ProgressCallback | None = None,
) -> DiscoveryPhase:
    """Discover Workshop/base definitions and establish stable scan order."""

    report_progress(progress, "workshop: discovering mod metadata and item scripts")
    mods, definitions_by_type, source_files, definition_count = discover_items(
        roots, list(filters), game_version
    )
    report_progress(progress, (
        f"workshop: found {len(mods):,} mods, {len(definitions_by_type):,} unique "
        f"definitions across {source_files:,} script files"
    ))
    report_progress(progress, "base: discovering installed vanilla item scripts")
    base_definitions, base_source_files, base_definition_count = discover_base_items(
        scripts_root
    )
    report_progress(progress, (
        f"base: found {len(base_definitions):,} definitions across "
        f"{base_source_files:,} script files"
    ))
    merged_definitions = merge_scan_definitions(base_definitions, definitions_by_type)
    all_ordered = [merged_definitions[key] for key in sorted(merged_definitions)]
    normalized_category = normalize_category_filter(category_filter)
    scoped_ordered = candidate_definitions(all_ordered, normalized_category)
    report_progress(progress, f"universe: merged {len(all_ordered):,} item definitions")
    if normalized_category:
        report_progress(progress, (
            f"scope: {normalized_category} candidates {len(scoped_ordered):,} / "
            f"{len(all_ordered):,} definitions"
        ))
    return DiscoveryPhase(
        mods=mods,
        definitions_by_type=definitions_by_type,
        source_files=source_files,
        definition_count=definition_count,
        base_definitions=base_definitions,
        base_source_files=base_source_files,
        base_definition_count=base_definition_count,
        merged_definitions=merged_definitions,
        all_ordered=all_ordered,
        scoped_ordered=scoped_ordered,
        category_filter=normalized_category,
        duplicate_count=max(0, definition_count - len(definitions_by_type)),
    )


def run_evidence_phase(
    discovery: DiscoveryPhase,
    scripts_root: Path | None,
    game_version: str,
    sandbox_options: dict[str, int | float],
    availability_filter: str,
    progress: ProgressCallback | None = None,
) -> EvidencePhase:
    """Build the static evidence graphs consumed by the runtime phase."""

    report_progress(progress, "availability: building acquisition evidence index")
    mod_roots = (mod.root for mod in discovery.mods)
    availability_index = build_acquisition_index(
        discovery.scoped_ordered,
        scripts_root,
        mod_roots,
        game_version,
    )
    availability_records = availability_index.records(discovery.scoped_ordered)
    report_progress(progress, (
        f"availability: indexed {len(availability_records):,} rows from "
        f"{availability_index.scanned_files:,} source files"
    ))
    selected_filter = normalize_availability_filter(availability_filter)
    effective_sandbox = effective_sandbox_settings(
        sandbox_options,
        load_sandbox_option_specs(game_version),
    )
    tile_properties, tile_source_files = build_tile_property_index(
        scripts_root,
        (mod.root for mod in discovery.mods),
        game_version,
    )
    yield_recipes, yield_stats = discover_yield_recipes(
        scripts_root,
        (mod.root for mod in discovery.mods),
        game_version,
        discovery.merged_definitions,
    )
    report_progress(progress, (
        f"recipes: indexed {yield_stats['recipeCount']:,} craft recipes and "
        f"{yield_stats['sourceCount']:,} single-input yield sources"
    ))
    tool_recipe_usage, tool_recipe_stats = discover_tool_recipe_usage(
        scripts_root,
        (mod.root for mod in discovery.mods),
        game_version,
        discovery.merged_definitions,
    )
    report_progress(progress, (
        f"tool demand: indexed {tool_recipe_stats['reusableInputCount']:,} reusable "
        f"recipe inputs across {len(tool_recipe_usage):,} items"
    ))
    return EvidencePhase(
        availability_index=availability_index,
        availability_records=availability_records,
        selected_filter=selected_filter,
        effective_sandbox=effective_sandbox,
        tile_properties=tile_properties,
        tile_source_files=tile_source_files,
        yield_recipes=yield_recipes,
        yield_stats=yield_stats,
        tool_recipe_usage=tool_recipe_usage,
        tool_recipe_stats=tool_recipe_stats,
    )


def run_runtime_phase(
    lua: str,
    discovery: DiscoveryPhase,
    evidence: EvidencePhase,
    progress: ProgressCallback | None = None,
) -> RuntimePhase:
    """Project evidence and execute the unchanged Lua bridge contract."""

    bridge_definitions = emulate_pz_acquisition_flags(
        discovery.all_ordered,
        evidence.availability_records,
        evidence.tile_properties,
    )
    report_progress(progress, f"lua: evaluating {len(bridge_definitions):,} definitions")
    bridge_result = run_lua_result(
        lua,
        bridge_definitions,
        evidence.effective_sandbox,
        yield_recipes=evidence.yield_recipes,
        tool_recipe_usage=evidence.tool_recipe_usage,
        emitted_types={definition.full_type for definition in discovery.scoped_ordered},
    )
    report_progress(progress, f"lua: returned {len(bridge_result.rows):,} rows")
    return RuntimePhase(bridge_definitions=bridge_definitions, bridge_result=bridge_result)


def enrich_runtime_rows(
    rows: list[dict],
    availability_records: dict[str, dict],
    category_filter: str,
    selected_filter: str,
) -> RowEnrichmentPhase:
    """Attach audit comparison fields and calculate scan-time row scopes."""

    all_rows: list[dict] = []
    lua_availability_records: dict[str, dict] = {}
    availability_mismatches: list[dict] = []
    for row in rows:
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
    return RowEnrichmentPhase(
        all_rows=all_rows,
        lua_availability_records=lua_availability_records,
        availability_mismatches=availability_mismatches,
        category_rows=category_rows,
        runtime_eligible=runtime_eligible,
        category_omitted=category_omitted,
    )
