# MarketSense

Dependency for Dynamic Trading addon mod.

Contains generated runtime market rules and tag pricing additions consumed by DynamicTrading.

## Offline inspector

The `tools` app scans Project Zomboid 42.20 item definitions and Workshop
metadata without starting the game. It runs the real MarketSense Lua evaluator
inside a PZ-shaped harness, so it does not modify item categories or touch
DynamicTrading. By default it discovers the union of installed vanilla items
and Workshop items, merges matching Workshop definitions over their vanilla
definition, and passes only items with acquisition evidence to the pricing
evaluator/list. Use the GUI's `Skip vanilla` option for a Workshop-only scan.

```bash
./tools/run.sh                 # Tk GUI
./tools/run.sh --console       # terminal report
./tools/run.sh --console --mod Bandits --chart categories
./tools/run.sh --console --confidence-threshold 0.65 --low-confidence-out /tmp/marketsense-low.jsonl
./tools/run.sh --console --sandbox-config tools/.config/sandbox-settings.json --chunk-size 25
./tools/run.sh --console --availability all --availability-chunk 2 --chunk-size 25
```

The GUI's Items tab supports case-insensitive search across item IDs,
categories, primary/expanded tags, descriptions, resolver sources, Workshop
metadata, and definition lineage. Categories are native collapsible tree nodes;
the review filter can be combined with search.
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
`tools/.config/sandbox-settings.json` by default.

The Items tab defaults to `Obtainable only`. The Lua mod applies this gate
before adding an item to DynamicTrading's `MasterList` or persisting it in the
`DT_Items` cache. It uses live 42.20 PZ signals (`getObsolete`, `isHidden`,
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

The same gate is available in the console with `--availability`. Use
`--availability all` to inspect the full evaluated universe; suspicious rows
are printed in bounded `AVAILABILITY FINDINGS` chunks. Use
`--availability-chunk N` to advance that section, or `--format json`/`--csv-out`
for complete machine-readable evidence. This is intentionally conservative
source evidence, not a claim that an item has a particular spawn probability.
The game can still gate a valid recipe or loot table by sandbox, skill, map, or
runtime conditions; the Lua mod remains the final authority in-game.

The terminal keeps these potentially large sections bounded: low-confidence,
availability findings, and sandbox overrides are printed in chunks. Use
`--low-confidence-chunk N` to inspect another chunk and
`--low-confidence-out PATH` to capture the complete list without putting every
row in the console/context.

Completed scans are cached in `tools/.cache/results` by default. The cache key
includes scan settings, Workshop/base item scripts, the base/Workshop Lua
acquisition sources, MarketSense Lua source, and the inspector source, so
changing inputs invalidates stale results. Use `Refresh` or `Clear cache` when
needed.
