"""Lua literal encoding and bridge-script generation."""

from __future__ import annotations

import math
from typing import Any

from .bridge_template import render_bridge
from .models import ItemDefinition


def lua_string(value: Any) -> str:
    text = str(value if value is not None else "")
    text = text.replace("\\", "\\\\").replace('"', '\\"')
    text = text.replace("\r", "\\r").replace("\n", "\\n").replace("\t", "\\t")
    return '"' + text + '"'


def lua_value(value: Any) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if isinstance(value, float) and not math.isfinite(value):
            return "nil"
        return repr(value)
    if isinstance(value, list):
        return "{" + ", ".join(lua_value(item) for item in value) + "}"
    if isinstance(value, dict):
        return "{" + ", ".join(
            f"[{lua_string(key)}]={lua_value(item)}" for key, item in value.items()
        ) + "}"
    return lua_string(value)


def bridge_source(
    definitions: list[ItemDefinition],
    sandbox_options: dict[str, int | float] | None = None,
    yield_recipes: dict[str, list[dict[str, Any]]] | None = None,
    tool_recipe_usage: dict[str, list[dict[str, Any]]] | None = None,
    emitted_types: set[str] | None = None,
) -> str:
    specs = []
    for definition in definitions:
        props = dict(definition.props)
        if "itemType" not in props and "type" in props:
            props["itemType"] = props["type"]
        specs.append({
            "fullType": definition.full_type,
            "module": definition.module,
            "props": props,
            "tags": props.get("tags", []),
            "workshopMod": definition.mod.mod_id,
            "workshopName": definition.mod.name,
            "workshopId": definition.mod.workshop_id,
            "workshopVersion": definition.mod.script_version,
            "scriptPath": definition.script_path,
            "definitionSources": definition.sources or [definition.script_path],
            "emit": emitted_types is None or definition.full_type in emitted_types,
        })
    safe_sandbox = {
        str(key): value for key, value in (sandbox_options or {}).items()
        if isinstance(value, (int, float)) and not isinstance(value, bool)
        and math.isfinite(float(value))
    }
    return render_bridge(
        lua_value(specs), lua_value(safe_sandbox), lua_value(yield_recipes or {}),
        lua_value(tool_recipe_usage or {})
    )
