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
tools/run.sh --console --category Food --availability all --chart none
tools/run.sh --console --heuristic-gap-chunk 2 --chunk-size 25
tools/run.sh --console --heuristic-gap-out /tmp/marketsense-gaps.json
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
    heuristics.py         # compact broad/default-bucket gap audit
    terminal.py            # readable terminal charts and ranked tables
    evaluation.py          # shared scan pipeline for console and GUI
    gui.py                 # Tk entry point and composed inspector class
    gui_widgets.py         # shared Treeview and form primitives
    gui_overview.py        # charts and overview summary
    gui_items.py           # nested item tree, search, and evidence
    lua_rules.py           # Lua-backed runtime blacklist/whitelist/override editor
    gui_audits.py          # review, runtime verification, and gap views
    runtime_comparison.py  # MS_Items parser and harness/runtime comparison
    gui_sandbox.py         # sandbox pricing editor
    gui_controller.py      # settings, discovery, scan lifecycle, exports
    cache.py               # invalidation-aware persistent result cache
    scan_scope.py          # conservative bounded category-audit prefilters
    preferences.py         # atomic GUI path/scan-setting persistence
    sandbox.py             # declarations, JSON recommendations, audit, persistence
    sandbox_defaults.json  # editable 42.20 Python-side category defaults
    availability.py        # acquisition evidence and obtainable-only gate
```

By default it scans the Steam Workshop `108600` directory and
`~/Zomboid/Workshop` when present. Use `--workshop-root` to provide an explicit
root. The GUI mod filter is populated by a metadata-only discovery pass; `All`
is the default and selecting a discovered mod uses its stable ID. The GUI also
has a `Category (scan)` scope (default `All categories`); `Food` is pruned
before availability indexing and Lua evaluation, then checked again against
the exact Lua category. Other category names remain exact output filters but
currently retain the full candidate universe until their source signals are
validated for safe pruning. The CLI `--mod` option remains a substring filter
for scripting and compatibility, while `--category Food` provides the same
bounded scope from the terminal.
The default game-version ceiling is `42.20`. Versioned Workshop mods
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
authority: it gates live PZ items before they enter MarketSense's
runtime registry/`MS_Items` cache using engine acquisition flags, recipe registries,
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

The GUI's Verify tab compares the complete harness result with the live PZ
`MS_Items` text cache. Point it at `~/Zomboid/Lua/MS_Items` (the default), then
choose Compare after a scan. It checks obtainable-item membership, raw tags,
taxonomy headers, generated base prices, and generated base stock, and lets you
save the complete mismatch report as JSON. `MS_Items` stores `basePrice`, not
the final lazy `GetPriceDetails` price; the report calls that distinction out
instead of treating the two stages as an error. When `MS_ItemsIndex.txt` is
present, the verifier follows its indexed file list—the same list loaded by
the runtime—and reports leftover unindexed text files as cache-hygiene issues.

The console and GUI also expose a bounded heuristic-gap work queue. It uses
Lua's detector/resolver/category provenance to find missing, broad, and
root-only classifications without treating every `root_fallback` resolver as
wrong. Specialized rows such as `MaterialButchering` remain clean. The
terminal shows only nonzero aggregate bucket counts plus one chunk; advance it
with `--heuristic-gap-chunk N` or export the complete evidence with
`--heuristic-gap-out PATH`. The GUI's Heuristic gaps tab adds search, signal
filtering, runtime evidence, and JSON/CSV export.

The emulator deliberately exposes the same Lua-facing method names used by the
mod (`getItemType`, `getTooltip`, `getDescription`, `getTags`, item stats,
`getAllItems`, `ScriptManager:FindItem`, and the fluid-container/primary-fluid
methods used by the Liquid taxonomy). Filled fluid rows also expose the
pending liquid utility heuristic; vessel capacity/name is not used as an
item-price anchor. It does not claim to reproduce PZ
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
MarketSense Lua sources, the Lua interpreter, and evaluator/parser code. GUI,
terminal, export, and heuristic-report changes do not invalidate the expensive
item evaluation; cached rows are rehydrated into those views. Use
`--refresh-cache`, `--no-cache`, or `--cache-dir PATH` to control it. The GUI
restores an exact cache entry at startup without scanning, and its normal Scan
button reuses that entry. `Refresh` explicitly invalidates/rebuilds the
current entry; source/settings changes automatically produce a new cache key.
The GUI scan defaults to all categories, but a selected category creates a
smaller master result and avoids evaluating unrelated definitions. Its
Availability, mod, Skip vanilla, and Max items controls are local view filters
over that cached scope, so changing them does not invoke Workshop discovery or
Lua again. Cache hits reuse the saved summary aggregates rather than scanning
all rows a second time for GUI presentation.
The Sandbox pricing tab also has `Audit definitions`, which reports live
declaration/value drift, stale generated options, and Python-only category
recommendations. Those recommendations are editable in
`src/marketsense_app/sandbox_defaults.json`; new stock multipliers default to
`1.0`. `Reset recommended` saves the catalog values to the selected sandbox
JSON and triggers a rescan, allowing invalid price defaults to self-heal in the
offline harness without editing generated Lua.

Liquid rows are included in the normal Items, heuristic-gap, diagnostics, and
JSON/CSV evidence views. The old per-litre editor and data table were removed
because they could not account for player utility, harmful state, mixture
uncertainty, vessel burden, or deterministic package yields. Liquid rows now
report the pending `liquid_v2_pending` evidence model until those anchors are
calibrated.
GUI paths and scan options are saved to
`tools/.config/inspector-settings.json`, with `--settings-config PATH` available
for another location; the selected sandbox JSON path is saved there too. The GUI exposes equivalent cache controls and a Clear
cache button. Its Diagnostics tab keeps a timestamped, bounded phase log for
cache lookup, Workshop/base discovery, availability indexing, Lua evaluation,
and cache writes. Completion shows summary metrics plus a small sample rather
than rendering every item row; Save JSON/CSV remains the complete export path.

Right-click a leaf item in the GUI Items tab to edit the standalone
`Contents/mods/MarketSense/common/media/lua/shared/MarketSense/Items/MS_RuntimeRules_Data.lua`
contract. The menu supports exact blacklist/whitelist membership, exact price,
exact tags, stock range, and removing one or all rules for that item. The tool
loads the existing file through the Lua interpreter, writes it atomically in a
readable form, and starts a background master re-scan; the changed Lua file is
part of the cache manifest, so the old result cannot be reused. The editor only
writes the MarketSense runtime-rules data contract.
