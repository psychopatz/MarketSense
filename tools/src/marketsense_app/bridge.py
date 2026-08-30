"""PZ-shaped Lua bridge used to execute the real MarketSense evaluator."""

from __future__ import annotations

import json
import math
import shutil
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .config import MOD_ROOT, REPO_ROOT
from .bridge_template import render_bridge
from .models import ItemDefinition


@dataclass(frozen=True)
class BridgeResult:
    rows: list[dict[str, Any]]
    metadata: dict[str, Any]


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
        lua_value(specs), lua_value(safe_sandbox), lua_value(yield_recipes or {})
    )


def find_lua(explicit: str | None) -> str:
    candidates = [explicit] if explicit else []
    candidates += ["lua5.1", "lua", "luajit"]
    for candidate in candidates:
        if not candidate:
            continue
        executable = shutil.which(candidate) or candidate
        if Path(executable).exists() or shutil.which(candidate):
            try:
                subprocess.run(
                    [executable, "-v"],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    check=True,
                    text=True,
                )
                return executable
            except (OSError, subprocess.SubprocessError):
                continue
    raise RuntimeError("No Lua interpreter found; set --lua or install lua5.1/lua.")


def run_lua_result(
    lua: str,
    definitions: list[ItemDefinition],
    sandbox_options: dict[str, int | float] | None = None,
    yield_recipes: dict[str, list[dict[str, Any]]] | None = None,
    emitted_types: set[str] | None = None,
) -> BridgeResult:
    bridge = bridge_source(
        definitions, sandbox_options, yield_recipes, emitted_types
    )
    with tempfile.TemporaryDirectory(prefix="marketsense-offline-") as temp_dir:
        bridge_path = Path(temp_dir) / "bridge.lua"
        bridge_path.write_text(bridge, encoding="utf-8")
        process = subprocess.run(
            [lua, str(bridge_path), str(MOD_ROOT)],
            cwd=REPO_ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=600,
            check=False,
        )
    rows: list[dict[str, Any]] = []
    metadata: dict[str, Any] = {}
    diagnostics: list[str] = []
    for line in process.stdout.splitlines():
        if line.startswith("MSROW\t"):
            try:
                rows.append(json.loads(line[6:]))
            except json.JSONDecodeError as error:
                diagnostics.append(f"invalid bridge row: {error}")
        elif line.startswith("MSMETA\t"):
            try:
                parsed = json.loads(line[7:])
                if isinstance(parsed, dict):
                    metadata = parsed
            except json.JSONDecodeError as error:
                diagnostics.append(f"invalid bridge metadata: {error}")
        elif line.strip():
            diagnostics.append(line.strip())
    if process.returncode != 0:
        detail = "\n".join(diagnostics[-10:])
        raise RuntimeError(f"Lua bridge exited with {process.returncode}. {detail}")
    return BridgeResult(rows=rows, metadata=metadata)


def run_lua(
    lua: str,
    definitions: list[ItemDefinition],
    sandbox_options: dict[str, int | float] | None = None,
    yield_recipes: dict[str, list[dict[str, Any]]] | None = None,
    emitted_types: set[str] | None = None,
) -> list[dict[str, Any]]:
    """Backward-compatible row-only wrapper around the metadata-aware bridge."""

    return run_lua_result(
        lua, definitions, sandbox_options, yield_recipes, emitted_types
    ).rows
