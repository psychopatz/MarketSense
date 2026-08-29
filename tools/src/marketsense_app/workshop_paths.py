"""Filesystem layouts and PZ version selection for Workshop content."""

from __future__ import annotations

from pathlib import Path
from typing import Iterator


def candidate_mod_roots(root: Path) -> Iterator[tuple[Path, str, str]]:
    """Yield (mod root, Workshop id, source kind) from Steam/local layouts."""
    if (root / "Contents" / "mods").is_dir():
        for mod_root in sorted((root / "Contents" / "mods").iterdir()):
            if mod_root.is_dir():
                yield mod_root, "local", "local"
        return
    if (root / "mods").is_dir():
        for mod_root in sorted((root / "mods").iterdir()):
            if mod_root.is_dir():
                yield mod_root, root.name, "workshop"
        return
    for workshop_dir in sorted(root.iterdir() if root.is_dir() else []):
        if not workshop_dir.is_dir() or not workshop_dir.name.isdigit():
            continue
        mods_dir = workshop_dir / "mods"
        if not mods_dir.is_dir():
            continue
        for mod_root in sorted(mods_dir.iterdir()):
            if mod_root.is_dir():
                yield mod_root, workshop_dir.name, "workshop"


def pz_version_int(value: str) -> int:
    """Match ZomboidFileSystem's major*1000 + minor comparison."""
    parts = value.split(".", 1)
    try:
        major = int(parts[0])
        minor = min(int(parts[1]), 999) if len(parts) == 2 else 0
    except (TypeError, ValueError):
        return 0
    return major * 1000 + minor


def item_script_paths(mod_root: Path, game_version: str | None) -> tuple[list[Path], str]:
    """Select common plus PZ's highest compatible versioned script tree."""
    direct = mod_root / "media" / "scripts"
    if direct.is_dir():
        return sorted(path.resolve() for path in direct.rglob("*.txt")), "direct"

    common = mod_root / "common" / "media" / "scripts"
    versioned = sorted(
        (path for path in mod_root.iterdir() if path.is_dir()
         and pz_version_int(path.name) > 0
         and (path / "media" / "scripts").is_dir()),
        key=lambda path: (pz_version_int(path.name), path.name),
    ) if mod_root.is_dir() else []
    selected: list[Path] = [common] if common.is_dir() else []
    selected_version = "common" if common.is_dir() else "none"
    if versioned:
        target_version = pz_version_int(game_version) if game_version else None
        compatible = [
            path for path in versioned
            if target_version is None or pz_version_int(path.name) <= target_version
        ]
        if not compatible:
            raise RuntimeError(
                f"{mod_root.name}: no version folder is compatible with game {game_version}"
            )
        chosen = compatible[-1]
        selected.append(chosen / "media" / "scripts")
        selected_version = f"{selected_version}+{chosen.name}" if common.is_dir() else chosen.name

    paths: list[Path] = []
    seen: set[Path] = set()
    for script_root in selected:
        for path in script_root.rglob("*.txt"):
            resolved = path.resolve()
            if resolved not in seen:
                seen.add(resolved)
                paths.append(resolved)
    return sorted(paths), selected_version


def default_roots() -> list[Path]:
    home = Path.home()
    candidates = [
        home / ".steam" / "debian-installation" / "steamapps" / "workshop" / "content" / "108600",
        home / ".steam" / "steam" / "steamapps" / "workshop" / "content" / "108600",
        home / ".local" / "share" / "Steam" / "steamapps" / "workshop" / "content" / "108600",
        home / ".steam" / "debian-installation" / "steamapps" / "common" / "ProjectZomboid" / "projectzomboid" / "steamapps" / "workshop" / "content" / "108600",
        home / ".steam" / "steam" / "steamapps" / "common" / "ProjectZomboid" / "projectzomboid" / "steamapps" / "workshop" / "content" / "108600",
        home / ".local" / "share" / "Steam" / "steamapps" / "common" / "ProjectZomboid" / "projectzomboid" / "steamapps" / "workshop" / "content" / "108600",
        home / "Zomboid" / "Workshop",
    ]
    result: list[Path] = []
    for candidate in candidates:
        if candidate.is_dir() and candidate not in result:
            result.append(candidate)
    return result


def game_scripts_root(explicit: Path | None) -> Path | None:
    home = Path.home()
    candidates = [explicit] if explicit else []
    candidates += [
        home / ".steam" / "debian-installation" / "steamapps" / "common" / "ProjectZomboid" / "projectzomboid",
        home / ".steam" / "steam" / "steamapps" / "common" / "ProjectZomboid" / "projectzomboid",
        home / ".local" / "share" / "Steam" / "steamapps" / "common" / "ProjectZomboid" / "projectzomboid",
        home / ".steam" / "debian-installation" / "steamapps" / "common" / "ProjectZomboid",
    ]
    for candidate in candidates:
        if candidate is None:
            continue
        candidate = candidate.expanduser().resolve()
        if candidate.name == "scripts" and candidate.is_dir():
            return candidate
        if (candidate / "media" / "scripts").is_dir():
            return candidate / "media" / "scripts"
    return None
