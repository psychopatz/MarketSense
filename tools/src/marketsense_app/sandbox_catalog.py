"""MarketSense sandbox option discovery, validation, and persistence."""

from __future__ import annotations

import json
import math
import os
import re
from dataclasses import dataclass, replace
from pathlib import Path
from typing import Any, Mapping

from .config import DEFAULT_GAME_VERSION, DEFAULT_SANDBOX_SETTINGS_PATH, MOD_ROOT


SANDBOX_FORMAT_VERSION = 1
SANDBOX_CATALOG_PATH = Path(__file__).with_name("sandbox_defaults.json")
_OPTION_BLOCK = re.compile(
    r"option\s+MarketSense\.([A-Za-z0-9_]+)\s*\{(.*?)\}", re.DOTALL
)
_FIELD = re.compile(r"^\s*([A-Za-z]+)\s*=\s*([^,\s]+)", re.MULTILINE)
_VERSION_FOLDER = re.compile(r"^\d+(?:\.\d+)?$")


@dataclass(frozen=True)
class SandboxOption:
    key: str
    label: str
    tooltip: str
    option_type: str
    default: int | float | None
    minimum: int | float | None
    maximum: int | float | None
    page: str
    # ``declared_default`` preserves the value from sandbox-options.txt even
    # when the Python catalog supplies a corrected/effective default.
    declared_default: int | float | None = None
    category_path: str = ""
    definition_source: str = "declared"

    @property
    def is_integer(self) -> bool:
        return self.option_type == "integer"


class SandboxSettingsError(ValueError):
    """Raised when a settings file contains an unsafe or invalid value."""


def _option_key(path: str, prefix: str, suffix: str) -> str:
    return f"{prefix}{path.replace('.', '')}{suffix}"


def _path_from_label(label: str) -> str:
    marker = ":"
    if marker not in label:
        return ""
    value = label.split(marker, 1)[1].strip()
    return value.replace(" > ", ".")


def _page_for_path(path: str) -> str:
    root = path.split(".", 1)[0]
    page_roots = {
        "Accessory": "Clothing",
        "Ammo": "Weapon",
        "Bandage": "Medical",
        "Beverage": "Food",
        "Cooking": "Tool",
        "Explosive": "Weapon",
        "Firearm": "Weapon",
        "FirstAid": "Medical",
        "Gardening": "Building",
        "Material": "Resource",
        "Memento": "Misc",
        "ProtectiveGear": "Clothing",
        "Smoking": "Misc",
    }
    return "MarketSense" + page_roots.get(root, root)


def _catalog_number(value: Any, *, integer: bool = False) -> int | float | None:
    if isinstance(value, bool) or value is None:
        return None
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    if not math.isfinite(number):
        return None
    return int(round(number)) if integer else number


def load_sandbox_catalog(
    path: Path | None = None,
) -> dict[str, Any]:
    """Load the editable Python-side recommendation catalog.

    A broken catalog must not prevent the GUI from opening.  The returned
    ``error`` field is surfaced by the definition audit instead.
    """

    target = (path or SANDBOX_CATALOG_PATH).expanduser()
    try:
        payload = json.loads(target.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return {"version": 0, "recommendations": [], "error": str(error)}
    if not isinstance(payload, dict):
        return {
            "version": 0,
            "recommendations": [],
            "error": "catalog root must be a JSON object",
        }
    recommendations = payload.get("recommendations", [])
    if not isinstance(recommendations, list):
        payload["recommendations"] = []
        payload["error"] = "catalog recommendations must be a JSON array"
        return payload

    valid: list[dict[str, Any]] = []
    errors: list[str] = []
    for index, entry in enumerate(recommendations):
        if not isinstance(entry, dict):
            errors.append(f"recommendation {index + 1} is not an object")
            continue
        category_path = entry.get("path")
        if not isinstance(category_path, str) or not re.fullmatch(
            r"[A-Za-z][A-Za-z0-9]*(?:\.[A-Za-z][A-Za-z0-9]*)*", category_path
        ):
            errors.append(f"recommendation {index + 1} has an invalid path")
            continue
        price = _catalog_number(entry.get("price"), integer=True)
        stock = _catalog_number(entry.get("stock", 1.0))
        if price is None and stock is None:
            errors.append(f"recommendation {category_path} has no numeric values")
            continue
        valid.append({
            "path": category_path,
            "price": price,
            "stock": 1.0 if stock is None else stock,
            "reason": str(entry.get("reason") or "Python-side recommendation"),
        })
    payload["recommendations"] = valid
    if errors:
        payload["error"] = "; ".join(errors[:5])
    return payload


def _recommendation_records(
    catalog: Mapping[str, Any] | None = None,
) -> dict[str, dict[str, Any]]:
    records: dict[str, dict[str, Any]] = {}
    source = catalog if catalog is not None else load_sandbox_catalog()
    for entry in source.get("recommendations", []):
        path = str(entry["path"])
        for prefix, suffix, value_key in (
            ("Price", "Value", "price"),
            ("Stock", "Mult", "stock"),
        ):
            value = entry.get(value_key)
            if value is None:
                continue
            key = _option_key(path, prefix, suffix)
            records[key] = {
                "key": key,
                "path": path,
                "value": value,
                "kind": "price" if prefix == "Price" else "stock",
                "reason": entry.get("reason", "Python-side recommendation"),
            }
    return records


def recommended_sandbox_settings(
    specs: list[SandboxOption] | None = None,
) -> dict[str, int | float]:
    """Return only JSON-backed values intended for the reset/self-heal action."""

    known = specs or load_sandbox_option_specs()
    raw = {
        key: record["value"]
        for key, record in _recommendation_records().items()
    }
    return normalize_settings(raw, known)


def _version_number(value: str) -> tuple[int, int]:
    parts = value.split(".", 1)
    try:
        return int(parts[0]), int(parts[1]) if len(parts) == 2 else 0
    except ValueError:
        return 0, 0


def _versioned_directory(mod_root: Path, game_version: str) -> Path | None:
    candidates = [
        path for path in mod_root.iterdir()
        if path.is_dir() and _VERSION_FOLDER.match(path.name)
        and _version_number(path.name) <= _version_number(game_version)
    ] if mod_root.is_dir() else []
    if not candidates:
        return None
    return max(candidates, key=lambda path: _version_number(path.name))


def _mod_version_root(mod_root: Path, game_version: str) -> Path:
    return _versioned_directory(mod_root, game_version) or mod_root


def _load_translations(version_root: Path) -> dict[str, str]:
    path = version_root / "media" / "lua" / "shared" / "Translate" / "EN" / "Sandbox.json"
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return {
        key.removeprefix("Sandbox_MarketSense."): str(value)
        for key, value in payload.items()
        if key.startswith("Sandbox_MarketSense.")
    }

def _parse_scalar(value: str, option_type: str) -> int | float | None:
    try:
        parsed = float(value)
    except ValueError:
        return None
    if not math.isfinite(parsed):
        return None
    if option_type == "integer":
        return int(parsed)
    return parsed


def _fallback_spec(key: str, translations: Mapping[str, str]) -> SandboxOption:
    if key == "PriceMultiplier":
        option_type, default, minimum, maximum = "double", 1.0, 0.0, 100.0
    elif key == "PriceGlobalValue":
        option_type, default, minimum, maximum = "integer", 0, -1000000, 1000000
    elif key == "StockMultiplier":
        option_type, default, minimum, maximum = "double", 1.0, 0.0, 100.0
    elif key.startswith("Price"):
        option_type, default, minimum, maximum = "integer", None, -1000000, 1000000
    else:
        option_type, default, minimum, maximum = "double", None, 0.0, 100.0
    prefix = key.removeprefix("Price").removeprefix("Stock")
    page = "MarketSenseGlobal" if key in {"PriceMultiplier", "PriceGlobalValue", "StockMultiplier"} else (
        "MarketSense" + re.match(r"[A-Za-z]+", prefix).group(0)
        if re.match(r"[A-Za-z]+", prefix) else "MarketSense"
    )
    return SandboxOption(
        key=key,
        label=translations.get(key, key),
        tooltip=translations.get(f"{key}_tooltip", ""),
        option_type=option_type,
        default=default,
        minimum=minimum,
        maximum=maximum,
        page=page,
        declared_default=default,
        category_path=_path_from_label(translations.get(key, key)),
        definition_source="declared",
    )


def _load_declared_sandbox_option_specs(
    game_version: str = DEFAULT_GAME_VERSION,
    mod_root: Path = MOD_ROOT,
) -> list[SandboxOption]:
    """Read the same option declarations and translations shipped by MarketSense."""

    version_root = _mod_version_root(mod_root, game_version)
    translations = _load_translations(version_root)
    options_path = version_root / "media" / "sandbox-options.txt"
    try:
        source = options_path.read_text(encoding="utf-8")
    except OSError:
        source = ""

    specs: list[SandboxOption] = []
    for key, body in _OPTION_BLOCK.findall(source):
        fields = {name: value for name, value in _FIELD.findall(body)}
        option_type = fields.get("type", "double")
        declared_default = _parse_scalar(fields.get("default", ""), option_type)
        label = translations.get(
            fields.get("translation", key), translations.get(key, key)
        )
        specs.append(SandboxOption(
            key=key,
            label=label,
            tooltip=translations.get(
                f"{fields.get('translation', key)}_tooltip",
                translations.get(f"{key}_tooltip", ""),
            ),
            option_type=option_type,
            default=declared_default,
            minimum=_parse_scalar(fields.get("min", ""), option_type),
            maximum=_parse_scalar(fields.get("max", ""), option_type),
            page=fields.get("page", "MarketSense"),
            declared_default=declared_default,
            category_path=_path_from_label(label),
            definition_source="declared",
        ))

    if not specs:
        keys = sorted(
            key for key in translations
            if (key.startswith("Price") or key.startswith("Stock"))
            and not key.endswith("_tooltip")
        )
        specs = [_fallback_spec(key, translations) for key in keys]

    return sorted(specs, key=lambda spec: (spec.page, spec.key))


def _recommended_spec(record: Mapping[str, Any]) -> SandboxOption:
    is_price = record["kind"] == "price"
    path = str(record["path"])
    label_path = path.replace(".", " > ")
    key = str(record["key"])
    label = (
        f"Price: {label_path}"
        if is_price else f"Stock multiplier: {label_path}"
    )
    tooltip = (
        f"{record.get('reason', 'Python-side recommendation')}. "
        "This setting is supplied by the Python harness because the live "
        "sandbox declaration does not expose this category yet."
    )
    return SandboxOption(
        key=key,
        label=label,
        tooltip=tooltip,
        option_type="integer" if is_price else "double",
        default=record["value"],
        minimum=-1000000 if is_price else 0.0,
        maximum=1000000 if is_price else 100.0,
        page=_page_for_path(path),
        declared_default=None,
        category_path=path,
        definition_source="python-recommended",
    )


def load_sandbox_option_specs(
    game_version: str = DEFAULT_GAME_VERSION,
    mod_root: Path = MOD_ROOT,
    *,
    include_recommended: bool = True,
) -> list[SandboxOption]:
    """Load live options and merge editable Python recommendations.

    Live ``sandbox-options.txt`` entries remain visible as declared options.
    Missing JSON recommendations are represented as virtual options so the
    harness can exercise the same ``SandboxVars.MarketSense`` lookup and the
    GUI can edit them without modifying generated Lua files.
    """

    declared = _load_declared_sandbox_option_specs(game_version, mod_root)
    if not include_recommended:
        return declared

    records = _recommendation_records()
    merged: list[SandboxOption] = []
    declared_keys = {spec.key for spec in declared}
    for spec in declared:
        record = records.get(spec.key)
        if record is None:
            merged.append(spec)
            continue
        merged.append(replace(
            spec,
            default=record["value"],
            category_path=str(record["path"]),
            definition_source="declared+python-recommended",
        ))
    merged.extend(
        _recommended_spec(record)
        for key, record in records.items()
        if key not in declared_keys
    )
    return sorted(merged, key=lambda spec: (spec.page, spec.category_path, spec.key))


def option_map(specs: list[SandboxOption] | None = None) -> dict[str, SandboxOption]:
    return {spec.key: spec for spec in (specs or load_sandbox_option_specs())}


def _coerce_value(value: Any, spec: SandboxOption | None) -> int | float:
    if isinstance(value, bool):
        raise SandboxSettingsError("boolean values are not valid sandbox numbers")
    try:
        parsed = float(value)
    except (TypeError, ValueError) as error:
        raise SandboxSettingsError(f"invalid numeric value {value!r}") from error
    if not math.isfinite(parsed):
        raise SandboxSettingsError("sandbox values must be finite numbers")
    if spec and spec.minimum is not None:
        parsed = max(parsed, float(spec.minimum))
    if spec and spec.maximum is not None:
        parsed = min(parsed, float(spec.maximum))
    return int(round(parsed)) if spec and spec.is_integer else parsed


def normalize_settings(
    values: Mapping[str, Any], specs: list[SandboxOption] | None = None,
) -> dict[str, int | float]:
    """Validate settings while retaining only MarketSense numeric option keys."""

    known = option_map(specs)
    normalized: dict[str, int | float] = {}
    for key, value in values.items():
        if value is None or value == "":
            continue
        key = str(key)
        spec = known.get(key)
        if spec is None and not (key.startswith("Price") or key.startswith("Stock")):
            continue
        normalized[key] = _coerce_value(value, spec)
    return dict(sorted(normalized.items()))


def default_sandbox_settings(
    specs: list[SandboxOption] | None = None,
) -> dict[str, int | float]:
    """Return effective defaults, including JSON corrections/recommendations."""

    return {
        spec.key: spec.default
        for spec in (specs or load_sandbox_option_specs())
        if spec.default is not None
    }
