# MarketSense 42.20 subcategory and false-positive audit

**Audit date:** 2026-08-30  
**Scope:** MarketSense Lua classifier, its offline Python harness, base-game item definitions, and the currently discovered Workshop definitions.  
**Status:** Audit only. No Lua heuristic or Dynamic Trading changes were made for this report.

## Executive result

The current 42.20 real-Lua harness run evaluated **5,403 item definitions with 0 evaluation errors**. It produced 12 top-level MarketSense departments and 214 distinct hierarchy paths:

| Result | Count |
|---|---:|
| Obtainable | 4,471 |
| Uncertain acquisition status | 723 |
| Excluded by the acquisition gate | 209 |
| Review flags | 643 |
| Low-confidence rows (`< 0.50`) | 344 |
| Heuristic-gap candidates | 575 |

The most important conclusion is that the review count is not a false-positive count. The current review layer intentionally marks every `Misc` row, including the already-specialized `Misc > Memento > Memento` and `Misc > Junk > Junk` paths. That creates **293 specialized Memento/Junk warnings which are tooling noise**; the remaining Misc rows are the real general-bucket work queue. The reason histogram contains 299 standalone broad-Misc reasons because six of the generic rows are not also below the confidence threshold. The actionable generic paths are:

| Generic or root-only path | Items | Priority |
|---|---:|---|
| `Misc > General > General` | 169 | P0 |
| `Clothing > General > General` | 142 | P1; mostly excluded body-state/debug rows |
| `Container > General > General` | 66 | P0 |
| `Building > Moveable > Moveable` | 52 | P1 |
| `Tool > General > General` | 40 | P1 |
| `Weapon > General > General` | 39 | P0 |
| `Electronics > General > General` | 32 | P1 |
| `Building > Gardening > Gardening` | 22 | P1 |
| `Food > General > General` | 7 | P2 |
| `Literature > General > General` | 6 | P2 |

These are candidates for better signatures, not automatic proof that the items are invalid. The next implementation task should distinguish three cases: a valid item with a missing subcategory, a genuinely wrong department, and a non-market/debug definition that should remain gated out.

## Method and authority

The report was generated from a full scan using the real MarketSense Lua evaluator:

```text
PYTHONPATH=tools/src python3 -m marketsense_app --console --format json --availability all --chart none
```

The evaluator merges base-game and Workshop item definitions, builds acquisition evidence, emulates the PZ item/property surface, calls the Lua bridge, and compares static acquisition evidence with the Lua availability result. Each evaluated row reports the Lua classifier, hierarchy, resolver, price audit, source definition, and availability evidence. The scan output was retained as `/tmp/marketsense_full_audit.json` while producing this report.

The Lua path is authoritative for classification. The Python `review.py` and `heuristics.py` modules only add bounded review hints and must not be treated as a second classifier. This is important when a row is marked `REVIEW`: it means “inspect the evidence”, not “remove this item”.

The classifier currently resolves a root in `MS_RootArbiter.resolve`, runs the root-specific signature pipeline in `MS_Classifier.classify`, and converts the winning token into a nested hierarchy through `MS_TagMapper`. The current stage order is:

```text
static override
liquid -> material -> ammo -> medical -> food -> memento
-> container -> electronics -> building -> literature -> clothing
-> weapon -> tool -> Misc fallback
```

This ordering is generally sound. The remaining problems are primarily signature specificity and the review layer’s overly broad `Misc` warning.

## Department audit

“Generic/gap” is the count identified by the harness as a broad or root-only target. “Review” is the count produced by the current Python review rules. “Excluded” is an acquisition result and should not enter the market even if its classifier result looks plausible.

| Department | Total | Generic/gap | Low confidence | Review | Excluded | Audit disposition |
|---|---:|---:|---:|---:|---:|---|
| Building | 516 | 74 | 0 | 0 | 1 | Valid department; refine moveables and gardening residuals. |
| Clothing | 1,272 | 142 | 142 | 142 | 138 | Mostly gate/debug cleanup; inspect only obtainable residuals. |
| Container | 326 | 66 | 0 | 0 | 0 | Strong bag/liquid/box coverage; split general utility containers. |
| Electronics | 124 | 32 | 0 | 0 | 0 | Add functional subfamilies to the remaining appliance/general rows. |
| Food | 695 | 7 | 0 | 0 | 0 | Nearly complete; inspect seven generic ingredients. |
| Liquid | 73 | 0 | 0 | 0 | 3 | Best finalized department; retain separate liquid-from-container model. |
| Literature | 539 | 6 | 0 | 0 | 0 | Good coverage; resolve hollow-book residuals. |
| Medical | 88 | 0 | 0 | 0 | 34 | Department is specific; verify excluded/internal definitions stay gated. |
| Misc | 462 | 169 | 163 | 462 | 5 | Highest priority; separate review noise from true general items. |
| Resource | 525 | 0 | 0 | 0 | 27 | Good material coverage; six safe residual material rows remain. |
| Tool | 343 | 40 | 0 | 0 | 0 | Split general smithing, measuring, utility, and construction tools. |
| Weapon | 440 | 39 | 39 | 39 | 1 | Highest classifier priority; mixed improvised weapons/materials. |

### Building

The department is not broadly wrong. Its strongest existing paths are:

| Existing path | Count |
|---|---:|
| `Building > Furniture > Decor` | 92 |
| `Building > Gardening > SeedPacket` | 66 |
| `Building > Gardening > Seed` | 49 |
| `Building > Fixture > Lighting` | 43 |
| `Building > Furniture > Chair` | 32 |
| `Building > Furniture > Storage` | 22 |
| `Building > Furniture > Counter` | 21 |
| `Building > Survival > SleepingBag` | 20 |
| `Building > Survival > Tent` | 14 |
| `Building > Fixture > Plumbing` | 13 |

The residuals are `Building > Moveable > Moveable` (52) and `Building > Gardening > Gardening` (22). Moveable is a valid root, but it is not a useful final signature for pricing or downstream mods. The next pass should use the moveable’s world-object capabilities and name/function evidence to split appliance, laundry, lighting, furniture, recreation/fitness, survival, medical, logistics, and decorative items. Gardening residuals should be split into seed, seed packet, compost, fertilizer, pest control, and garden decor; a plantable seed should never be left at `Gardening` merely because it lacks a strong name match.

### Clothing

The main clothing slots are well covered: `Head` (145), `Top` (137), `Bottom` (115), protective legs (114), outerwear (81), jewelry (72), protective arms (72), underwear (64), and full body (48).

The 142 `Clothing > General > General` rows are not automatically 142 bad classifications. The current set is dominated by:

- `Base.F_Hair_Stubble`, `Base.M_Beard_Stubble`, and `Base.M_Hair_Stubble`;
- football, hockey, and shoulder-pad variants;
- wound and `ZedDmg_*` body-state definitions, most of which are excluded by acquisition evidence.

The correct action is to keep excluded body-state definitions out of the market and only create an apparel subcategory for obtainable shoulder-pad/protective variants if the base game treats them as inventory clothing. Do not lower the gate merely to make this bucket smaller.

### Container

Current strong paths include boxes (81), liquid vessels (50), backpacks (30), duffels (22), ammunition containers (18), bags (18), satchels (12), key rings (11), wearable ammunition (10), and fanny packs (6).

The 66 `Container > General > General` rows are the clearest missing-subcategory group. Names and definitions show several natural families:

- bags and sacks: `Bag_Dancer`, `Bag_Gunny`, `Bag_HideSack`, `Bag_Laundry*`, `Bag_TarpSack`, `Bag_TrashBag`, `Bag_TreasureBag`, grocery bags, paper bags, plastic bags, totes, and wheat sacks;
- cold storage: `Cooler`, `Cooler_Beer`, `Cooler_Meat`, `Cooler_Seafood`, and `Cooler_Soda`;
- medical kits: `FirstAidKit_Camping`, `FirstAidKit_Camping_New`, and `FirstAidKit_Military`;
- tool/seed containers: `ToolRoll_*`, `SeedBag`, and `SeedBag_Farming`;
- personal storage: `Handbag`, `Purse`, `Wallet*`, and `Lunchbag`;
- parcels and gifts: `Parcel_*` and `Present_*`;
- miscellaneous containers: `CookieJar`, `DiceBag`, `GemBag`, and `Garbagebag`.

Recommended child tokens are `ContainerBag`, `ContainerMedicalKit`, `ContainerCooler`, `ContainerToolRoll`, `ContainerSeedBag`, `ContainerWallet`, `ContainerParcel`, `ContainerGift`, and a documented residual `ContainerUtility`. The existing worn-slot detection for backpack, satchel, fanny pack, and bandolier should remain the higher-confidence path when it is available.

### Electronics

The department already detects appliances (59), lights (11), flashlights (7), generators (4), clocks (3), communicators (3), batteries (2), radios, transmitters, and laundry appliances. The 32 general rows should be split by capability rather than by name alone:

- communications/audio: radios, receivers, speakers, microphones, headphones, earbuds, phones, and amplifiers;
- control/sensing: remotes, timers, triggers, motion sensors, scanners, and alarms;
- power/components: power bars, electric wire, electronics scrap, batteries, and repair components;
- personal appliances: hair dryers and hair irons;
- display/entertainment: video games and related display devices.

This is the best example of why `capabilities`, `powerSource`, requirements, and world-object evidence should be retained in the signature result. A television or washing machine is not “Misc” merely because it is a moveable object; its powered behavior is a stronger semantic signal.

### Food

Food coverage is strong and has the most useful price-driving hierarchy. The largest paths are staple (199), canned (58), herb (51), baking (41), perishable (39), meat (34), seafood (29), candy (26), vegetables (21), bread (24), and boxed (24).

Only seven rows land in `Food > General > General`: `AnimalMilkPowder`, `Bitters`, `GravyMix`, `HopsDried`, `PancakeMix`, `NnC.OpiumPot`, and `NnC.OpiumPotForged`. The first five need ingredient/beverage/baking subcategories. The two NnC rows require a mod-specific decision; do not classify them from the `Opium` name alone when the definition’s food, drug, crafting, and market role evidence can be inspected.

### Liquid

Liquid is currently the cleanest department: 73 rows, no generic-path candidates, and no low-confidence rows. It has water, tainted water, juice, soda, milk, beer, wine, alcohol, syrup, fuel, dye, chemical, and medical paths. The three excluded rows should remain excluded.

The separate `Liquid` department is correctly decoupled from `Container`: a vessel is classified by `ContainerLiquid`, while a non-empty fluid payload is classified by `Liquid*`. This is the correct foundation for future per-liter pricing. Do not merge the two subsystems to reduce path count.

### Literature

Recipes (155), skill books (144), softcover (55), magazines (52), hardcover (46), junk literature (34), and maps (16) are already differentiated. The six general rows are hollow-book variants: `HollowBook`, `HollowBook_Handgun`, `HollowBook_Kids`, `HollowBook_Prison`, `HollowBook_Valuables`, and `HollowBook_Whiskey`.

These should be audited as either literature with a `HollowBook` child or a container/memento hybrid based on their actual use. The classifier already deliberately prevents the container signature from stealing hollow books, so this can be resolved with a narrow literature signature rather than a broad pipeline change.

### Medical

All 88 rows are under `Medical > FirstAid > FirstAid`, with 34 excluded by acquisition evidence. This is a broad leaf but not currently a heuristic gap because the department’s admission evidence is stable. The future refinement should use treatment effect, infection reduction, bandage power, and medical use requirements; it is not a priority for removing false positives from the current market universe.

### Misc

Misc contains 233 mementos, 60 junk items, and 169 general rows. The first two groups are already meaningful categories. They are nevertheless all marked `REVIEW` because `review_row()` currently adds `broad Misc bucket` whenever either the category or primary token is `Misc`.

This is a tooling false positive, not evidence that the 293 memento/junk items are misclassified. The review rule should eventually flag only `Misc > General > General` (and perhaps explicit root fallback), while leaving `Misc > Memento > Memento` and `Misc > Junk > Junk` clean.

The 169 general rows are a real work queue. Representative signals include:

| Candidate family | Examples | Likely next audit |
|---|---|---|
| Fire/light | `Candle*`, `Lantern_Hurricane*`, `Lighter*`, `Matches`, firestarter blocks | Tool, fire source, or resource |
| Fishing | `FishingHook*`, `FishingLine`, `FishingNet*`, `Bobber`, `JigLure`, `MinnowLure`, `Chum` | Tool/fishing or resource bait |
| Locks/navigation | `Padlock`, `CombinationPadlock`, `Key*`, `CompassDirectional` | Tool/security or navigation |
| Sports/recreation | `Baseball`, `Basketball`, `Football`, `GolfBall`, `PoolBall`, `Dart` | Recreation or improvised weapon only where supported |
| Household utility | `BathTowel*`, `DishCloth*`, `Mirror`, `Umbrella*`, `Extinguisher`, `InsectRepellent` | Survival, tool, medical/safety, or utility |
| Gases/chemicals | `Oxygen_Tank`, `BBQStarterFluid`, `CorrectionFluid`, lighter fluid | Resource/liquid/tool according to filled-state evidence |
| Weapon candidates | `ClosedUmbrella*`, pens, letter opener, plunger, chair/table legs | Weapon improvised only when the runtime weapon fields support it |
| NnC/Workshop content | `NnC.*`, mod-specific item families | Mod-specific signature or safe residual |

The `Misc` pass must be evidence-led. A substring rule that moves every item containing “weapon”, “fluid”, or “tool” will reintroduce the false positives this audit is intended to remove.

### Resource

Resource is already highly specific: butchering (141), metalworking (130), tailoring (70), chemical (59), construction (32), pottery (18), hardware (17), maintenance (14), stone (11), fire source (10), glass (7), carpentry (6), paper (3), and bundled material (1). There are no current heuristic-gap candidates. The six residual `Resource > Material > Material` rows are acceptable until a stable material-use signal is available.

### Tool

Smoking (108), mechanics (103), and cooking (51) are strong existing groups. The 40 general tool rows should be split using usage and requirement evidence into smithing/forge, measurement, construction, utility, fire-starting, fishing, and other tool families. The classifier already has the correct root admission for `Tool`; the missing work is leaf specificity, not department reassignment.

### Weapon

The existing melee hierarchy is healthy for blunt (92), small blunt (70), small blade (49), axe (45), spear (24), and long blade (11). Ammunition and firearms also have distinct paths. Spears are therefore detected in the current 42.20 scan; the remaining issue is the 39-row `Weapon > General > General` group.

That group is mixed and should not receive one blanket melee rule. It contains likely improvised weapons such as `BowlingPin`, `ChairLeg`, `FieldHockeyStick_Broken`, `LeadPipe`, `LongStick`, `Plank`, `TableLeg*`, and `WoodenStick*`, but also likely materials or parts such as `FlintNodule`, `IronBar`, `MetalBar`, `SteelBar*`, `Stone2`, `Sapling`, `Handle`, `LongHandle`, and `RailroadSpike`. Pens and letter openers need actual weapon/category fields before being admitted as weapons.

The next weapon signature should first use native `weaponCategories`, item type, damage/range, maintenance signals, and two-handed state. Only then should it use name/display evidence for an `Improvised` child. Material-bearing definitions must be claimed by the Resource root before weapon fallback can see them.

## False-positive taxonomy

| Finding | Classification | Correct handling |
|---|---|---|
| `Misc > Memento` and `Misc > Junk` marked `REVIEW` | Review-layer false positive | Narrow the review condition; do not change the Lua classifier. |
| Wound and `ZedDmg_*` clothing rows | Valid classifier result, invalid market candidate | Keep acquisition gate/exclusion; do not create market subcategories. |
| `Building > Moveable > Moveable` | Valid department, missing leaf | Add capability/world-object/function subcategories. |
| `Container > General > General` | Valid department, missing container family | Split by body slot, capacity/use, and name only as supporting evidence. |
| `Weapon > General > General` | Mixed true weapons and resource/parts | Use root precedence plus native weapon evidence; do not blanket-promote. |
| Low confidence `.20` root fallback | Confirmed lack of specific signature, not confirmed false positive | Add targeted signature or retain a documented residual. |
| 723 uncertain acquisition rows | Insufficient acquisition evidence | Keep out of the default obtainable market view until the gate can prove them. |

## Recommended implementation goal

### Goal

Finalize MarketSense’s nested item signatures for the current base game and hot-swappable Workshop set so that every obtainable item has a defensible department and useful subcategory, while excluded/debug/internal definitions cannot enter the market. Preserve MarketSense as an interface-only categorization layer; do not change Dynamic Trading.

### Work order

1. **P0 — review correctness and Misc/Weapon/Container triage**
   - Change the Python review report so specialized `Misc` children are not falsely warned.
   - Audit all 169 `Misc > General > General` rows and split only those supported by runtime/use evidence.
   - Split the 39 generic weapon rows into improvised melee, resource/part, tool, or a documented residual.
   - Split the 66 generic containers into bag, kit, cooler, parcel, wallet, tool roll, seed bag, and utility families.

2. **P1 — behavior-driven building, electronics, gardening, and tools**
   - Use capability, requirement, power-source, world-object, and moveable metadata.
   - Resolve the 52 generic moveables and 22 generic gardening rows.
   - Resolve the 32 generic electronics rows by function.
   - Resolve the 40 general tool rows by use/skill/requirement.

3. **P2 — small residual groups**
   - Resolve the seven generic food rows and six hollow-book literature rows.
   - Inspect only obtainable clothing general rows after excluded body-state rows are confirmed gated.
   - Leave stable Liquid, Medical, and Resource departments unchanged unless a new definition demonstrates a gap.

### Acceptance criteria

- No evaluation errors in the full 42.20 harness run.
- No excluded item appears in the default obtainable market result.
- Every new subcategory has a stable `TagMapper` parent chain and a documented purpose.
- Generic-path counts decrease without moving unrelated items into the wrong department.
- `Misc > Memento` and `Misc > Junk` no longer create review noise.
- Weapon/resource precedence is tested with improvised weapon candidates and metal/wood/stone material candidates.
- Moveable appliance, laundry, lighting, table/furniture, survival, and fitness fixtures have capability-based fixtures in the harness.
- Base-game and Workshop definitions are both covered; Workshop changes remain discoverable without changing Dynamic Trading.
- Lua smoke tests, Python self-tests, `pz_verify`, and `git diff --check` remain clean.

## Harness and GUI workflow for the next pass

Use the full universe during auditing so uncertain and excluded rows can be inspected:

```bash
cd /home/psychopatz/Zomboid/Workshop/MarketSense
PYTHONPATH=tools/src python3 -m marketsense_app --console --format json --availability all --chart none
PYTHONPATH=tools/src python3 -m marketsense_app --self-test
python3 tests/run_tests.py
```

In the GUI:

- use **All items** only while auditing the gate;
- use **Obtainable only** for the market-facing acceptance check;
- open **Heuristic gaps** for the 575 bounded candidates;
- filter by `Misc`, `Weapon`, `Container`, or a Workshop mod before inspecting rows;
- select a deepest item row and inspect runtime evidence before adding a Lua signature;
- treat `REVIEW` as an investigation queue, not a deletion list.

## Architecture and verification snapshot

The architecture audit of the current repository found 59 production files, 7 indexed tests, 25 subsystems, and a 97.2/100 production health score. The largest remaining refactor pressure is in the classifier/signature boundary (`Items`, `ItemsRegistry`, and `signatures`), which is consistent with this audit: the system is structurally healthy, but the broad residual signatures need controlled expansion.

The graph coverage check found no recorded parse gaps for the source paths used here. Several files are newer than the graph generation, so their source was read directly and the graph result is treated as best-effort structural evidence rather than proof of freshness.

This audit does not claim that all 575 candidates are false positives, nor that all 723 uncertain rows are invalid. It identifies the exact queues and the evidence required to resolve them safely in the next Lua implementation task.

## Source map

- Lua root arbitration: `Contents/mods/MarketSense/common/media/lua/shared/MarketSense/signatures/tags/MS_RootArbiter.lua`
- Lua pipeline and precedence: `Contents/mods/MarketSense/common/media/lua/shared/MarketSense/signatures/tags/MS_Classifier.lua`
- Nested category definitions: `Contents/mods/MarketSense/common/media/lua/shared/MarketSense/signatures/tags/MS_TagMapper.lua`
- Department signatures: `Contents/mods/MarketSense/common/media/lua/shared/MarketSense/signatures/tags/MS_Sig_*.lua`
- Runtime bridge/evaluator provenance: `tools/src/marketsense_app/bridge_runtime.lua` and `tools/src/marketsense_app/evaluation.py`
- Review flags: `tools/src/marketsense_app/review.py`
- Heuristic-gap triage: `tools/src/marketsense_app/heuristics.py`
- Acquisition evidence: `tools/src/marketsense_app/availability.py` and `tools/src/marketsense_app/workshop.py`
