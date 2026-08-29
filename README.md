# MarketSense

Dependency for Dynamic Trading addon mod.

Contains generated runtime market rules and tag pricing additions consumed by DynamicTrading.

## Offline inspector

The `tools` app scans Project Zomboid 42.20 item definitions and Workshop
metadata without starting the game. It runs the real MarketSense Lua evaluator
inside a PZ-shaped harness, so it does not modify item categories or touch
DynamicTrading. By default it evaluates the union of installed vanilla items
and Workshop items; matching Workshop definitions are merged over their
vanilla definition. Use the GUI's `Skip vanilla` option for a Workshop-only
scan.

```bash
./tools/run.sh                 # Tk GUI
./tools/run.sh --console       # terminal report
./tools/run.sh --console --mod Bandits --chart categories
./tools/run.sh --console --confidence-threshold 0.65 --low-confidence-out /tmp/marketsense-low.jsonl
./tools/run.sh --console --sandbox-config tools/.config/sandbox-settings.json --chunk-size 25
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

The terminal keeps these potentially large sections bounded: low-confidence
rows and sandbox overrides are printed in chunks. Use
`--low-confidence-chunk N` to inspect another chunk and
`--low-confidence-out PATH` to capture the complete list without putting every
row in the console/context.

Completed scans are cached in `tools/.cache/results` by default. The cache key
includes scan settings, Workshop/base-script metadata, MarketSense Lua source,
and the inspector source, so changing inputs invalidates stale results. Use
`Refresh` or `Clear cache` when needed.
