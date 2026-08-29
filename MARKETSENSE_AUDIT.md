# MarketSense audit

Date: 2026-08-29

## Scope

Audited the complete mod tree under `Contents/mods/MarketSense`, including the
pricing pipeline, property reader, classifier/signature pipeline, runtime cache,
registry persistence, public DynamicTrading API, and load hook. The architecture
scan covered 48 production files, 3 generated files, and 4 test files.

The mod remains interface-only with respect to item taxonomy: the implementation
reads the PZ item metadata and writes MarketSense/DynamicTrading records. The
audit found no category/tag setter calls against the underlying PZ item objects.

## Confirmed fixes

- Item descriptions are now read from live `InventoryItem:getDescription()` with
  script-item `Item:getTooltip()` fallback, normalized into the context, and used
  by food, packaging, container, cooking, ammo, and post-label heuristics.
- The property reader now recognizes current PZ method names including
  `Item:getItemType()`, `Item:getLevelSkillTrained()`, and the wind-resistance
  variants. Live inventory stats take precedence over script defaults.
- `GetPriceDetails` rejects invalid IDs and recalculates when an audit is
  requested after a non-audit result was cached.
- `GetRuntimeRules` now works on a fresh API load; registry `get` and
  `getAllKnown` methods are implemented and backed by copied catalog data.
- Kahlua-incompatible `table.unpack`, `next`, and `package.loaded` uses were
  removed. Registry timestamps now use Project Zomboid `getGameTime()` when
  available instead of sandboxed `os.date()`.

## Test and harness results

```text
python3 tests/run_tests.py
  marketsense_api_smoke: ok
  marketsense_runtime_smoke: ok

luac -p on all MarketSense Lua files
  passed

pz_verify
  Kahlua compatibility: 0 files, 0 errors

tools/run.sh --self-test
  10/10 checks passed through the real MarketSense Lua evaluator, including
  hierarchy, detector provenance, runtime variables, price audit, and a
  sandbox-to-price delta assertion

python3 tests/marketsense_tool_smoke.py
  marketsense_tool_smoke: ok

Tk GUI smoke
  initialized, scanned 10 Bandits-filtered items, and populated 2 category rows

Tk hierarchy/runtime-evidence smoke
  nested Food → NonPerishable → Canned → Base.CannedLeek, expanded Food
  recursively, found CannedLeek by search, and displayed context/detection/
  priceAudit evidence

Result cache smoke
  first scan produced a cache miss; identical second scan returned a cache hit

Base/Workshop availability audit
  42.20 base sources covered loot/distributions, recipes/evolved recipes,
  foraging, farming, fishing, trapping, animal/butchering, and scripted output
  paths; explicit Hidden/debug/internal markers are excluded
  full installed scan: 5,403 merged definitions, 4,471 obtainable rows,
  723 uncertain rows, 209 excluded rows, 0 Lua evaluation errors
  5,888 server/shared/scripts runtime source files scanned; Base.CannedLeek resolved through loot,
  crafting, and foraging evidence

python3 tools/marketsense_offline.py --chart prices --top 3
  80 selected Workshop mods, 4,471 obtainable items (4,065 vanilla + 406 Workshop)
  508 selected Workshop definitions over 5,105 vanilla definitions
  0 evaluation errors, 11 categories, 689 unique generated prices
  664 conservative classification review flags
```

The Java baseline harness verified the current methods used by the Lua reader:
`Item.getItemType()`, `Item.getTooltip()`, `Item.getLevelSkillTrained()`,
`InventoryItem.getDescription()`, and the clothing wind-resistance method.

## Tool maintainability follow-up

The offline harness is now a real Python package under `tools/src/marketsense_app`.
The former monolith remains only as a compatibility launcher. `tools/run.sh`
creates a local virtual environment and installs the dependency contract before
running it; with no arguments it opens the GUI, while arguments or
`--console` retain the terminal workflow. The current implementation
intentionally has no third-party Python dependencies. Discovery, evaluation,
reporting, terminal output, and the dedicated availability scanner are kept in
separate roles; the GUI is a cohesive presentation/controller module, and the
static `bridge_runtime.lua` template is intentionally larger because it
contains the complete PZ-shaped Lua compatibility surface.

Completed scan results are cached under `tools/.cache/results` by default. Cache
keys include scan settings, Workshop/base script metadata, MarketSense Lua
sources, and the Lua interpreter, so changed inputs invalidate old results.
The GUI adds a conservative review layer over those rows: it exposes the real
category, primary/expanded tags, resolver source, and an explainable review
reason without changing the evaluator result. Search covers those fields plus
descriptions, Workshop metadata, and definition lineage.
The Low confidence tab exports the complete threshold-filtered candidate list
as JSONL or CSV with the original definition, runtime context, detector
evidence, and price audit. Terminal reports print only bounded low-confidence
and sandbox-setting chunks; complete candidate data is written to a file on
request.
The Sandbox pricing tab parses all 173 MarketSense 42.20 sandbox declarations,
persists local JSON overrides, injects the effective settings into the Lua
bridge's `SandboxVars.MarketSense`, and exposes the applied runtime pricing
values in the summary. The previously empty 42.20 `sandbox-options.txt` was
restored with the declarations required by the translations and Lua config.
The Items tab is a native collapsible category tree. `Collapse all` closes
every category, `Expand Food` opens the Food group directly, and vanilla rows
are shown with `Base` in the mod column. Workshop patches are represented as
merged rows rather than duplicated item rows.
Selecting an item leaf also exposes the bridge's actual Lua evidence: context
variables from `PropertyReader.buildContext`, raw and final detector results,
`TagMapper.getDefinition` hierarchy, evaluator provenance, and the exact
`balanceAudit` steps used to reach the generated price.

## Availability gate

MarketSense now applies the obtainable-only gate inside the Lua mod before an
item can enter DynamicTrading's MasterList or the persisted `DT_Items` cache.
`MS_ItemAvailability.lua` reads live PZ item state (`getObsolete`, `isHidden`,
`canSpawnAsLoot`, `isCraftRecipeProduct`, and `canBeForaged`), scans the loaded
recipe registries, and observes the loaded 42.20 runtime source tables for
distribution/vehicle loot, foraging, farming harvests, fishing catches,
trapping, animal/butchering outputs, and scripted output providers. The Python
inspector only projects its independent source findings onto PZ-shaped shims so
the Lua result can be tested outside the game; it is not the market authority.

PZ distribution and some farming/trapping tables use bare item names. Lua
resolution is restricted to live ScriptManager items, an unambiguous known item,
or the preferred Base/mod module, so arbitrary strings do not become obtainable
evidence.

Strong negative markers are applied after positive evidence: hidden/debug/
internal categories, zombie-damage and wound/bandage overlays, debug/dummy/
placeholder names, explicit no-spawn/no-loot/no-drop flags, temporary testing
paths, and tooltips that say not to spawn/use. The output retains the evidence
channels, source line references, and exclusion reason for inspection. The
default `obtainable` list therefore excludes definitions with no acquisition
source and hard-excluded definitions. `all`, `uncertain`, and `excluded` modes
remain available for updating heuristics.

The harness's source scan is a conservative comparison against runtime
reachability. It does not infer spawn probability or prove that a recipe is
enabled under a specific skill/sandbox/map state; the actual Lua gate prevents
obvious internal/debug definitions from reaching a market catalog while
exposing uncertain rows for review. Availability source files are part of the
result-cache invalidation key.

## Remaining audit items

- The verifier still reports 14 hardcoded strings in
  `MS_ItemsRegistry_Shared.lua`; these are regex/JSON escape literals, not UI
  text, so they are checker false positives.
- Twelve production Lua files exceed the local 2,000-token warning threshold.
  This is maintainability debt, not a runtime failure. The offline Python tool
  itself has been split so the discovery, evaluator, reporting, and terminal
  service modules stay below that threshold.
- The new `tools/marketsense_offline.py` is an inspection harness, not a
  replacement for the missing prebuild/cache-generation workflow; it does not
  write the runtime `DT_Items` catalog.
- The server settings `buildCatalogOnBoot`, `allowLazyGeneration`,
  `cacheLazyItems`, and `verboseBootScan` are currently defaults without runtime
  consumers. They should either be wired into registry/pricing behavior or
  removed to avoid misleading configuration.
- The mock harness cannot prove the live PZ event order, Java collection bridge,
  or actual `getAllItems()`/file-I/O behavior. A final in-game server test should
  run the registry hook, inspect `console.txt`, and confirm a generated
  `DT_ItemsIndex.lua` is loaded by DynamicTrading.
