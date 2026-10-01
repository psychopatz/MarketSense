"""Headless Project Zomboid runner for authoritative MarketSense cases."""

from __future__ import annotations

import json
import os
import signal
import shutil
import selectors
import subprocess
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .bridge_values import lua_value
from .config import MOD_ROOT, REPO_ROOT


ENGINE_TEMPLATE = Path(__file__).with_name("engine_harness.lua")
BOOTSTRAP_TEMPLATE = Path(__file__).with_name("engine_bootstrap.java")


@dataclass(frozen=True)
class EngineOptions:
    item_types: tuple[str, ...]
    pz_root: Path | None = None
    instance: bool = False
    timeout_seconds: float = 300.0


@dataclass(frozen=True)
class EngineResult:
    rows: list[dict[str, Any]]
    metadata: dict[str, Any]


def find_pz_root(explicit: Path | None = None) -> Path:
    """Find the installed PZ root containing projectzomboid.jar."""

    candidates = [explicit] if explicit else []
    home = Path.home()
    candidates.extend((
        home / ".steam" / "debian-installation" / "steamapps" / "common" / "ProjectZomboid" / "projectzomboid",
        home / ".steam" / "steam" / "steamapps" / "common" / "ProjectZomboid" / "projectzomboid",
        home / ".local" / "share" / "Steam" / "steamapps" / "common" / "ProjectZomboid" / "projectzomboid",
    ))
    for candidate in candidates:
        if candidate is None:
            continue
        root = candidate.expanduser().resolve()
        if (root / "projectzomboid.jar").is_file():
            return root
    raise RuntimeError(
        "Project Zomboid install not found; set --pz-root to the directory "
        "containing projectzomboid.jar."
    )


def _link_or_copy(destination: Path, source: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    try:
        destination.symlink_to(source, target_is_directory=True)
    except OSError:
        shutil.copytree(source, destination)


def _core_root() -> Path | None:
    candidate = REPO_ROOT.parent / "psychopatzCore" / "Contents" / "mods" / "PsychopatzCore"
    return candidate if candidate.is_dir() else None


def _write_harness_mod(mod_root: Path, item_types: tuple[str, ...], instance: bool) -> None:
    source = ENGINE_TEMPLATE.read_text(encoding="utf-8")
    cases = [{"fullType": item_type} for item_type in item_types]
    source = source.replace("__MARKETSENSE_CASES__", lua_value(cases), 1)
    source = source.replace("__MARKETSENSE_INSTANCE__", "true" if instance else "false", 1)
    version_root = mod_root / "42.20"
    version_root.mkdir(parents=True, exist_ok=True)
    (version_root / "mod.info").write_text(
        "name=MarketSense Harness\n"
        "id=MarketSenseHarness\n"
        "description=Ephemeral MarketSense engine test runner.\n"
        "versionMin=42.20\n"
        "require=MarketSense\n",
        encoding="utf-8",
    )
    lua_path = version_root / "media" / "lua" / "server" / "MarketSenseHarness.lua"
    lua_path.parent.mkdir(parents=True, exist_ok=True)
    lua_path.write_text(source, encoding="utf-8")


def _compile_bootstrap(output_dir: Path) -> None:
    javac = shutil.which("javac")
    if not javac:
        raise RuntimeError(
            "--engine needs javac to compile its Java-version-neutral bootstrap."
        )
    output_dir.mkdir(parents=True, exist_ok=True)
    source_path = output_dir / "MarketSenseEngineBootstrap.java"
    source_path.write_text(BOOTSTRAP_TEMPLATE.read_text(encoding="utf-8"), encoding="utf-8")
    result = subprocess.run(
        [javac, "-d", str(output_dir), str(source_path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(f"could not compile PZ bootstrap: {result.stdout.strip()}")


def _terminate(process: subprocess.Popen[str]) -> None:
    if process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
        process.wait(timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        try:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=5)
        except (OSError, subprocess.TimeoutExpired):
            pass


def _read_result_file(
    path: Path,
    rows: list[dict[str, Any]],
    metadata: dict[str, Any],
    diagnostics: list[str],
) -> bool:
    """Read the Lua-side result file written through PZ's getFileWriter."""

    if not path.is_file():
        return False
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as error:
        diagnostics.append(f"could not read engine result file: {error}")
        return False
    finished = False
    for line in lines:
        if line.startswith("MSENGINE\t"):
            try:
                value = json.loads(line.split("\t", 1)[1])
            except json.JSONDecodeError as error:
                diagnostics.append(f"invalid engine file row: {error}")
            else:
                if isinstance(value, dict):
                    rows.append(value)
        elif line.startswith("MSENGINE_DONE\t"):
            try:
                value = json.loads(line.split("\t", 1)[1])
            except json.JSONDecodeError as error:
                diagnostics.append(f"invalid engine file metadata: {error}")
            else:
                if isinstance(value, dict):
                    metadata.update(value)
            finished = True
        elif line.strip():
            diagnostics.append(line)
    return finished


def run_engine(options: EngineOptions) -> EngineResult:
    """Run cases through the real PZ Lua/Java runtime and return JSON rows."""

    if not options.item_types:
        raise ValueError("at least one item type is required")
    pz_root = find_pz_root(options.pz_root)
    java = pz_root / "jre64" / "bin" / "java"
    if not java.is_file():
        java = Path(shutil.which("java") or "")
    if not java.is_file():
        raise RuntimeError("no Java runtime found in the PZ install or PATH")

    rows: list[dict[str, Any]] = []
    metadata: dict[str, Any] = {}
    diagnostics: list[str] = []
    with tempfile.TemporaryDirectory(prefix="marketsense-engine-") as temporary:
        temp_root = Path(temporary)
        cache_root = temp_root / "Zomboid"
        mods_root = cache_root / "mods"
        _link_or_copy(mods_root / "MarketSense", MOD_ROOT)
        core_root = _core_root()
        if core_root is not None:
            _link_or_copy(mods_root / "PsychopatzCore", core_root)
        _write_harness_mod(mods_root / "MarketSenseHarness", options.item_types, options.instance)
        _compile_bootstrap(temp_root / "bootstrap-classes")
        harness_lua = (
            mods_root
            / "MarketSenseHarness"
            / "42.20"
            / "media"
            / "lua"
            / "server"
            / "MarketSenseHarness.lua"
        )
        result_file = cache_root / "Lua" / "MarketSenseHarnessOutput.json"

        java_args = [
            str(java),
            "-Djava.awt.headless=true",
            "-Dzomboid.steam=0",
            "-Djava.library.path=./:./natives/",
            "-cp",
            f"{temp_root / 'bootstrap-classes'}:{pz_root / 'projectzomboid.jar'}",
            "MarketSenseEngineBootstrap",
            str(cache_root),
            str(harness_lua),
            "MarketSenseHarness",
        ]
        environment = os.environ.copy()
        native_dir = pz_root / "natives"
        if native_dir.is_dir():
            existing = environment.get("LD_LIBRARY_PATH", "")
            environment["LD_LIBRARY_PATH"] = ":".join(
                value for value in (str(native_dir), existing) if value
            )
        process = subprocess.Popen(
            java_args,
            cwd=pz_root,
            env=environment,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            start_new_session=True,
        )
        assert process.stdout is not None
        selector = selectors.DefaultSelector()
        selector.register(process.stdout, selectors.EVENT_READ)
        deadline = time.monotonic() + options.timeout_seconds
        finished = False
        try:
            while time.monotonic() < deadline:
                events = selector.select(max(0.1, deadline - time.monotonic()))
                if not events:
                    continue
                line = process.stdout.readline()
                if not line:
                    if process.poll() is not None:
                        break
                    continue
                line = line.rstrip("\r\n")
                if line.startswith("MSENGINE\t"):
                    try:
                        value = json.loads(line.split("\t", 1)[1])
                    except json.JSONDecodeError as error:
                        diagnostics.append(f"invalid engine row: {error}")
                    else:
                        if isinstance(value, dict):
                            rows.append(value)
                elif line.startswith("MSENGINE_DONE\t"):
                    try:
                        value = json.loads(line.split("\t", 1)[1])
                    except json.JSONDecodeError as error:
                        diagnostics.append(f"invalid engine metadata: {error}")
                    else:
                        if isinstance(value, dict):
                            metadata = value
                    finished = True
                    break
                elif line.strip():
                    diagnostics.append(line)
        finally:
            selector.close()
            _terminate(process)
            finished = _read_result_file(result_file, rows, metadata, diagnostics) or finished

        if not finished:
            if process.poll() is not None:
                detail = "\n".join(diagnostics[-20:])
                raise RuntimeError(
                    f"headless PZ exited with code {process.returncode}. {detail}"
                )
            raise RuntimeError(
                f"headless PZ timed out after {options.timeout_seconds:g}s. "
                + "\n".join(diagnostics[-20:])
            )

    metadata.setdefault("runtime", "pz-engine")
    metadata.setdefault("pzRoot", str(pz_root))
    metadata.setdefault("itemCount", len(options.item_types))
    metadata.setdefault("instance", options.instance)
    metadata.setdefault("bootstrap", "reflective ScriptManager + LuaManager")
    if diagnostics:
        metadata["diagnostics"] = diagnostics[-20:]
    return EngineResult(rows=rows, metadata=metadata)
