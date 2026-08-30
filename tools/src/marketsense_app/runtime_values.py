"""Shared value normalization for runtime-cache parsing and comparison."""

from __future__ import annotations

import math
from typing import Any, Iterable

DESCRIPTOR_ROOTS = {"Quality", "Origin", "Rarity", "Theme"}

def _number(value: Any) -> int | float | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)) and math.isfinite(float(value)):
        return value
    try:
        parsed = float(str(value).strip())
    except (TypeError, ValueError):
        return None
    if not math.isfinite(parsed):
        return None
    return int(parsed) if parsed.is_integer() else parsed


def _integer(value: Any) -> int | None:
    parsed = _number(value)
    if parsed is None:
        return None
    return int(parsed)


def _tags(values: Any) -> list[str]:
    if isinstance(values, str):
        values = values.split("|")
    if not isinstance(values, (list, tuple, set)):
        return []
    return sorted({str(value).strip() for value in values if str(value).strip()})


def _primary(tags: Iterable[str]) -> str:
    for tag in tags:
        if str(tag).split(".", 1)[0] not in DESCRIPTOR_ROOTS:
            return str(tag)
    return "Misc"


def _header_value(headers: dict[str, str], key: str, default: str = "") -> str:
    value = str(headers.get(key) or default).strip()
    return value
