"""Lazy compatibility shim for the source-tree self-test support.

Fixtures and assertions live under tools/tests so they cannot become part
of the production scan package. The wrapper keeps the historical
marketsense_app.testing and marketsense_app.fixtures imports working.
"""

from __future__ import annotations

import importlib
import sys
from pathlib import Path
from typing import Any

_SUPPORT_PACKAGE = "marketsense_app_test_support"


def _load_support() -> Any:
    try:
        return importlib.import_module(_SUPPORT_PACKAGE)
    except ModuleNotFoundError as error:
        if error.name != _SUPPORT_PACKAGE:
            raise
    support_root = Path(__file__).resolve().parents[3] / "tests"
    if not support_root.is_dir():
        raise RuntimeError(
            "MarketSense self-test support is only available from the source checkout."
        )
    support_path = str(support_root)
    if support_path not in sys.path:
        sys.path.insert(0, support_path)
    return importlib.import_module(_SUPPORT_PACKAGE)


def mock_definitions():
    return _load_support().mock_definitions()


def mock_yield_recipes():
    return _load_support().mock_yield_recipes()


def self_test(lua: str):
    return _load_support().self_test(lua)


def print_self_test(checks):
    return _load_support().print_self_test(checks)


__all__ = ["mock_definitions", "mock_yield_recipes", "print_self_test", "self_test"]
