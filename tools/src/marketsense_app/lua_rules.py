"""Read and edit the standalone MarketSense runtime-rules Lua data file.

The game mod owns the runtime contract. This module is deliberately a small
host-side editor for that contract: it does not duplicate the Lua rule
application logic or add a second rule engine.
"""

from __future__ import annotations

import copy
import datetime
import json
import math
import os
import subprocess
import tempfile
from pathlib import Path
from typing import Any

from .bridge import find_lua
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


# Lua is used only to evaluate the data file's returned table.  The file is a
# static MarketSense data contract, not arbitrary user code, and the result is
# converted to JSON before Python mutates it.  Keeping this small evaluator in
# the tool means the editor accepts the same Lua table syntax as the game.
_LUA_TO_JSON = r'''
local function quote(value)
    value = value:gsub("\\", "\\\\")
    value = value:gsub('"', '\\"')
    value = value:gsub("\n", "\\n")
    value = value:gsub("\r", "\\r")
    value = value:gsub("\t", "\\t")
    value = value:gsub("\b", "\\b")
    value = value:gsub("\f", "\\f")
    return '"' .. value .. '"'
end

local function is_array(value)
    local count = 0
    local highest = 0
    for key, _ in pairs(value) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
            return false
        end
        count = count + 1
        if key > highest then highest = key end
    end
    return highest == count
end

local function encode(value, force_object)
    local kind = type(value)
    if kind == "nil" then
        return "null"
    elseif kind == "string" then
        return quote(value)
    elseif kind == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            return "null"
        end
        return tostring(value)
    elseif kind == "boolean" then
        return value and "true" or "false"
    elseif kind ~= "table" then
        error("unsupported Lua value: " .. kind)
    end

    if not force_object and is_array(value) then
        local result = {}
        for index = 1, #value do
            result[#result + 1] = encode(value[index], false)
        end
        return "[" .. table.concat(result, ",") .. "]"
    end

    local keys = {}
    for key, _ in pairs(value) do
        if type(key) ~= "string" then
            error("runtime-rules table has a non-string map key")
        end
        keys[#keys + 1] = key
    end
    table.sort(keys)
    local result = {}
    for _, key in ipairs(keys) do
        result[#result + 1] = quote(key) .. ":" .. encode(value[key], false)
    end
    return "{" .. table.concat(result, ",") .. "}"
end

local value = dofile(arg[1])
if type(value) ~= "table" then
    error("runtime-rules data must return a table")
end
io.write(encode(value, true))
'''


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


def load_rules(path: Path | None = None, lua: str | None = None) -> dict[str, Any]:
    """Load and normalize a MarketSense rule document using Lua's parser."""

    target = (path or RUNTIME_RULES_PATH).expanduser().resolve()
    if not target.is_file():
        return default_rules()
    interpreter = lua or find_lua(None)
    try:
        process = subprocess.run(
            # A standalone '-' tells Lua to use stdin as its script, leaving
            # the real data path in arg[1] on Lua 5.1, 5.3, and LuaJIT alike.
            [interpreter, "-e", _LUA_TO_JSON, "-", str(target)],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
            timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise RuntimeRuleError(f"Could not run Lua while reading {target}: {error}") from error
    if process.returncode != 0:
        detail = process.stdout.strip()[-2_000:]
        raise RuntimeRuleError(
            f"Could not parse {target}: Lua exited with {process.returncode}. {detail}"
        )
    try:
        decoded = json.loads(process.stdout)
    except json.JSONDecodeError as error:
        raise RuntimeRuleError(
            f"Could not parse {target}: Lua returned invalid JSON ({error})."
        ) from error
    return normalize_rules(decoded)


def _lua_string(value: str) -> str:
    return json.dumps(str(value), ensure_ascii=False)


def _lua_literal(value: Any, level: int = 0) -> str:
    indent = "    " * level
    child_indent = "    " * (level + 1)
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int) and not isinstance(value, bool):
        return str(value)
    if isinstance(value, float):
        if not math.isfinite(value):
            return "nil"
        return format(value, ".15g")
    if isinstance(value, str):
        return _lua_string(value)
    if isinstance(value, list):
        if not value:
            return "{}"
        return "{\n" + ",\n".join(
            child_indent + _lua_literal(item, level + 1) for item in value
        ) + f"\n{indent}}}"
    if isinstance(value, dict):
        if not value:
            return "{}"
        entries = []
        for key in sorted(value):
            entries.append(
                f"{child_indent}[{_lua_string(str(key))}] = "
                f"{_lua_literal(value[key], level + 1)}"
            )
        return "{\n" + ",\n".join(entries) + f"\n{indent}}}"
    raise RuntimeRuleError(f"Unsupported runtime-rule value: {type(value).__name__}")


def render_rules(rules: Any, source_label: str = "MarketSense Inspector") -> str:
    """Render normalized rules as deterministic, human-readable Lua."""

    normalized = normalize_rules(rules)
    ordered = {key: normalized[key] for key in _ordered_rule_keys(normalized)}
    timestamp = datetime.datetime.now(datetime.timezone.utc)
    lines = [
        "-- MarketSense Runtime Rules Data",
        f"-- Edited by {source_label} on {timestamp.isoformat(timespec='seconds')}",
        "-- Standalone MarketSense runtime contract.",
        "-- Changes made here are consumed by the MarketSense Lua mod.",
        "",
        "return ",
    ]
    rendered = _lua_literal(ordered, 0)
    lines[-1] += rendered
    return "\n".join(lines) + "\n"


def save_rules(
    rules: Any,
    path: Path | None = None,
    source_label: str = "MarketSense Inspector",
) -> Path:
    """Atomically save rules and return the resolved Lua path."""

    target = (path or RUNTIME_RULES_PATH).expanduser().resolve()
    target.parent.mkdir(parents=True, exist_ok=True)
    content = render_rules(rules, source_label)
    temporary_name: str | None = None
    try:
        descriptor, temporary_name = tempfile.mkstemp(
            prefix=f".{target.name}.", suffix=".tmp", dir=target.parent
        )
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_name, target)
        temporary_name = None
    except OSError as error:
        raise RuntimeRuleError(f"Could not write {target}: {error}") from error
    finally:
        if temporary_name:
            try:
                Path(temporary_name).unlink()
            except OSError:
                pass
    return target


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
