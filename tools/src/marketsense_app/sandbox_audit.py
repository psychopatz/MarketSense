"""Cross-source sandbox definition audit implementation."""

from __future__ import annotations

import math
from pathlib import Path
from typing import Any, Mapping

from .config import DEFAULT_GAME_VERSION, MOD_ROOT
from .sandbox_catalog import (
    SANDBOX_CATALOG_PATH,
    SandboxOption,
    _catalog_number,
    _mod_version_root,
    _option_key,
    _recommendation_records,
    load_sandbox_catalog,
    load_sandbox_option_specs,
)
from .lua_rules import load_rules

def _same_number(left: Any, right: Any) -> bool:
    try:
        return math.isclose(float(left), float(right), rel_tol=1e-9, abs_tol=1e-9)
    except (TypeError, ValueError):
        return False


def _load_lua_document(path: Path) -> tuple[dict[str, Any], str | None]:
    """Read a small returned Lua table for audit-only purposes."""

    try:
        # Keep Lua parsing identical to the rule editor and avoid a second,
        # subtly different parser for generated MarketSense data files.
        from .lua_rules import load_rules

        value = load_rules(path)
    except (OSError, RuntimeError, ValueError) as error:
        return {}, str(error)
    return (value if isinstance(value, dict) else {}), None


def _pricing_data_paths(mod_root: Path) -> tuple[Path, Path]:
    pricing_root = (
        mod_root / "common" / "media" / "lua" / "shared" / "MarketSense" / "Pricing"
    )
    return (
        pricing_root / "MS_PricingConfig_Data.lua",
        pricing_root / "MS_SandboxOverrides_Data.lua",
    )


def _typed_tag_values(document: Mapping[str, Any]) -> dict[str, float]:
    values: dict[str, float] = {}
    modifiers = document.get("market_modifiers")
    if not isinstance(modifiers, dict):
        return values
    additions = modifiers.get("tag_modifiers", modifiers.get("tagModifiers"))
    if not isinstance(additions, dict):
        return values
    for path, rule in additions.items():
        if not isinstance(rule, dict):
            continue
        number = _catalog_number(rule.get("add"))
        if isinstance(path, str) and number is not None:
            values[_option_key(path, "Price", "Value")] = number
    return values


def sandbox_definition_audit(
    game_version: str = DEFAULT_GAME_VERSION,
    specs: list[SandboxOption] | None = None,
    mod_root: Path = MOD_ROOT,
    catalog_path: Path | None = None,
) -> dict[str, Any]:
    """Compare live declarations, generated pricing data, and JSON defaults.

    The audit intentionally separates ``warnings`` from
    ``recommendation_gaps``.  A large taxonomy is useful for the GUI, but only
    actual value conflicts and stale generated entries should look like an
    error to a person debugging the mod.
    """

    declared = specs or load_sandbox_option_specs(
        game_version, mod_root, include_recommended=False
    )
    declared_by_key = {spec.key: spec for spec in declared}
    catalog = load_sandbox_catalog(catalog_path)
    records = _recommendation_records(catalog)
    config_path, generated_path = _pricing_data_paths(mod_root)
    pricing, pricing_error = _load_lua_document(config_path)
    generated, generated_error = _load_lua_document(generated_path)
    pricing_sandbox = pricing.get("sandbox")
    pricing_sandbox = pricing_sandbox if isinstance(pricing_sandbox, dict) else {}
    tag_values = _typed_tag_values(pricing)

    warnings: list[dict[str, Any]] = []

    def warn(kind: str, key: str, message: str, **extra: Any) -> None:
        warnings.append({
            "kind": kind,
            "key": key,
            "message": message,
            **extra,
        })

    if catalog.get("error"):
        warn(
            "catalog-error",
            "sandbox_defaults.json",
            str(catalog["error"]),
            source=str(catalog_path or SANDBOX_CATALOG_PATH),
        )
    if pricing_error:
        warn(
            "pricing-source-error",
            "MS_PricingConfig_Data.lua",
            pricing_error,
            source=str(config_path),
        )
    if generated_error and generated_path.is_file():
        warn(
            "generated-source-error",
            "MS_SandboxOverrides_Data.lua",
            generated_error,
            source=str(generated_path),
        )

    # The generated pricing table is the current category-definition source
    # for the live sandbox declarations. A conflict here catches stale
    # category additions that disagree with their declared sandbox value.
    for key, tag_value in sorted(tag_values.items()):
        sandbox_value = pricing_sandbox.get(key)
        if sandbox_value is not None and not _same_number(sandbox_value, tag_value):
            warn(
                "pricing-definition-mismatch",
                key,
                f"pricing tag value {tag_value:g} differs from sandbox value {float(sandbox_value):g}",
                categoryPath=key.removeprefix("Price").removesuffix("Value"),
                expected=tag_value,
                actual=sandbox_value,
                source="MS_PricingConfig_Data.lua",
            )

    for key, value in sorted(pricing_sandbox.items()):
        spec = declared_by_key.get(key)
        if spec is None or not isinstance(value, (int, float)):
            continue
        if spec.declared_default is not None and not _same_number(
            spec.declared_default, value
        ):
            warn(
                "sandbox-declaration-mismatch",
                key,
                f"sandbox-options.txt default {spec.declared_default} differs from pricing data {value}",
                expected=value,
                actual=spec.declared_default,
                source="sandbox-options.txt vs MS_PricingConfig_Data.lua",
            )

    recommendation_gaps: list[dict[str, Any]] = []
    recommendation_drift: list[dict[str, Any]] = []
    for key, record in sorted(records.items()):
        spec = declared_by_key.get(key)
        if spec is None:
            recommendation_gaps.append({
                "key": key,
                "categoryPath": record["path"],
                "value": record["value"],
                "kind": record["kind"],
                "reason": record["reason"],
            })
            continue
        if spec.declared_default is not None and not _same_number(
            spec.declared_default, record["value"]
        ):
            drift = {
                "key": key,
                "categoryPath": record["path"],
                "declared": spec.declared_default,
                "recommended": record["value"],
                "kind": record["kind"],
                "reason": record["reason"],
            }
            recommendation_drift.append(drift)
            warn(
                "python-recommendation-drift",
                key,
                f"live default {spec.declared_default} differs from recommended {record['value']}",
                categoryPath=record["path"],
                expected=record["value"],
                actual=spec.declared_default,
                reason=record["reason"],
            )

    generated_keys: set[str] = set()
    if not generated_error:
        generated_keys = {
            str(key)
            for key, value in generated.items()
            if (str(key).startswith("Price") or str(key).startswith("Stock"))
            and isinstance(value, (int, float))
        }
    known_keys = set(declared_by_key) | set(records)
    stale_generated = sorted(generated_keys - known_keys)
    for key in stale_generated:
        warn(
            "stale-generated-option",
            key,
            "generated override has no live declaration or Python recommendation",
            source="MS_SandboxOverrides_Data.lua",
        )

    return {
        "status": "warning" if warnings or recommendation_gaps else "ok",
        "gameVersion": game_version,
        "declaredCount": len(declared),
        "recommendedCount": len(records),
        "recommendationGapCount": len(recommendation_gaps),
        "recommendationGaps": recommendation_gaps,
        "recommendationDrift": recommendation_drift,
        "generatedOptionCount": len(generated_keys),
        "staleGeneratedCount": len(stale_generated),
        "warnings": warnings,
        "sources": {
            "sandboxOptions": str(
                _mod_version_root(mod_root, game_version) / "media" / "sandbox-options.txt"
            ),
            "pricingConfig": str(config_path),
            "generatedOverrides": str(generated_path),
            "pythonCatalog": str(catalog_path or SANDBOX_CATALOG_PATH),
        },
    }
