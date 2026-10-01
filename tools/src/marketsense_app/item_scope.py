"""Normalize and resolve targeted item cases for the MarketSense harness."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Iterable

from .models import ItemDefinition


def normalize_item_types(values: Iterable[Any]) -> tuple[str, ...]:
    """Return stable, de-duplicated full types while preserving request order."""

    result: list[str] = []
    seen: set[str] = set()
    for value in values:
        text = str(value or "").strip()
        if not text:
            continue
        # Accept comma-separated command-line values without making the CLI
        # depend on shell-specific quoting rules.
        for token in text.split(","):
            item_type = token.strip()
            if not item_type:
                continue
            key = item_type.casefold()
            if key not in seen:
                seen.add(key)
                result.append(item_type)
    return tuple(result)


def load_item_types(path: Path) -> tuple[str, ...]:
    """Load full types from JSON or one-per-line text."""

    text = path.expanduser().read_text(encoding="utf-8")
    try:
        payload = json.loads(text)
    except json.JSONDecodeError:
        payload = None

    if isinstance(payload, dict):
        payload = payload.get("items", payload.get("itemTypes", []))
    if isinstance(payload, list):
        return normalize_item_types(payload)

    return normalize_item_types(
        line.split("#", 1)[0].strip()
        for line in text.splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    )


def select_item_definitions(
    definitions: Iterable[ItemDefinition],
    item_types: tuple[str, ...],
) -> tuple[list[ItemDefinition], list[str]]:
    """Select exact definitions and return requested types that were missing."""

    ordered = list(definitions)
    if not item_types:
        return ordered, []
    by_type = {definition.full_type.casefold(): definition for definition in ordered}
    selected: list[ItemDefinition] = []
    missing: list[str] = []
    for item_type in item_types:
        definition = by_type.get(item_type.casefold())
        if definition is None:
            missing.append(item_type)
        else:
            selected.append(definition)
    return selected, missing
