"""Discover and merge Workshop/vanilla item definitions."""

from __future__ import annotations

from pathlib import Path
from typing import Iterable

from .models import ItemDefinition, WorkshopMod
from .script_parser import mod_from_root, parse_script
from .workshop_paths import candidate_mod_roots, item_script_paths


def discover_items(
    roots: Iterable[Path], filters: list[str], game_version: str | None,
) -> tuple[list[WorkshopMod], dict[str, ItemDefinition], int, int]:
    mods: list[WorkshopMod] = []
    definitions: dict[str, ItemDefinition] = {}
    source_files = 0
    definition_count = 0
    seen_mod_roots: set[Path] = set()
    seen_mod_keys: set[tuple[str, str]] = set()
    for root in roots:
        for mod_root, workshop_id, source_kind in candidate_mod_roots(root):
            mod_root = mod_root.resolve()
            if mod_root in seen_mod_roots:
                continue
            seen_mod_roots.add(mod_root)
            mod = mod_from_root(mod_root, workshop_id, source_kind)
            mod_key = (mod.workshop_id, mod.mod_id)
            if mod_key in seen_mod_keys:
                continue
            seen_mod_keys.add(mod_key)
            searchable = " ".join((mod.mod_id, mod.name, mod.workshop_id, mod.root.name)).casefold()
            if filters and not any(term.casefold() in searchable for term in filters):
                continue
            mods.append(mod)
            script_paths, selected_version = item_script_paths(mod_root, game_version)
            mod.script_version = selected_version
            source_files += len(script_paths)
            for script_path in script_paths:
                parsed = parse_script(script_path, mod)
                definition_count += len(parsed)
                for definition in parsed:
                    previous = definitions.get(definition.full_type)
                    if previous is not None:
                        definition.sources = list(previous.sources or [previous.script_path])
                        definition.sources.append(definition.script_path)
                    definitions[definition.full_type] = definition
    return mods, definitions, source_files, definition_count


def merge_definitions(previous: ItemDefinition | None, overlay: ItemDefinition) -> ItemDefinition:
    """Merge a later script block over an earlier one like a PZ item patch."""
    if previous is None:
        overlay.sources = list(overlay.sources or [overlay.script_path])
        return overlay
    props = dict(previous.props)
    for key, value in overlay.props.items():
        if key == "tags":
            existing = list(props.get("tags") or [])
            for tag in value if isinstance(value, list) else []:
                if tag not in existing:
                    existing.append(tag)
            props[key] = existing
        else:
            props[key] = value
    sources = list(previous.sources or [previous.script_path])
    sources.extend(overlay.sources or [overlay.script_path])
    return ItemDefinition(
        full_type=overlay.full_type,
        module=overlay.module,
        props=props,
        mod=overlay.mod,
        script_path=overlay.script_path,
        sources=sources,
    )


def discover_base_items(scripts_root: Path | None) -> tuple[dict[str, ItemDefinition], int, int]:
    if scripts_root is None:
        return {}, 0, 0
    base_mod = WorkshopMod(
        root=scripts_root.parent.parent,
        workshop_id="base",
        mod_id="Base",
        name="Project Zomboid",
        source_kind="base",
        script_version="base",
    )
    definitions: dict[str, ItemDefinition] = {}
    source_files = 0
    definition_count = 0
    script_paths = sorted(path.resolve() for path in scripts_root.rglob("*.txt"))
    for script_path in script_paths:
        parsed = parse_script(script_path, base_mod)
        if not parsed:
            continue
        source_files += 1
        definition_count += len(parsed)
        for definition in parsed:
            definitions[definition.full_type] = merge_definitions(
                definitions.get(definition.full_type), definition
            )
    return definitions, source_files, definition_count
