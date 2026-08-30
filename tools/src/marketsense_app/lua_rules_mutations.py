"""Pure rule-document mutations used by the runtime-rules editor."""

from __future__ import annotations

import json
from typing import Any

from .lua_rules_contract import RuntimeRuleError, _string_list, normalize_rules

def _upsert_override(rules: dict[str, Any], item_id: str) -> dict[str, Any]:
    for entry in rules["overrides"]:
        if entry.get("id") == item_id:
            return entry
    entry = {"id": item_id}
    rules["overrides"].append(entry)
    return entry


def set_item_override(
    rules: dict[str, Any],
    item_id: str,
    **fields: Any,
) -> dict[str, Any]:
    """Merge editor fields into one exact item override."""

    normalized = normalize_rules(rules)
    rules.clear()
    rules.update(normalized)
    item_id = str(item_id).strip()
    if not item_id:
        raise RuntimeRuleError("An item override requires a non-empty full type.")
    entry = _upsert_override(rules, item_id)
    for key, value in fields.items():
        if value is None or value == "":
            entry.pop(key, None)
        elif key in ("tags", "addTags", "removeTags"):
            values = _string_list(value if isinstance(value, list) else [value])
            if values:
                entry[key] = values
            else:
                entry.pop(key, None)
        elif key == "stock" and isinstance(value, dict):
            stock = {
                name: max(0, int(number))
                for name, number in value.items()
                if name in ("min", "max") and number is not None
            }
            if stock.get("min") is not None and stock.get("max") is not None:
                stock["min"] = min(stock["min"], stock["max"])
            if stock:
                entry[key] = stock
            else:
                entry.pop(key, None)
        else:
            entry[key] = value
    return entry


def remove_item_override(rules: dict[str, Any], item_id: str) -> bool:
    normalized = normalize_rules(rules)
    rules.clear()
    rules.update(normalized)
    before = len(rules["overrides"])
    rules["overrides"] = [
        entry for entry in rules["overrides"] if entry.get("id") != item_id
    ]
    return len(rules["overrides"]) != before


def set_membership_rule(
    rules: dict[str, Any], item_id: str, membership: str | None
) -> None:
    """Set exact whitelist/blacklist membership with mutually exclusive UX."""

    normalized = normalize_rules(rules)
    rules.clear()
    rules.update(normalized)
    item_id = str(item_id).strip()
    if not item_id:
        raise RuntimeRuleError("A membership rule requires a non-empty full type.")
    rules["blacklist"] = [value for value in rules["blacklist"] if value != item_id]
    rules["whitelist"] = [value for value in rules["whitelist"] if value != item_id]
    if membership == "blacklist":
        rules["blacklist"].append(item_id)
    elif membership == "whitelist":
        rules["whitelist"].append(item_id)


def remove_all_item_rules(rules: dict[str, Any], item_id: str) -> bool:
    before = json.dumps(normalize_rules(rules), sort_keys=True)
    set_membership_rule(rules, item_id, None)
    remove_item_override(rules, item_id)
    return json.dumps(normalize_rules(rules), sort_keys=True) != before
