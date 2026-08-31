# MarketSense subcategory implementation report — Project Zomboid 42.20

Date: 2026-08-30
Scope: `MarketSense` Lua classifier, TagMapper taxonomy, focused fixtures, and verification tooling.

## Outcome

The 42.20 subcategory pass is implemented without changing Dynamic Trading, public MarketSense APIs, pricing, availability authority, liquid/container separation, or the existing override/blacklist/whitelist behavior.

The final real-Lua scan evaluated 5,403 item definitions with zero evaluator errors. Availability was unchanged from the audit baseline: 4,471 obtainable, 723 uncertain, and 209 excluded. No excluded item was market-eligible.

## Implemented changes

- Added explicit parent chains in `MS_TagMapper.lua` for container families, food refinements, tool families, hollow books, gardening harvest/planter, electronics functions, and conservative Misc families.
- Tightened `MS_RootArbiter.lua` precedence:
  - material weapon-shaped stock is resolved as Resource before Weapon;
  - gardening tools are routed to Tool while plants, packets, sprays, and garden objects remain Building;
  - hollow books are routed to Literature before Container;
  - existing static, liquid, medical, food, memento, and override precedence remains intact.
- Added `MS_Sig_Misc.lua` with explicit evidence for fishing, security, navigation, fire, recreation, entertainment, trapping, animal, safety, household, and utility items. Mementos and sharpenable household tools are deliberately excluded from this broad signature.
- Added evidence-led refinements for containers, food, gardening, literature, electronics, tools, materials, weapons, and singular sport shoulder-pad body slots.
- Preserved explicit Workshop food results as `FoodModSpecific` so an icon such as `Pot_Rice` cannot relabel a mod recipe product as a vanilla staple.
- Narrowed the Python review warning to the actual broad Misc bucket; specialized Memento and Junk rows no longer create review noise.
- Added 17 real-Lua bridge fixtures plus `tests/marketsense_subcategory_smoke.lua`, including false-positive regressions for material-vs-weapon precedence, gardening tools, hollow books, mementos, sharpenable tools, and specialized containers.

## Before/after metrics

| Audit bucket | Before | After | Change |
|---|---:|---:|---:|
| `Misc > General > General` | 169 | 55 | -114 |
| `Weapon > General > General` | 39 | 0 | -39 |
| `Container > General > General` | 66 | 2 | -64 |
| `Building > Moveable > Moveable` | 52 | 1 | -51 |
| `Building > Gardening > Gardening` | 22 | 0 | -22 |
| `Electronics > General > General` | 32 | 0 | -32 |
| `Tool > General > General` | 40 | 9 | -31 |
| `Food > General > General` | 7 | 0 | -7 |
| `Literature > General > General` | 6 | 0 | -6 |
| `Clothing > General > General` | 142 | 137 | -5 |
| All listed generic paths | 575 | 204 | -371 |
| Review rows | 350 | 192 | -158 |
| Heuristic-gap candidates | 575 | 204 | -371 |

The remaining generic rows are bounded and intentionally conservative:

- 55 Misc rows are mostly N&CsNarcotics mod-specific content without a sufficiently safe shared subtype; 27 are obtainable and remain visible for a future mod-specific audit.
- The two generic containers are `Base.PhotoAlbum` and `Base.PhotoAlbum_Old`; their existing memento/category-override semantics are preserved.
- `Base.Moveable` is an uncertain generic placeholder.
- The nine generic Tool rows are uncertain `DTQuest` quest items and are left untouched to avoid inventing Dynamic Trading compatibility semantics.
- All 137 Clothing General rows are excluded body/debug-state definitions.

## Representative evidence-backed results

| Definition | Final path | Evidence/decision |
|---|---|---|
| `Base.IronBar` | Resource / Material / Metalworking | material display plus iron/bar-stock evidence wins over weapon-shaped fields |
| `Base.FlintNodule` | Resource / Material / Stone | material display and stone evidence |
| `Base.BowlingPin` | Weapon / Melee / SmallBlunt | native weapon category wins over `nomaintenancexp` |
| `Base.HandShovel` | Tool / Gardening / Gardening | sharpenable/dig-plow evidence routes a gardening weapon-shaped item to Tool |
| `Base.Scythe` | Tool / Farming / Farming | scythe/farming evidence |
| `Base.Remote` | Electronics / Control / Control | remote/control evidence |
| `Base.Amplifier` | Electronics / Audio / Audio | amplifier/audio evidence |
| `Base.Bellows` | Tool / Craft / Blacksmith | blacksmith tool evidence |
| `Base.MeasuringTape` | Tool / Measurement / Measurement | measurement tool evidence |
| `Base.HollowBook_Handgun` | Literature / HollowBook / Handgun | hollow-book tag and variant suffix |
| `Base.HollowFancyBook` | Literature / Hardcover / FancyBook | existing fancy-book semantics preserved |
| `Base.AnimalMilkPowder` | Food / NonPerishable / Dairy | named food evidence |
| `NnC.OpiumPot` | Food / NonPerishable / ModSpecific | Workshop recipe-product evidence; no icon-name relabeling |
| `Base.Shoulderpads_Football` | Clothing / ProtectiveGear / Arms | singular 42.20 body-slot evidence |

Every new taxonomy token has a valid `TagMapper` parent chain and the Lua signature result records a source/evidence reason. Pricing and stock remain downstream of the same resolved classification and runtime APIs; existing fixture checks cover sandbox price overrides, stock, liquid pricing, runtime variables, and API behavior.

## Verification

Passed:

- Real-Lua full scan: 5,403/5,403 evaluated, 0 errors; runtime/static availability matched 5,403/5,403.
- `PYTHONPATH=tools/src python3 -m marketsense_app --self-test`: 104/104 fixture rows, 29/29 checks.
- `python3 tests/run_tests.py`: all API, catalog UI, liquid pricing, runtime, and subcategory smoke tests passed.
- `PYTHONPATH=tools/src python3 tests/marketsense_tool_smoke.py`: passed.
- `git diff --check`: passed.

`pz_verify.py --mod-dir Contents/mods/MarketSense` reported zero Kahlua compatibility errors or warnings. It exits with its existing warning severity because it also reports 19 hardcoded diagnostic/regex strings across three files and 19 files over its token-bloat threshold; these are outside the requested subcategory change and were not altered.

## Deferred theme work

Theme descriptors remain deferred as requested. `MARKETSENSE_THEME_AUDIT_42_20.md` is preserved as the follow-up inventory; no theme descriptor taxonomy or Dynamic Trading compatibility code was changed in this pass.
