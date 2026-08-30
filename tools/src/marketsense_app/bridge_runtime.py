"""Process execution for the PZ-shaped Lua bridge."""

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .bridge_values import bridge_source
from .config import MOD_ROOT, REPO_ROOT
from .models import ItemDefinition


@dataclass(frozen=True)
class BridgeResult:
    rows: list[dict[str, Any]]
    metadata: dict[str, Any]


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
    tool_recipe_usage: dict[str, list[dict[str, Any]]] | None = None,
    emitted_types: set[str] | None = None,
) -> BridgeResult:
    bridge = bridge_source(
        definitions, sandbox_options, yield_recipes, tool_recipe_usage, emitted_types
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
    tool_recipe_usage: dict[str, list[dict[str, Any]]] | None = None,
    emitted_types: set[str] | None = None,
) -> list[dict[str, Any]]:
    """Backward-compatible row-only wrapper around the metadata-aware bridge."""

    return run_lua_result(
        lua, definitions, sandbox_options, yield_recipes, tool_recipe_usage,
        emitted_types
    ).rows
