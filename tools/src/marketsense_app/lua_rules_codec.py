"""Lua/JSON codec and persistence for runtime-rules data."""

from __future__ import annotations

import datetime
import json
import math
import os
import subprocess
import tempfile
from pathlib import Path
from typing import Any

from .bridge import find_lua
from .lua_rules_contract import (
    RUNTIME_RULES_PATH,
    RuntimeRuleError,
    _ordered_rule_keys,
    default_rules,
    normalize_rules,
)

# Lua is used only to evaluate the data file's returned table. The file is a
# static MarketSense data contract, not arbitrary user code, and the result is
# converted to JSON before Python mutates it. Keeping this small evaluator in
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
