"""Read and edit Market Sense's dedicated per-litre liquid price contract.

The base data and the override data are Lua tables because the game consumes
them directly.  This module only evaluates those small, static data files
with the same Lua executable used by the harness; it never executes Workshop
item scripts as Python code.
"""

from __future__ import annotations

import datetime as _datetime
import json
import math
import os
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .bridge import find_lua
from .config import LIQUID_PRICING_DATA_PATH, LIQUID_PRICING_OVERRIDE_PATH


class LiquidPricingError(RuntimeError):
    """Raised when the liquid data contract cannot be read or written."""


# This is intentionally a small table decoder rather than a general Lua
# parser.  The files are shipped data modules that return one table.  Running
# the actual Lua interpreter keeps the inspector aligned with Kahlua/Lua
# syntax and avoids a second, subtly different parser in Python.
_LUA_TO_JSON = r'''
local function quote(value)
    value = value:gsub("\\", "\\\\")
    value = value:gsub('"', '\\"')
    value = value:gsub("\n", "\\n")
    value = value:gsub("\r", "\\r")
    value = value:gsub("\t", "\\t")
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
    if kind == "nil" then return "null" end
    if kind == "string" then return quote(value) end
    if kind == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            return "null"
        end
        return tostring(value)
    end
    if kind == "boolean" then return value and "true" or "false" end
    if kind ~= "table" then error("unsupported Lua value: " .. kind) end
    if not force_object and is_array(value) then
        local result = {}
        for index = 1, #value do result[#result + 1] = encode(value[index], false) end
        return "[" .. table.concat(result, ",") .. "]"
    end
    local keys = {}
    for key, _ in pairs(value) do
        if type(key) ~= "string" then error("liquid data has a non-string map key") end
        keys[#keys + 1] = key
    end
    table.sort(keys)
    local result = {}
    for _, key in ipairs(keys) do
        result[#result + 1] = quote(key) .. ":" .. encode(value[key], false)
    end
    return "{" .. table.concat(result, ",") .. "}"
end

local value = dofile(assert(arg[1], "liquid data path is required"))
if type(value) ~= "table" then error("liquid data must return a table") end
io.write(encode(value, true))
'''


def _finite_price(value: Any, fallback: float | None = None) -> float | None:
    if isinstance(value, bool):
        return fallback
    try:
        number = float(value)
    except (TypeError, ValueError):
        return fallback
    if not math.isfinite(number) or number < 0:
        return fallback
    return number


def _lua_table(path: Path, lua: str | None) -> dict[str, Any]:
    target = path.expanduser().resolve()
    if not target.is_file():
        return {}
    interpreter = lua or find_lua(None)
    try:
        process = subprocess.run(
            [interpreter, "-e", _LUA_TO_JSON, "-", str(target)],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
            timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise LiquidPricingError(f"Could not read {target}: {error}") from error
    if process.returncode != 0:
        detail = process.stdout.strip()[-2_000:]
        raise LiquidPricingError(
            f"Could not read {target}: Lua exited with {process.returncode}. {detail}"
        )
    try:
        decoded = json.loads(process.stdout)
    except json.JSONDecodeError as error:
        raise LiquidPricingError(
            f"Could not read {target}: Lua returned invalid JSON ({error})."
        ) from error
    if not isinstance(decoded, dict):
        raise LiquidPricingError(f"Liquid data at {target} did not return an object.")
    return decoded


def _mapping(value: Any) -> dict[str, Any]:
    return value if isinstance(value, dict) else {}


@dataclass
class LiquidPriceRow:
    """One editable exact fluid, family fallback, or global fallback row."""

    kind: str
    key: str
    primary: str
    price_per_liter: float
    base_price_per_liter: float | None
    source: str
    overridden: bool
    note: str

    @property
    def iid(self) -> str:
        return f"liquid:{self.kind}:{self.key}"


class LiquidPricingCatalog:
    """Merged base/override view with edits kept as sparse overrides."""

    def __init__(
        self,
        base: dict[str, Any],
        overrides: dict[str, Any],
        base_path: Path,
        override_path: Path,
    ) -> None:
        self.base_path = base_path.expanduser().resolve()
        self.override_path = override_path.expanduser().resolve()
        self.base_default = _finite_price(base.get("defaultPricePerLiter"), 5.0) or 5.0
        configured_default = _finite_price(overrides.get("defaultPricePerLiter"))
        self.default_price = (
            self.base_default if configured_default is None else configured_default
        )
        self.base_exact = _mapping(base.get("liquids"))
        self.base_families = _mapping(base.get("primaryDefaults"))
        self.override_exact = dict(_mapping(overrides.get("liquids")))
        self.override_families = dict(_mapping(overrides.get("primaryDefaults")))
        self.default_overridden = (
            _finite_price(overrides.get("defaultPricePerLiter")) is not None
        )
        self.exact: dict[str, LiquidPriceRow] = {}
        self.families: dict[str, LiquidPriceRow] = {}
        self._merge_rows()

    def _merge_rows(self) -> None:
        keys = set(self.base_exact) | set(self.override_exact)
        for key in sorted(keys, key=str.casefold):
            base_definition = _mapping(self.base_exact.get(key))
            override_definition = self.override_exact.get(key)
            base_price = _finite_price(base_definition.get("pricePerLiter"))
            if isinstance(override_definition, dict):
                override_price = _finite_price(override_definition.get("pricePerLiter"))
                override_primary = str(override_definition.get("primary") or "")
            else:
                override_price = _finite_price(override_definition)
                override_primary = ""
            price = override_price if override_price is not None else (
                base_price if base_price is not None else self.base_default
            )
            primary = override_primary or str(base_definition.get("primary") or "")
            self.exact[str(key)] = LiquidPriceRow(
                kind="exact",
                key=str(key),
                primary=primary,
                price_per_liter=price,
                base_price_per_liter=base_price,
                source="override" if override_price is not None else "base",
                overridden=override_price is not None,
                note="Exact fluid anchor; vessel/container is not included.",
            )

        keys = set(self.base_families) | set(self.override_families)
        for key in sorted(keys, key=str.casefold):
            base_price = _finite_price(self.base_families.get(key))
            override_price = _finite_price(self.override_families.get(key))
            price = override_price if override_price is not None else (
                base_price if base_price is not None else self.base_default
            )
            self.families[str(key)] = LiquidPriceRow(
                kind="family",
                key=str(key),
                primary=str(key),
                price_per_liter=price,
                base_price_per_liter=base_price,
                source="override" if override_price is not None else "base",
                overridden=override_price is not None,
                note="Family fallback for exact fluid names not in the table.",
            )

    def rows(self, query: str = "") -> list[LiquidPriceRow]:
        query = query.strip().casefold()
        default_row = LiquidPriceRow(
            kind="default",
            key="Unknown",
            primary="LiquidUnknown",
            price_per_liter=self.default_price,
            base_price_per_liter=self.base_default,
            source="override" if self.default_overridden else "base",
            overridden=self.default_overridden,
            note="Final fallback for an unknown liquid family.",
        )
        candidates = [default_row, *self.families.values(), *self.exact.values()]
        if not query:
            return candidates
        return [
            row for row in candidates
            if query in " ".join((row.kind, row.key, row.primary, row.note)).casefold()
        ]

    def set_price(self, row: LiquidPriceRow, price: float) -> None:
        value = _finite_price(price)
        if value is None:
            raise LiquidPricingError("Price per litre must be a finite non-negative number.")
        row.price_per_liter = value
        row.source = "override"
        row.overridden = True
        if row.kind == "exact":
            current = self.override_exact.get(row.key)
            payload = dict(current) if isinstance(current, dict) else {}
            payload["pricePerLiter"] = value
            if row.primary:
                payload.setdefault("primary", row.primary)
            self.override_exact[row.key] = payload
        elif row.kind == "family":
            self.override_families[row.key] = value
        elif row.kind == "default":
            self.default_price = value
            self.default_overridden = True

    def clear_price(self, row: LiquidPriceRow) -> None:
        if row.kind == "exact":
            self.override_exact.pop(row.key, None)
            row.price_per_liter = (
                self.base_default
                if row.base_price_per_liter is None
                else row.base_price_per_liter
            )
        elif row.kind == "family":
            self.override_families.pop(row.key, None)
            row.price_per_liter = (
                self.base_default
                if row.base_price_per_liter is None
                else row.base_price_per_liter
            )
        elif row.kind == "default":
            self.default_price = self.base_default
            self.default_overridden = False
        row.source = "base"
        row.overridden = False

    def clear_all(self) -> None:
        self.override_exact.clear()
        self.override_families.clear()
        self.default_price = self.base_default
        self.default_overridden = False
        self.exact = {}
        self.families = {}
        self._merge_rows()

    def override_payload(self) -> dict[str, Any]:
        payload: dict[str, Any] = {
            "version": 1,
            "liquids": {
                key: self.override_exact[key]
                for key in sorted(self.override_exact, key=str.casefold)
                if isinstance(self.override_exact[key], (dict, int, float))
            },
            "primaryDefaults": {
                key: self.override_families[key]
                for key in sorted(self.override_families, key=str.casefold)
                if _finite_price(self.override_families[key]) is not None
            },
        }
        if self.default_overridden:
            payload["defaultPricePerLiter"] = self.default_price
        return payload


def load_liquid_catalog(
    lua: str | None = None,
    base_path: Path | None = None,
    override_path: Path | None = None,
) -> LiquidPricingCatalog:
    """Load the shipped anchors and sparse user overrides."""

    base_target = (base_path or LIQUID_PRICING_DATA_PATH).expanduser().resolve()
    override_target = (
        override_path or LIQUID_PRICING_OVERRIDE_PATH
    ).expanduser().resolve()
    base = _lua_table(base_target, lua)
    overrides = _lua_table(override_target, lua)
    return LiquidPricingCatalog(base, overrides, base_target, override_target)


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
            raise LiquidPricingError("Cannot render a non-finite liquid price.")
        return format(value, ".15g")
    if isinstance(value, str):
        return _lua_string(value)
    if isinstance(value, dict):
        if not value:
            return "{}"
        entries = [
            f'{child_indent}[{_lua_string(str(key))}] = '
            f"{_lua_literal(value[key], level + 1)}"
            for key in sorted(value, key=str.casefold)
        ]
        return "{\n" + ",\n".join(entries) + f"\n{indent}}}"
    raise LiquidPricingError(f"Unsupported liquid override value: {type(value).__name__}")


def render_liquid_overrides(
    payload: dict[str, Any], source_label: str = "MarketSense Inspector"
) -> str:
    """Render only the sparse editable liquid overrides as Lua data."""

    timestamp = _datetime.datetime.now(_datetime.timezone.utc)
    return "\n".join((
        "-- MarketSense editable liquid content price overrides",
        f"-- Edited by {source_label} on {timestamp.isoformat(timespec='seconds')}",
        "-- Prices are per litre of liquid content; vessel/container value is separate.",
        "-- This file is optional and survives updates to MS_LiquidPricing_Data.lua.",
        "",
        "return " + _lua_literal(payload),
        "",
    ))


def save_liquid_overrides(
    catalog: LiquidPricingCatalog,
    path: Path | None = None,
    source_label: str = "MarketSense Inspector",
) -> Path:
    """Atomically write the game-readable sparse override module."""

    target = (path or catalog.override_path).expanduser().resolve()
    target.parent.mkdir(parents=True, exist_ok=True)
    content = render_liquid_overrides(catalog.override_payload(), source_label)
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
        raise LiquidPricingError(f"Could not write {target}: {error}") from error
    finally:
        if temporary_name:
            try:
                Path(temporary_name).unlink()
            except OSError:
                pass
    return target


__all__ = [
    "LiquidPriceRow",
    "LiquidPricingCatalog",
    "LiquidPricingError",
    "load_liquid_catalog",
    "render_liquid_overrides",
    "save_liquid_overrides",
]
