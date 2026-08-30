"""Compatibility exports for the historical fixture import path.

New code should import from marketsense_app.testing. The facade remains so
external scripts that used the old module continue to work.
"""

from .testing import (
    mock_definitions,
    mock_yield_recipes,
    print_self_test,
    self_test,
)

__all__ = [
    "mock_definitions", "mock_yield_recipes", "print_self_test", "self_test",
]
