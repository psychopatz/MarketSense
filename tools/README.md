# Offline MarketSense app

The `tools` directory is a small standard-library Python application. It scans
Project Zomboid Workshop item scripts, applies the obtainable-only gate, creates
PZ-shaped Lua item objects, and runs the real MarketSense Lua pricing and
classification pipeline without launching the game.

From the MarketSense repository root, double-click `run.sh` or run it with no
arguments to open the GUI. It creates and reuses `tools/.venv`, installs
`requirements.txt`, and runs the package entry point:

```bash
tools/run.sh
tools/run.sh --max-items 500
tools/run.sh --mod Bandits --chart prices
tools/run.sh --format jsonl --max-items 100 > /tmp/marketsense-items.jsonl
tools/run.sh --csv-out /tmp/marketsense-items.csv
tools/run.sh --self-test
tools/run.sh --gui
tools/run.sh --gui --mod Bandits --game-version 42.20
tools/run.sh --console --self-test
tools/run.sh --console --refresh-cache --format json
tools/run.sh --console --confidence-threshold 0.65 \
  --low-confidence-out /tmp/marketsense-low.jsonl
tools/run.sh --console --low-confidence-chunk 2 --chunk-size 25
tools/run.sh --console --availability all --availability-chunk 2 --chunk-size 25
python3 tests/marketsense_tool_smoke.py
```

The old direct command remains supported for scripts and existing workflows:

```bash
python3 tools/marketsense_offline.py --self-test
```

For development, the canonical package invocation is also available without
installing the package:

```bash
PYTHONPATH=tools/src python3 -m marketsense_app --self-test
```

The application layout is intentionally role-based:

```text
tools/
  run.sh                  # venv/bootstrap wrapper
  pyproject.toml          # package metadata and console script
  requirements.txt        # dependency contract (stdlib-only today)
  marketsense_offline.py  # backwards-compatible launcher
  src/marketsense_app/
    cli.py                # argument parsing and orchestration
    workshop.py           # Workshop/vanilla definition discovery and merging
    workshop_paths.py     # Steam layouts and 42.20 version selection
    script_parser.py      # item-script parsing and normalization
    bridge.py             # data serialization and Lua subprocess I/O
    bridge_template.py     # packaged Lua template loader
    bridge_runtime.lua     # PZ-shaped runtime template
    fixtures.py           # deterministic real-evaluator checks
    reporting.py          # summaries and CSV support
    terminal.py            # readable terminal charts and ranked tables
    evaluation.py          # shared scan pipeline for console and GUI
    gui.py                 # Tk desktop inspector
    cache.py               # invalidation-aware persistent result cache
    sandbox.py             # sandbox declaration parsing, overrides, persistence
    availability.py        # acquisition evidence and obtainable-only gate
```

By default it scans the Steam Workshop `108600` directory and
`~/Zomboid/Workshop` when present. Use `--workshop-root` to provide an explicit
root. The default game-version ceiling is `42.20`. Versioned Workshop mods
load `common` plus the highest installed version folder at or below that
ceiling, matching PZ's `ZomboidFileSystem` selection rule. Override it with
`--game-version`. The tool also auto-detects the installed Project Zomboid
`media/scripts` tree so partial Workshop patches such as
`Base.Bacon { Tags = ... }` inherit vanilla stats before pricing. Use
`--no-base-game` to disable that merge. The terminal report includes category
counts, price ranges, price charts, top/bottom items, mod coverage, definition
lineage, duplicate definitions, and warnings for zero variation or
low-confidence results.

The Items tab and console default to `Obtainable only`. The Lua mod is the
authority: it gates live PZ items before they enter DynamicTrading's
`MasterList`/`DT_Items` cache using engine acquisition flags, recipe registries,
and loaded 42.20 runtime source tables. The harness projects its independent
source scan onto PZ-shaped shims and reports Lua-vs-static mismatches; Python
does not decide which items the mod registers. Definitions with no positive
source are marked `uncertain` and omitted from the default market list. Choose
`--availability all`, `uncertain`, or `excluded` (or the matching GUI option)
to inspect those definitions and their source-line evidence.

The console prints suspicious rows in bounded `AVAILABILITY FINDINGS` chunks;
use `--availability-chunk N` to advance that section. JSON/JSONL/CSV exports
include the channel, source references, confidence, and exclusion reason. This
is comparison evidence, not a spawn-probability calculation; normal game
conditions can still gate a valid recipe, distribution, or catch. The Lua
runtime gate is the final in-game decision.

DynamicTrading is intentionally not a required scan target: it consumes
MarketSense prices but does not need to define the items itself. Filtering to a
consumer-only mod therefore reports zero item definitions instead of treating
that as a harness failure.

The emulator deliberately exposes the same Lua-facing method names used by the
mod (`getItemType`, `getTooltip`, `getDescription`, `getTags`, item stats,
`getAllItems`, and `ScriptManager:FindItem`). It does not claim to reproduce PZ
mod load order or live Java inventory state; those remain final in-game checks.
`--self-test` runs deterministic synthetic food, medical, weapon, and container
fixtures through the real Lua evaluator and fails if categories, descriptions,
stats, or price variation stop working. `--gui` opens the desktop inspector;
it provides the same scan controls, category/price bar charts, item and mod
tables, diagnostics, and JSON/CSV export. The Low confidence tab exports every
row under the selected threshold, including the Lua detector/context/price
evidence needed to revise heuristics. The Sandbox pricing tab parses the
MarketSense 42.20 `sandbox-options.txt` and translations, persists local
overrides as JSON, and injects the effective values into `SandboxVars.MarketSense`
for the next scan. Results include the requested, applied, and effective Lua
pricing settings. `run.sh` with no arguments opens the GUI; the console remains
available through `--console` or normal report arguments. Results are cached by
default under `tools/.cache/results`; the cache key includes scan settings,
Workshop/base item-script metadata, base/Workshop Lua acquisition sources,
MarketSense Lua sources, and the Lua interpreter, including sandbox overrides
and declarations. Use
`--refresh-cache`, `--no-cache`, or `--cache-dir PATH` to control it. The GUI
exposes equivalent cache controls and a Clear cache button.
