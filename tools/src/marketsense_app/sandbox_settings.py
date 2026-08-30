"""Sandbox settings normalization and atomic persistence."""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any, Mapping

from .config import DEFAULT_SANDBOX_SETTINGS_PATH
from .sandbox_catalog import (
    SANDBOX_FORMAT_VERSION,
    SandboxOption,
    SandboxSettingsError,
    default_sandbox_settings,
    load_sandbox_option_specs,
    normalize_settings,
)

def effective_sandbox_settings(
    overrides: Mapping[str, Any], specs: list[SandboxOption] | None = None,
) -> dict[str, bool | int | float]:
    """Merge local overrides over the mod's declared sandbox defaults."""

    known = specs or load_sandbox_option_specs()
    effective = default_sandbox_settings(known)
    effective.update(normalize_settings(overrides, known))
    return dict(sorted(effective.items()))


def load_sandbox_settings(
    path: Path | None = None, specs: list[SandboxOption] | None = None,
) -> dict[str, bool | int | float]:
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
    return f"default ({spec.default})"
