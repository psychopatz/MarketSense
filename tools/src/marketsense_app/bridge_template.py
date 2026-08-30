"""Load the static Lua runtime template used by the generated bridge."""

from __future__ import annotations

from pathlib import Path


TEMPLATE_PATH = Path(__file__).with_name("bridge_runtime.lua")
SPEC_MARKER = "__MARKETSENSE_SPEC_LITERAL__"
SANDBOX_MARKER = "__MARKETSENSE_SANDBOX_LITERAL__"
YIELD_MARKER = "__MARKETSENSE_YIELD_LITERAL__"


def render_bridge(
    spec_literal: str, sandbox_literal: str = "{}", yield_literal: str = "{}",
) -> str:
    template = TEMPLATE_PATH.read_text(encoding="utf-8")
    if SPEC_MARKER not in template:
        raise RuntimeError(f"Bridge template is missing {SPEC_MARKER}")
    if SANDBOX_MARKER not in template:
        raise RuntimeError(f"Bridge template is missing {SANDBOX_MARKER}")
    if YIELD_MARKER not in template:
        raise RuntimeError(f"Bridge template is missing {YIELD_MARKER}")
    return template.replace(SPEC_MARKER, spec_literal, 1).replace(
        SANDBOX_MARKER, sandbox_literal, 1
    ).replace(YIELD_MARKER, yield_literal, 1)
