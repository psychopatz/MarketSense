"""Runtime-rules data contract and normalization."""

from __future__ import annotations

import copy
import math
from pathlib import Path
from typing import Any

from .config import MOD_ROOT

RUNTIME_RULES_PATH = (
    MOD_ROOT
    / "common"
    / "media"
    / "lua"
    / "shared"
    / "MarketSense"
    / "Items"
    / "MS_RuntimeRules_Data.lua"
)

_RULE_LIST_KEYS = (
    "blacklist",
    "blacklistPatterns",
    "whitelist",
    "whitelistPatterns",
)
_RULE_KEY_ORDER = _RULE_LIST_KEYS + ("overrides",)


class RuntimeRuleError(RuntimeError):
    """Raised when the runtime-rules data cannot be safely edited."""


def default_rules() -> dict[str, Any]:
    """Return an empty, normalized rule document."""

    return {
        "blacklist": [],
        "blacklistPatterns": [],
        "whitelist": [],
        "whitelistPatterns": [],
        "overrides": [],
    }


def _string_list(value: Any) -> list[str]:
    if not isinstance(value, list):
        return []
    return list(dict.fromkeys(
        str(entry).strip()
        for entry in value
        if isinstance(entry, str) and entry.strip()
    ))


def _normalized_override(entry: Any, item_id: str | None = None) -> dict[str, Any] | None:
    if not isinstance(entry, dict):
        return None
    result = copy.deepcopy(entry)
    resolved_id = item_id or result.get("id")
    if not isinstance(resolved_id, str) or not resolved_id.strip():
        return None
    result["id"] = resolved_id.strip()
    for key in ("tags", "addTags", "removeTags"):
        if key in result:
            result[key] = _string_list(result[key])
            if not result[key]:
                result.pop(key, None)
    stock = result.get("stock")
    if isinstance(stock, dict):
        normalized_stock = {
            key: int(value)
            for key, value in stock.items()
            if key in ("min", "max")
            and isinstance(value, (int, float))
            and not isinstance(value, bool)
            and math.isfinite(float(value))
        }
        if normalized_stock:
            result["stock"] = normalized_stock
        else:
            result.pop("stock", None)
    return result


def normalize_rules(raw: Any) -> dict[str, Any]:
    """Normalize Lua-decoded data while preserving supported future fields.

    The runtime accepts both ``overrides`` and ``overridesById``.  The editor
    writes one list because it is easier to scan and hand-edit.  If both forms
    exist, the map's fields are merged last, matching the Lua loader's order.
    """

    source = raw if isinstance(raw, dict) else {}
    result: dict[str, Any] = {
        key: copy.deepcopy(value)
        for key, value in source.items()
        if key not in ("overrides", "overridesById")
    }
    for key in _RULE_LIST_KEYS:
        result[key] = _string_list(source.get(key))

    overrides: list[dict[str, Any]] = []
    positions: dict[str, int] = {}
    for entry in source.get("overrides") or []:
        normalized = _normalized_override(entry)
        if normalized is None:
            continue
        item_id = normalized["id"]
        if item_id in positions:
            overrides[positions[item_id]].update(normalized)
        else:
            positions[item_id] = len(overrides)
            overrides.append(normalized)

    map_overrides = source.get("overridesById")
    if isinstance(map_overrides, dict):
        for item_id, entry in map_overrides.items():
            normalized = _normalized_override(entry, str(item_id))
            if normalized is None:
                continue
            resolved_id = normalized["id"]
            if resolved_id in positions:
                overrides[positions[resolved_id]].update(normalized)
            else:
                positions[resolved_id] = len(overrides)
                overrides.append(normalized)
    result["overrides"] = overrides
    return {key: result[key] for key in _ordered_rule_keys(result)}


def _ordered_rule_keys(rules: dict[str, Any]) -> list[str]:
    known = [key for key in _RULE_KEY_ORDER if key in rules]
    return known + sorted(key for key in rules if key not in known)
