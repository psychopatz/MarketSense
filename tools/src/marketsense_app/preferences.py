"""Small, atomic persistence layer for the desktop inspector settings."""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any


PREFERENCES_FORMAT_VERSION = 1


def load_preferences(path: Path | None) -> dict[str, Any]:
    """Load user preferences, returning an empty mapping for bad/missing data."""

    if path is None:
        return {}
    try:
        payload = json.loads(path.expanduser().read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    if not isinstance(payload, dict):
        return {}
    if payload.get("format") != PREFERENCES_FORMAT_VERSION:
        return {}
    return payload


def _safe_string(value: Any) -> str:
    return value.strip() if isinstance(value, str) else ""


def _safe_bool(value: Any, default: bool) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        if value.casefold() in {"1", "true", "yes", "on"}:
            return True
        if value.casefold() in {"0", "false", "no", "off"}:
            return False
    return default


def _safe_nonnegative_int(value: Any) -> int:
    try:
        return max(0, int(value))
    except (TypeError, ValueError):
        return 0


def normalize_preferences(payload: dict[str, Any]) -> dict[str, Any]:
    """Keep only known, serializable GUI settings from a preferences payload."""

    roots = payload.get("workshopRoots")
    if not isinstance(roots, list):
        roots = []
    normalized: dict[str, Any] = {
        "format": PREFERENCES_FORMAT_VERSION,
        "workshopRoots": [value.strip() for value in roots if isinstance(value, str) and value.strip()],
        "gameRoot": _safe_string(payload.get("gameRoot")),
        "modFilters": _safe_string(payload.get("modFilters")),
        "gameVersion": _safe_string(payload.get("gameVersion")),
        "maxItems": _safe_nonnegative_int(payload.get("maxItems") or 0),
        "skipVanilla": _safe_bool(payload.get("skipVanilla"), False),
        "useCache": _safe_bool(payload.get("useCache"), True),
        "refreshCache": _safe_bool(payload.get("refreshCache"), False),
        "availability": _safe_string(payload.get("availability")),
    }
    return normalized


def save_preferences(path: Path | None, values: dict[str, Any]) -> Path | None:
    """Atomically save normalized preferences and return the target path."""

    if path is None:
        return None
    target = path.expanduser().resolve()
    target.parent.mkdir(parents=True, exist_ok=True)
    payload = normalize_preferences(values)
    temporary = target.with_name(f".{target.name}.{os.getpid()}.tmp")
    temporary.write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    temporary.replace(target)
    return target
