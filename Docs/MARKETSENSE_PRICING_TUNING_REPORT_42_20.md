# MarketSense pricing tuning report — 42.20

## Scope and evidence

This pass audited the obtainable MarketSense catalog against the canonical
Project Zomboid/Workshop item-script TXT definitions. The final scan covered
4,479 obtainable definitions across all active pricing roots; generated JSONL
was used only as an audit export and is not a runtime input.

Active root/subcategory coverage in that scan:

| Root | Active subcategories (items) |
| --- | --- |
| Building | Agriculture 6, Crafting 2, Display 1, Fixture 55, Funeral 2, Furniture 88, Garden 2, Gardening 144, Infrastructure 3, Logistics 1, Medical 2, Recreation 4, Survival 34, WallDecor 4 |
| Clothing | Accessory 183, Bottom 166, Footwear 39, FullBody 38, Hands 19, Head 93, Outerwear 72, ProtectiveGear 202, Top 133 |
| Container | Ammo 16, Bag 136, Box 40, Cooler 5, General 2, KeyRing 10, Liquid 41, MedicalKit 7, MementoOrContainer 1, Parcel 9, Personal 2, SeedBag 3, ToolRoll 1, Utility 2, Wallet 6, Wearable 11 |
| Electronics | Appliance 46, Audio 8, Battery 6, Communicator 11, Control 9, Entertainment 1, Generator 4, Light 18, Personal 2, Power 3, Radio 1, Transmitter 1 |
| Food | Beverage 4, NonPerishable 380, Perishable 265, Preserved 3 |
| Liquid | Alcohol 25, Beverage 2, Dairy 4, Fuel 2, Industrial 8, Juice 8, Medical 1, Soda 6, Water 9 |
| Literature | Adult 2, Brochure 1, Comic 2, Consumable 2, Flier 2, Hardcover 11, HollowBook 51, Magazine 51, Map 14, Newspaper 6, OrJunk 32, PictureBook 3, Recipe 154, RpgManual 1, SkillBook 144, Softcover 53 |
| Medical | FirstAid 54 |
| Misc | Animal 3, Entertainment 3, Fire 30, Fishing 11, General 2, Household 34, Junk 57, Memento 218, Navigation 1, Recreation 13, Safety 9, Security 6, Trapping 6, Utility 10 |
| Resource | Material 418 |
| Tool | Cooking 29, Craft 38, Farming 6, Gardening 1, Maintenance 7, Measurement 3, Mechanics 44, Smoking 109, Utility 11 |
| Weapon | Ammo 34, BrokenWeapon 5, Explosive 36, Firearm 21, Melee 308, Part 11 |

## Lua-side changes

- Replaced the generated pricing-config runtime load with module-owned Lua
  defaults. `reloadExported()` remains as a compatibility no-op for callers;
  the generated Lua table is audit/export-only.
- Removed the old global and per-root bundle price ceilings and invalidated old
  materialized registry pricing with heuristic version `26`.
- Rebalanced the Lua-owned crisis anchors: food `55`, liquid `20`, weapon `42`
  with ammo `8`, tool `26`, container `28`, medical `30`, electronics `28`,
  clothing `10`, literature `10`, resource `12`, building `12`, and a stronger
  neutral Misc baseline.
- Raised deterministic bundle valuation and retained a `0.60` quantity
  exponent so cartons/stacks remain discounted without flattening legitimate
  scarcity value. Ammo uses a separate lower per-round anchor to prevent
  nested carton prices from compounding unrealistically.
- Sealed canned/preserved food now receives emergency-ration treatment instead
  of the generic ingredient discount; candy receives a separate discretionary
  food multiplier.
- Removed the weapon reliability double-count: the legacy reliability field
  mirrors hit chance in the current context model.
- Tightened authority boundaries: empty equipment/power-source strings no
  longer count as positive evidence; building capacity requires world-object
  evidence; liquid water/fuel identity comes from fluid metadata rather than
  the inferred subtype name.
- Food opened-variant evidence now distinguishes explicit recipe/replacement
  relations from name-only `Open` hints. Strong relations may repair
  incomplete sealed metadata; name-only matches may fill missing fields but
  cannot overwrite canonical non-zero values. Authority, confidence, field
  sources, conflicts, and candidate provenance are retained.

## Distribution result

The same TXT-backed obtainable scan before/after the crisis rebalance produced:

| Population | Min | P05 | Median | P95 | Max |
| --- | ---: | ---: | ---: | ---: | ---: |
| Before | 2 | 12 | 21 | 60 | 450 |
| After | 7 | 17 | 33 | 77 | 1,051 |

Selected category results after tuning:

| Root | Items | P05 | Median | P95 | Max |
| --- | ---: | ---: | ---: | ---: | ---: |
| Food | 652 | 18 | 34 | 83 | 538 |
| Liquid | 65 | 30 | 34 | 72 | 82 |
| Container | 292 | 36 | 49 | 69 | 91 |
| Medical | 54 | 38 | 44 | 217 | 309 |
| Resource | 418 | 21 | 29 | 69 | 804 |
| Tool | 248 | 35 | 40 | 80 | 275 |
| Weapon | 415 | 49 | 69 | 119 | 1,051 |

The high end is now evidence-driven: large ammo and hardware cartons, boxed
food/wine, and the existing exact Katana override at `$450`; no global or
aggregate ceiling clips these values.

## Compatibility and invariants

- `sandbox-options.txt` was not modified; its working-tree SHA-256 remains
  `25d80353b306340dd242013ea162a9ba993dadf15b10346da1feea7b825aeab6`.
- Sandbox variable names and read semantics remain unchanged. Multipliers,
  contrast, variation, floors, and penalties are still applied through the
  existing Lua runtime path.
- Deferred/cooperative registry scheduling, runtime caches, and cache-only
  fallback behavior were preserved.
- Ambiguous probabilistic yields remain diagnostic/blocked rather than being
  converted into guessed package value.

## Verification

- `python3 tests/run_tests.py` — pass, including the new pricing-tuning smoke.
- `pz_verify --kahlua --severity ERROR` — 0 Kahlua errors/warnings.
- Full `pz_verify` still reports pre-existing hardcoded diagnostic strings and
  token-size findings outside this pricing pass; no Kahlua findings were
  introduced.
- `git diff --check` — pass.
