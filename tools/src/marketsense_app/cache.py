"""Persistent, invalidation-aware result cache for completed scans."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
from typing import Any, Iterable

from .config import DEFAULT_CACHE_DIR, MOD_ROOT, TOOLS_ROOT


# Bumped when the result row universe or exposed runtime evidence changes.
CACHE_FORMAT_VERSION = 8

# Presentation changes (GUI, terminal formatting, exports, and heuristic
# reports) must not force the expensive Workshop/Lua evaluation to run again.
# Only modules that can change the evaluated row universe belong in this list.
EVALUATOR_FILES = (
    "availability.py", "bridge.py", "bridge_runtime.lua", "bridge_template.py",
    "config.py", "evaluation.py", "models.py", "sandbox.py",
    "script_fields.py", "script_parser.py", "tile_parser.py", "workshop.py",
    "workshop_paths.py",
)


def _file_manifest(roots: Iterable[Path], suffixes: tuple[str, ...]) -> list[dict[str, Any]]:
    entries: list[dict[str, Any]] = []
    seen: set[Path] = set()
    for root in roots:
        if not root or not root.is_dir():
            continue
        for suffix in suffixes:
            for path in root.rglob(f"*{suffix}"):
                path = path.resolve()
                if path in seen:
                    continue
                seen.add(path)
                try:
                    stat = path.stat()
                except OSError:
                    entries.append({"path": str(path), "missing": True})
                    continue
                entries.append({
                    "path": str(path),
                    "size": stat.st_size,
                    "mtime_ns": stat.st_mtime_ns,
                })
    return sorted(entries, key=lambda entry: entry["path"])


def _file_manifest_paths(paths: Iterable[Path]) -> list[dict[str, Any]]:
    entries: list[dict[str, Any]] = []
    for path in paths:
        path = path.expanduser().resolve()
        try:
            stat = path.stat()
        except OSError:
            entries.append({"path": str(path), "missing": True})
            continue
        if path.is_file():
            entries.append({
                "path": str(path),
                "size": stat.st_size,
                "mtime_ns": stat.st_mtime_ns,
            })
    return entries


def cache_key(lua: str, options: Any, roots: Iterable[Path], scripts_root: Path | None) -> str:
    """Build a stable key from scan settings and all relevant source metadata."""
    roots = tuple(root.resolve() for root in roots)
    app_root = TOOLS_ROOT / "src" / "marketsense_app"
    payload = {
        "format": CACHE_FORMAT_VERSION,
        "lua": str(Path(lua).resolve()),
        "options": {
            "roots": [str(root) for root in roots],
            "filters": sorted(options.filters),
            "game_version": options.game_version,
            "game_root": str(options.game_root.resolve()) if options.game_root else None,
            "no_base_game": options.no_base_game,
            "max_items": options.max_items,
            "confidence_threshold": options.confidence_threshold,
            "sandbox_options": sorted(options.sandbox_options.items()),
            "availability_filter": getattr(options, "availability_filter", "obtainable"),
        },
        "inputs": {
            # Lua distribution/recipe/foraging data is part of the strict
            # availability gate, so edits there must invalidate a result.
            "workshop": _file_manifest(roots, (".txt", ".lua", ".info")),
            "base": _file_manifest(
                (scripts_root.parent,) if scripts_root else (), (".txt", ".lua")
            ),
            "marketsense": _file_manifest((MOD_ROOT,), (".lua", ".info", ".txt", ".json")),
            "app": _file_manifest_paths(app_root / name for name in EVALUATOR_FILES),
        },
    }
    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


class ResultCache:
    def __init__(self, cache_dir: Path | None, key: str) -> None:
        self.directory = (cache_dir or DEFAULT_CACHE_DIR).expanduser().resolve()
        self.key = key
        self.path = self.directory / f"{key}.json"

    def load(self) -> dict[str, Any] | None:
        try:
            payload = json.loads(self.path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return None
        if payload.get("format") != CACHE_FORMAT_VERSION or payload.get("key") != self.key:
            return None
        result = payload.get("result")
        return result if isinstance(result, dict) else None

    def save(self, summary: dict[str, Any], rows: list[dict[str, Any]]) -> None:
        self.directory.mkdir(parents=True, exist_ok=True)
        payload = {
            "format": CACHE_FORMAT_VERSION,
            "key": self.key,
            "result": {"summary": summary, "items": rows},
        }
        temporary = self.directory / f".{self.key}.{os.getpid()}.tmp"
        temporary.write_text(json.dumps(payload, sort_keys=True), encoding="utf-8")
        temporary.replace(self.path)
        self._prune()

    def _prune(self, keep: int = 20) -> None:
        def modified(path: Path) -> int:
            try:
                return path.stat().st_mtime_ns
            except OSError:
                return 0

        cached = sorted(
            self.directory.glob("*.json"),
            key=modified,
            reverse=True,
        )
        for path in cached[keep:]:
            try:
                path.unlink()
            except OSError:
                continue


def clear_cache(cache_dir: Path | None = None) -> int:
    directory = (cache_dir or DEFAULT_CACHE_DIR).expanduser().resolve()
    removed = 0
    for path in directory.glob("*.json") if directory.is_dir() else ():
        try:
            path.unlink()
            removed += 1
        except OSError:
            continue
    return removed
