"""Parser for Project Zomboid ``*.tiles.txt`` sprite properties.

The game resolves an item's ``WorldObjectSprite`` into a tile definition and
then exposes that definition through ``IsoSprite.getProperties()``.  The
offline harness mirrors only this read path: it never invents classifications
from the tile file and it lets Lua remain authoritative.
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any, Iterable

from .script_parser import clean_value, parse_bool
from .workshop_paths import pz_version_int


_SPRITE_COMMENT = re.compile(r"^\s*//\s*([^/\s]+)\s*$")
_TILE_LINE = re.compile(r"^\s*tile(?:\s*\{)?\s*$", re.IGNORECASE)
_PROPERTY_LINE = re.compile(r"^\s*([A-Za-z_][\w]*)\s*=\s*(.*?)\s*$")
_NUMBER_KEYS = {
    "ContainerCapacity", "PickUpLevel", "PickUpWeight", "Surface",
    "MinimumCarSpeedDmg",
}


def _matching_brace(lines: list[str], opening: int) -> int | None:
    depth = 0
    quote = ""
    for index in range(opening, len(lines)):
        char_position = 0
        line = lines[index]
        while char_position < len(line):
            char = line[char_position]
            if quote:
                if char == "\\":
                    char_position += 2
                    continue
                if char == quote:
                    quote = ""
            elif char in "\"'":
                quote = char
            elif char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
                if depth == 0:
                    return index
            char_position += 1
    return None


def _normalize_properties(lines: Iterable[str]) -> dict[str, Any]:
    properties: dict[str, Any] = {}
    for line in lines:
        match = _PROPERTY_LINE.match(line)
        if not match:
            continue
        key, raw_value = match.groups()
        value = clean_value(raw_value)
        if key in _NUMBER_KEYS:
            try:
                number = float(value)
                properties[key] = int(number) if number.is_integer() else number
                continue
            except ValueError:
                pass
        boolean = parse_bool(value) if value else None
        if boolean is not None:
            properties[key] = boolean
        elif value == "":
            # In the PZ tile format an empty assignment is a present flag,
            # e.g. ``IsTable =`` or ``GenericCraftingSurface =``.
            properties[key] = True
        else:
            properties[key] = value
    return properties


def parse_tile_definitions(path: Path) -> dict[str, dict[str, Any]]:
    """Return ``sprite name -> PropertyContainer-like properties``."""
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return {}

    result: dict[str, dict[str, Any]] = {}
    index = 0
    while index < len(lines):
        comment = _SPRITE_COMMENT.match(lines[index])
        if not comment:
            index += 1
            continue
        sprite_name = comment.group(1).strip()
        tile_index = index + 1
        while tile_index < len(lines) and not lines[tile_index].strip():
            tile_index += 1
        if tile_index >= len(lines) or not _TILE_LINE.match(lines[tile_index]):
            index += 1
            continue
        opening = tile_index
        while opening < len(lines) and "{" not in lines[opening]:
            opening += 1
        if opening >= len(lines):
            index = tile_index + 1
            continue
        closing = _matching_brace(lines, opening)
        if closing is None:
            index = opening + 1
            continue
        result[sprite_name] = _normalize_properties(lines[opening + 1:closing])
        # Continue one line at a time instead of jumping to ``closing``.
        # Some 42.20 tile files contain adjacent tilesets and patch blocks;
        # scanning the comments independently prevents one malformed or
        # nested block from hiding later sprite definitions.
        index += 1
    return result


def _selected_media_roots(mod_root: Path, game_version: str | None) -> list[Path]:
    """Mirror item_script_paths() for media tile-definition roots."""
    direct = mod_root / "media"
    if direct.is_dir():
        return [direct]

    roots: list[Path] = []
    common = mod_root / "common" / "media"
    if common.is_dir():
        roots.append(common)
    versioned = sorted(
        (
            path for path in mod_root.iterdir()
            if path.is_dir()
            and pz_version_int(path.name) > 0
            and (path / "media").is_dir()
        ),
        key=lambda path: (pz_version_int(path.name), path.name),
    ) if mod_root.is_dir() else []
    if versioned:
        target = pz_version_int(game_version) if game_version else None
        compatible = [
            path for path in versioned
            if target is None or pz_version_int(path.name) <= target
        ]
        if compatible:
            roots.append(compatible[-1] / "media")
    return roots


def _tile_paths(media_roots: Iterable[Path]) -> list[Path]:
    paths: list[Path] = []
    seen: set[Path] = set()
    for root in media_roots:
        if not root.is_dir():
            continue
        for path in sorted(root.rglob("*.tiles.txt")):
            resolved = path.resolve()
            if resolved not in seen:
                seen.add(resolved)
                paths.append(resolved)
    return paths


def build_tile_property_index(
    scripts_root: Path | None,
    mod_roots: Iterable[Path],
    game_version: str | None,
) -> tuple[dict[str, dict[str, Any]], list[str]]:
    """Build the same sprite lookup view used by the offline bridge.

    Base definitions are loaded first and workshop roots overlay them in
    discovery order, matching item-definition precedence.  The returned
    source list is useful in summaries and diagnostics without dumping every
    parsed property into the terminal.
    """
    media_roots: list[Path] = []
    if scripts_root is not None:
        base_media = scripts_root.parent
        if base_media.is_dir():
            media_roots.append(base_media)
    for mod_root in mod_roots:
        media_roots.extend(_selected_media_roots(mod_root, game_version))

    index: dict[str, dict[str, Any]] = {}
    source_files: list[str] = []
    for path in _tile_paths(media_roots):
        parsed = parse_tile_definitions(path)
        if not parsed:
            continue
        for sprite_name, properties in parsed.items():
            # Patch tile files commonly repeat a sprite only to add an
            # ambient sound or overlay.  PZ keeps the original properties;
            # merge rather than replacing the complete PropertyContainer.
            index.setdefault(sprite_name, {}).update(properties)
        source_files.append(str(path))
    return index, source_files
