"""MarketSense sandbox option discovery, validation, and persistence."""

from __future__ import annotations

import json
import math
import os
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping

from .config import DEFAULT_GAME_VERSION, DEFAULT_SANDBOX_SETTINGS_PATH, MOD_ROOT


SANDBOX_FORMAT_VERSION = 1
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

    @property
    def is_integer(self) -> bool:
        return self.option_type == "integer"


class SandboxSettingsError(ValueError):
    """Raised when a settings file contains an unsafe or invalid value."""


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
    )


def load_sandbox_option_specs(
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
        specs.append(SandboxOption(
            key=key,
            label=translations.get(fields.get("translation", key), translations.get(key, key)),
            tooltip=translations.get(
                f"{fields.get('translation', key)}_tooltip",
                translations.get(f"{key}_tooltip", ""),
            ),
            option_type=option_type,
            default=_parse_scalar(fields.get("default", ""), option_type),
            minimum=_parse_scalar(fields.get("min", ""), option_type),
            maximum=_parse_scalar(fields.get("max", ""), option_type),
            page=fields.get("page", "MarketSense"),
        ))

    if not specs:
        keys = sorted(
            key for key in translations
            if (key.startswith("Price") or key.startswith("Stock"))
            and not key.endswith("_tooltip")
        )
        specs = [_fallback_spec(key, translations) for key in keys]

    return sorted(specs, key=lambda spec: (spec.page, spec.key))


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
    """Return only declared defaults; ``None`` means inherit Lua fallback behavior."""

    return {
        spec.key: spec.default
        for spec in (specs or load_sandbox_option_specs())
        if spec.default is not None
    }


def effective_sandbox_settings(
    overrides: Mapping[str, Any], specs: list[SandboxOption] | None = None,
) -> dict[str, int | float]:
    """Merge local overrides over the mod's declared sandbox defaults."""

    known = specs or load_sandbox_option_specs()
    effective = default_sandbox_settings(known)
    effective.update(normalize_settings(overrides, known))
    return dict(sorted(effective.items()))


def load_sandbox_settings(
    path: Path | None = None, specs: list[SandboxOption] | None = None,
) -> dict[str, int | float]:
    path = (path or DEFAULT_SANDBOX_SETTINGS_PATH).expanduser()
    if not path.is_file():
        return {}
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SandboxSettingsError(f"could not read sandbox settings: {error}") from error
    if not isinstance(payload, dict):
        raise SandboxSettingsError("sandbox settings must be a JSON object")
    values = payload.get("options", payload)
    if not isinstance(values, dict):
        raise SandboxSettingsError("sandbox settings 'options' must be a JSON object")
    return normalize_settings(values, specs)


def save_sandbox_settings(
    path: Path | None, values: Mapping[str, Any], specs: list[SandboxOption] | None = None,
) -> Path:
    target = (path or DEFAULT_SANDBOX_SETTINGS_PATH).expanduser().resolve()
    normalized = normalize_settings(values, specs)
    target.parent.mkdir(parents=True, exist_ok=True)
    payload = {"version": SANDBOX_FORMAT_VERSION, "options": normalized}
    temporary = target.with_name(f".{target.name}.{os.getpid()}.tmp")
    temporary.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    temporary.replace(target)
    return target


def setting_display(value: Any, spec: SandboxOption) -> str:
    if value is not None:
        return str(value)
    if spec.default is None:
        return "inherit"
    return f"default ({spec.default:g})"
