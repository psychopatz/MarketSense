"""Offline self-test implementation kept outside the scan pipeline."""

from __future__ import annotations

from typing import Any

from marketsense_app.bridge import run_lua, run_lua_result
from marketsense_app.sandbox import recommended_sandbox_settings
from .fixture_data import mock_definitions, mock_yield_recipes
from .self_test_checks import (
    run_catalog_checks,
    run_domain_checks,
    run_pricing_checks,
    run_taxonomy_checks,
)

def self_test(lua: str) -> tuple[bool, list[dict[str, Any]]]:
    rows = run_lua(lua, mock_definitions(), yield_recipes=mock_yield_recipes())
    by_type = {row.get("fullType"): row for row in rows}
    checks: list[dict[str, Any]] = []

    def check(name: str, passed: bool, detail: str) -> None:
        checks.append({"name": name, "passed": bool(passed), "detail": detail})
    run_catalog_checks(rows, by_type, check)
    run_taxonomy_checks(by_type, check)
    run_domain_checks(by_type, check)
    run_pricing_checks(lua, by_type, check)
    return all(check["passed"] for check in checks), checks



def print_self_test(checks: list[dict[str, Any]]) -> None:
    print("MarketSense offline harness self-test")
    for check in checks:
        status = "PASS" if check["passed"] else "FAIL"
        print(f"  {status:<4} {check['name']}: {check['detail']}")
    passed = sum(1 for check in checks if check["passed"])
    print(f"Result: {'PASS' if passed == len(checks) else 'FAIL'} ({passed}/{len(checks)} checks)")
