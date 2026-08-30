# MarketSense

Shared MarketSense runtime service for Project Zomboid mods.

MarketSense owns item taxonomy, availability detection, runtime rules, and price
evaluation as a standalone service for other Project Zomboid mods.

## In-game item test catalog

With PsychopatzCore enabled, open `Psychopatz Debug Hub` and launch
`MarketSense Item Catalog`. The catalog loads MarketSense's obtainable runtime
items, groups them by the expanded taxonomy (for example
`WEAPON/RANGED/AMMO`), and keeps each group collapsible. Selecting an item runs
the existing MarketSense debug evaluator so its price and eligibility can be
checked while scrolling through the complete available catalog. Use
`Generate MarketSense catalog` to force the live PZ runtime registry to
regenerate the catalog. The generated cache is stored at `Zomboid/Lua/MS_Items`;
the window then refreshes and reports the generated item/file counts and elapsed
milliseconds.

The offline inspector's `Verify` tab compares those runtime `MS_Items` files
against the harness result. Run the complete scan, confirm the runtime cache
directory (default `~/Zomboid/Lua/MS_Items`), and choose `Compare`; the report
checks item membership, tags, taxonomy, generated base price, and stock, with
JSON export for the full mismatch list.

## Offline inspector

The `tools` app scans Project Zomboid 42.20 item definitions and Workshop
metadata without starting the game. It runs the real MarketSense Lua evaluator
inside a PZ-shaped harness, so it does not modify native item categories or
start the game. By default it discovers the union of installed vanilla items
and Workshop items, merges matching Workshop definitions over their vanilla
definition, and passes the complete discovered universe to the pricing
evaluator/list. The GUI's `Skip vanilla`, mod, and availability controls are
fast filters over that cached result; they do not create a Workshop-only scan.
Use `--category Food` (or the GUI's `Category (scan)` control) to restrict the
expensive availability/Lua pass to one top-level category. The Food source hint
is conservative and the Lua result is checked exactly before it is returned;
other category names remain exact output filters until their source signals are
validated for safe pruning.

```bash
./tools/run.sh                 # Tk GUI
./tools/run.sh --console       # terminal report
./tools/run.sh --console --mod Bandits --chart categories
./tools/run.sh --console --confidence-threshold 0.65 --low-confidence-out /tmp/marketsense-low.jsonl
./tools/run.sh --console --sandbox-config tools/.config/sandbox-settings.json --chunk-size 25
./tools/run.sh --console --availability all --availability-chunk 2 --chunk-size 25
./tools/run.sh --console --category Food --availability all --chart none
./tools/run.sh --console --heuristic-gap-chunk 2 --chunk-size 25
./tools/run.sh --console --heuristic-gap-out /tmp/marketsense-gaps.json
```

The GUI's Items tab supports case-insensitive search across item IDs,
categories, primary/expanded tags, descriptions, resolver sources, Workshop
metadata, and definition lineage. Categories are native collapsible tree nodes;
the review filter can be combined with search.
The Scan settings mod filter is a combobox populated from detected Workshop
metadata. It defaults to `All`. `Category (scan)` defaults to `All categories`;
selecting `Food` bounds the expensive evaluator candidate set and gets its own
cache entry. Other category names still produce exact category-only output but
conservatively keep the full candidate universe until their source signals are
validated for pruning. The first scan builds the selected scope's cached
universe; the mod filter, `Skip vanilla`, `Availability`, and `Max items`
controls then filter that in-memory result instantly. Selecting a mod matches
its stable ID emitted by the Lua bridge, so it does not trigger another
Workshop/Lua scan. `Skip vanilla` remains an independent view control when
`All` is selected.
Selecting a leaf item opens the runtime evidence panel: the actual Lua
detector result, resolver source, category path, context variables, evaluator
provenance, and price balance audit are shown from the bridge output.
The Classification review tab lists explainable triage flags such as a broad
`Misc` bucket, a fallback resolver, low confidence, missing labels, or a
category/tag mismatch. A flag is a review hint, not proof of a false positive.
The Low confidence tab produces the complete lowest-confidence list and exports
JSONL/CSV containing the original item definition, runtime context, detector
evidence, and price audit. The Sandbox pricing tab reads the MarketSense 42.20
sandbox declarations, lets you edit overrides, and applies them to
`SandboxVars.MarketSense` inside the harness when you scan. Use `Apply & rescan`
to see price changes immediately; overrides persist in
`tools/.config/sandbox-settings.json` by default. `Audit definitions` compares
the live declarations with the current pricing data and the editable
`tools/src/marketsense_app/sandbox_defaults.json` catalog. The catalog exposes
new heuristic categories as Python-only harness options, defaults all new stock
multipliers to `1.0`, and contains repair values for invalid negative literature
additions. `Reset recommended` writes those catalog values to the sandbox JSON
and automatically applies them with a rescan; it does not modify generated Lua.

Liquid rows are currently shown through the normal item evidence and heuristic
diagnostics. The retired per-litre table/editor is intentionally absent while
the new utility model is calibrated; this prevents an unverified fluid anchor
from being mistaken for a market price. The pending model records measured
amount, capacity, primary amount, fill ratio, mixture state, fluid identity and
categories, player-effect evidence, vessel burden, and deterministic yield
evidence.

The Diagnostics tab shows a timestamped, bounded scan log: cache lookup,
Workshop discovery, vanilla discovery, availability indexing, Lua evaluation,
and cache-save phases are reported as they complete. The final diagnostic view
contains only summary metrics and a small row sample; use Save JSON/CSV for the
complete result. Exceptions append their traceback without replacing the phase
history.

Right-click any leaf item in the GUI Items tab to edit MarketSense runtime
rules. The editor writes exact blacklist/whitelist entries and per-item price,
tag, or stock overrides to
`Contents/mods/MarketSense/common/media/lua/shared/MarketSense/Items/MS_RuntimeRules_Data.lua`.
It reads the current Lua table with the Lua interpreter, preserves existing
rules, writes atomically, and automatically starts a background re-scan. Since
that file is included in the cache manifest, the changed rule is applied to the
new result instead of reusing stale rows. This is the standalone MarketSense
runtime contract.

The Heuristic gaps tab is the focused work queue for improving Lua detection.
It finds missing labels, broad/default primaries (`Misc`, `BuildingMoveable`,
`Gardening`, `Electronics`), and root-only category/primary pairs such as a
generic `Container` or `Tool`. It is provenance-based and deliberately labels
every result as a triage candidate, not a confirmed false positive. Search the
queue by item, mod, detector, resolver, or evidence, select a row for its full
runtime evidence, or export all candidates as JSON/CSV. The console prints only
aggregate nonzero bucket counts and one bounded candidate chunk; use
`--heuristic-gap-chunk N` or `--heuristic-gap-out PATH` for deeper inspection.

The Items tab defaults to `Obtainable only`. In the GUI this is a local view of
the complete cached Lua result; changing it does not rescan. The Lua mod
applies the actual gate before adding an item to the MarketSense catalog. The
standalone runtime cache is written to `MS_Items`. It uses live 42.20 PZ signals (`getObsolete`, `isHidden`,
`canSpawnAsLoot`, `isCraftRecipeProduct`, and `canBeForaged`), recipe registries,
and loaded runtime source tables for distribution/vehicle loot, foraging,
farming harvests, fishing catches, trapping, animal/butchering outputs, and
scripted providers. The Python harness only supplies PZ-shaped shims and
compares the Lua result against an independent source scan; it does not decide
market eligibility. A definition with no positive evidence is marked
`uncertain` and is omitted from the default market list; it is still visible
when Availability is changed to `All items`, `Uncertain only`, or `Excluded
only`. Selecting an item exposes its Lua channels, source references, and
exclusion reason.

The same gate is available as a scan-time option in the console with `--availability`. Use
`--availability all` to inspect the full evaluated universe; suspicious rows
are printed in bounded `AVAILABILITY FINDINGS` chunks. Use
`--availability-chunk N` to advance that section, or `--format json`/`--csv-out`
for complete machine-readable evidence. This is intentionally conservative
source evidence, not a claim that an item has a particular spawn probability.
The game can still gate a valid recipe or loot table by sandbox, skill, map, or
runtime conditions; the Lua mod remains the final authority in-game.

The terminal keeps these potentially large sections bounded: low-confidence,
heuristic-gap candidates, availability findings, and sandbox overrides are
printed in chunks. Use
`--low-confidence-chunk N` to inspect another chunk and
`--low-confidence-out PATH` to capture the complete list without putting every
row in the console/context. Use the corresponding heuristic-gap options for
the heuristic work queue.

Completed master scans are cached in `tools/.cache/results` by default. The cache key
includes scan settings (including category scope), Workshop/base item scripts, the base/Workshop Lua
acquisition sources, MarketSense Lua source, and the inspector source, so
changing inputs automatically invalidates stale results. The GUI attempts a
cache-only restore at startup and normal `Scan Workshop` reuses an exact hit;
it does not perform a three-minute scan just to restore the tabs. `Refresh`
forces the current key to be rebuilt, while `Clear cache` removes saved
results. The cache tracks evaluator/parser code; GUI, terminal, export, and
heuristic-report formatting changes reuse the saved evaluated rows. GUI paths and scan options are persisted in
`tools/.config/inspector-settings.json`. GUI view filters are not part of the
cache key, so changing them reuses the same master rows and only rebuilds the
visible tabs/charts.
