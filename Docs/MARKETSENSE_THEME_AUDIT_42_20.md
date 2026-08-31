# MarketSense 42.20 theme and descriptor audit

**Audit date:** 2026-08-30  
**Scope:** Theme, quality, rarity, origin, and semantic descriptor behavior across the current base-game and Workshop item universe.  
**Status:** Baseline audit for the implemented descriptor update. The findings below describe the pre-update behavior; the implementation result records the changes now applied.

## Executive result

The current 42.20 real-Lua run evaluated **5,403 definitions with 0 evaluator errors**. The descriptor layer emitted:

| Descriptor | Tagged rows | Main observation |
|---|---:|---|
| `Theme.*` | 559 | Only 10.3% of rows; exactly one theme is emitted per row. |
| `Quality.*` | 5,402 | One item override row (`Base.Katana`) loses the quality tag in the final pricing record. |
| `Rarity.*` | 5,403 | Common dominates; no `Rarity.Legendary` or `Rarity.UltraRare` is emitted by the current filter. |
| `Origin.*` | 5,402 | Provenance is mostly stable; `Base.Katana` also loses Origin in the final pricing record. |

The theme layer is currently lexical and mutually exclusive. It searches full type, item ID, display category, item type, body location, ammo type, display name, description, and raw item tags using substring matching. It does **not** currently use numeric insulation, wind resistance, armor values, fluid category, item capabilities, world-object behavior, or crafting requirements when assigning a theme.

That explains the most important findings:

- only **2** clothing rows have `Theme.Winter`, although **61** clothing rows have both insulation and wind resistance at or above `0.75`;
- **29** clothing rows receive `Theme.Survival` from the negative description token `tooltip_item_nobackpack`;
- **21** rows receive `Theme.Police` because `cop` is a substring of `Copper`, `Scope`, `Microscope`, or `Stethoscope`;
- **1** food row, `Base.Guacamole`, receives `Theme.Militia` because `camo` occurs inside `guacamole`;
- at least **125** weapon rows receive `Theme.Primitive` with `WeaponCrafted` as a direct display-category match, which is a construction cue rather than proof of a primitive theme;
- no row receives more than one theme, so a padded camouflage jacket can be Militia but not independently Winterized.

The next implementation should make environmental protection, pattern, institutional identity, construction method, and gameplay role separate facets. A single `Theme.*` slot is too lossy for both pricing and future mods.

## Implementation result

The descriptor layer now emits independent, evidence-backed facets instead of stopping at the first theme. Known false positives were removed or bounded: `cop` no longer drives Police, `camo` no longer matches Guacamole, no-backpack variants reject Survival, and `WeaponCrafted` alone no longer implies Primitive.

Added material/protection facets are `Theme.Leather`, `Theme.Denim`, `Theme.Wool`, `Theme.Silk`, `Theme.Cotton`, `Theme.Rubber`, `Theme.Canvas`, `Theme.Fur`, `Theme.Camouflage`, and `Theme.Thermal`. Matched fields, tokens, confidence, and rejected cues are exported to the resolver/debug catalog.

Rarity now prioritizes explicit rarity tags, then loot-distribution evidence from PZ `items = { name, weight, ... }` pairs, and only uses old name cues as a low-confidence fallback. Loot evidence records entry count, distribution-source count, raw weights, normalized local weight, and references. This is intentionally a relative rarity signal for a distribution list, not a claim of global spawn probability.

## Method and authority

The audit uses the retained full-universe result from:

```text
PYTHONPATH=tools/src python3 -m marketsense_app --console --format json --availability all --chart none
```

The evaluator merges base-game and Workshop definitions, builds an emulated PZ property context, invokes the actual MarketSense Lua bridge, and serializes the resulting descriptor tags. The relevant Lua sequence is:

```text
PropertyReader.buildContext
  -> AutoTag.generate
  -> Classifier.classify / item override
  -> PostLabelResolver
  -> Quality, Origin, Rarity, Theme filters
  -> TagUtils.expandHierarchy
```

The Python harness is used for observation and aggregation only. The Lua mod remains authoritative.

The baseline `Core.ctxContains` behavior performed case-insensitive substring checks over multiple context fields. Because it had no word-boundary or negation handling, terms such as `cop`, `camo`, `crafted`, and `backpack` could match unrelated words or negative tooltip keys. The updated theme filter uses bounded matching and emits independent facets.

## Current theme distribution

| Theme | Rows | Share of all rows | Category concentration |
|---|---:|---:|---|
| `Theme.Primitive` | 265 | 4.9% | Weapon 141, Clothing 48, Resource 32 |
| `Theme.Survival` | 84 | 1.6% | Building 32, Clothing 30, Misc 11 |
| `Theme.Militia` | 71 | 1.3% | Clothing 58, Resource 5 |
| `Theme.Combat` | 60 | 1.1% | Container 14, Clothing 23, Literature 7 |
| `Theme.Police` | 59 | 1.1% | Clothing 30, Container 10, Resource 5 |
| `Theme.Industrial` | 13 | 0.2% | Building 5, Electronics 4 |
| `Theme.Winter` | 7 | 0.1% | Medical 2, Clothing 2 |

There are **0 multi-theme rows**. The theme filter’s early return makes the following order authoritative when more than one cue exists:

```text
Combat -> Police -> Militia -> Survival -> Winter -> Industrial -> Primitive
```

This is a source of silent information loss. For example, `Base.Jacket_Padded_HuntingCamoDOWN` has strong thermal values and camouflage, but its output is only `Theme.Militia`.

## Theme false positives and coverage gaps

### Winter and thermal protection

The current filter recognizes only text cues (`winter`, `snow`, `cold`, `insulated`, and `thermal`). It never reads `ctx.insulation` or `ctx.windResistance`, even though `MS_PropertyReader` exposes both values.

| Clothing signal | Rows | Current `Theme.Winter` rows | Gap |
|---|---:|---:|---:|
| Insulation `> 0` | 820 | 2 | 818 not tagged Winter |
| Insulation `>= 0.75` | 92 | 2 | 90 not tagged Winter |
| Wind resistance `>= 0.75` | 90 | 2 | 88 not tagged Winter |
| Both insulation and wind resistance `>= 0.75` | 61 | 2 | 59 not tagged Winter |

The two current Winter clothing rows are `Base.Hat_WinterHat` and `Base.Hat_WinterHat_SheepSkin`. The other five Winter rows are `Base.Coldpack`, `Base.ColdpackBox`, `Base.SnowGlobe`, `Base.SnowShovel`, and `Base.WinterBerry`. These may be seasonally themed, but they should not be conflated with clothing thermal protection.

Recommended model:

- `Environment.Cold` or `Theme.Winter` for an explicit seasonal identity;
- `Protection.Thermal` or a numeric thermal evidence record for insulation/wind resistance;
- `Pattern.Camouflage` for visual concealment;
- `Role.Survival` for survival use.

Do not label every item with insulation as “winter clothing”. The numeric signal should create a separate, explainable thermal facet and can later feed price without changing the item’s main category.

### Camouflage and militia

There are 62 rows containing a `camo` cue, including 49 clothing rows. All 49 clothing rows receive `Theme.Militia`, which is a reasonable current result for the named camouflage garments. However, the same lexical rule also tags:

- `Base.Guacamole` as `Theme.Militia` because `camo` is inside `guacamole`;
- five makeup/camo resource items, three bags, three building rows, one liquid row, and one food row.

The clothing pattern should be split from institutional identity. A camo pattern can occur on a civilian bag, hunting clothing, military gear, face paint, or a mod item without proving “Militia”. The safest evidence order is explicit item/tag metadata, then a bounded token match such as `camo`, `camouflage`, or `tigerstripe`, then optional role inference from `hunter`, `ranger`, or `military`.

### Police substring collisions

The `cop` needle creates **21 false lexical matches**:

| Collision family | Examples | Why it is wrong |
|---|---|---|
| Copper | `CopperCup`, `CopperIngot`, `CopperOre`, `HotDrinkCopper`, `PastaPanCopper` | `cop` is inside `copper`. |
| Optics | `x2Scope`, `x4Scope`, `x8Scope` | `cop` is inside `scope`. |
| Instruments | `Mov_Microscope`, `Stethoscope` | `cop` is inside `microscope`/`stethoscope`. |
| Copper equipment | `Kettle_Copper`, `Lantern_Hurricane_Copper`, `SaucepanCopper` | Material is not police affiliation. |

The remaining police cues—`police`, `officer`, and `sheriff`—produce 38 rows and are generally plausible. The `cop` needle should be removed or changed to an explicit token/boundary rule.

### Survival negative-tooltip collisions

Twenty-nine clothing rows receive `Theme.Survival` because their description contains `tooltip_item_nobackpack` or `tooltip_item_scba_nobackpack`. These are shoulder pads, SCBA, and hazmat-related clothing; the token explicitly says the item does **not** use a backpack.

This is a high-priority false positive because `Theme.Survival` has a configured price addition and stock behavior. A negation-aware or field-specific matcher is required. Description localization keys that contain `no`, `not`, or `without` must not be treated as positive semantic evidence.

### Primitive and crafted

`Theme.Primitive` is the largest theme at 265 rows. At least 125 weapon rows directly match `displayCategoryLower == "weaponcrafted"`. This captures legitimate improvised weapons, but it also means the generic display category can assign Primitive without checking material, recipe, or construction evidence.

The current tag therefore mixes at least four concepts:

- genuinely primitive materials: stone, flint, bone, crude, burlap;
- improvised construction: crafted, scrap, nails, sawblade, tire;
- mod-defined `WeaponCrafted` display categories;
- items whose names merely contain one of those words.

Recommended split: `Construction.Primitive`, `Construction.Improvised`, and optionally `State.Crafted`. Keep `Theme.Primitive` only for a deliberate high-level theme if a downstream consumer still needs it.

## Descriptor audit across all departments

The table below counts rows with at least one theme tag in each department. The percentages show current theme coverage, not correctness.

| Department | Total | Theme-tagged | Coverage | Current dominant themes | Audit finding |
|---|---:|---:|---:|---|---|
| Clothing | 1,272 | 192 | 15.1% | Militia, Primitive, Police, Survival | Camo is useful, but thermal protection is almost entirely missed and `NoBackpack` is harmful. |
| Weapon | 440 | 151 | 34.3% | Primitive | Many crafted weapons are reasonable; do not treat every `WeaponCrafted` item as primitive. |
| Building | 516 | 44 | 8.5% | Survival, Industrial | Add capability/function facets for moveables instead of relying on names. |
| Container | 326 | 43 | 13.2% | Combat, Police, Survival | Theme may describe the vessel, not its liquid payload; preserve that distinction. |
| Resource | 525 | 47 | 9.0% | Primitive, Police, Militia | Copper and camo makeup collisions need correction. |
| Literature | 539 | 19 | 3.5% | Primitive, Combat | Military/primitive topic is useful, but should be derived from content/recipe evidence where available. |
| Misc | 462 | 19 | 4.1% | Survival, Primitive | General Misc remains a noisy source; theme tags do not repair its department. |
| Tool | 343 | 18 | 5.2% | Primitive, Survival | Use function/material/skill signals for tools. |
| Electronics | 124 | 11 | 8.9% | Primitive, Industrial | Powered behavior and appliance capability are stronger than theme text. |
| Food | 695 | 7 | 1.0% | Police, Militia, Winter | Five copper foods are Police false positives; Guacamole is Militia false positive. |
| Liquid | 73 | 5 | 6.8% | Combat, Industrial, Militia | Prefer fluid category and contents; do not price a liquid from its vessel’s theme. |
| Medical | 88 | 3 | 3.4% | Winter, Police | Coldpacks are seasonally cold, not winter clothing; Stethoscope is a Police collision. |

### Current cross-category examples

| Output | Likely interpretation |
|---|---|
| `Theme.Combat` on military bags, books, firearms, and armor | Often “military-associated”, not necessarily combat-capable. Consider `Role.Military` separately. |
| `Theme.Police` on police clothing and cases | Useful when the explicit token is `police`, `officer`, or `sheriff`; unsafe for `cop`. |
| `Theme.Militia` on camo clothing | Pattern evidence is good; militia affiliation is an inference and should be separate. |
| `Theme.Survival` on tents, hiking bags, and camping gear | Mostly useful, but polluted by `NoBackpack` descriptions. |
| `Theme.Industrial` on industrial appliances and sinks | Reasonable; validate against capabilities/power requirements. |
| `Theme.Primitive` on stone/flint/crude items | Useful when material evidence supports it; too broad for `WeaponCrafted`. |
| `Theme.Winter` on coldpacks and snowglobes | Seasonal cue is valid, but it is not the same facet as thermal insulation. |

## Quality, rarity, and origin findings

### Quality

Current distribution:

| Quality | Rows |
|---|---:|
| `Quality.Standard` | 5,110 |
| `Quality.Waste` | 178 |
| `Quality.Luxury` | 98 |
| `Quality.Sterile` | 16 |

Quality uses the same broad substring context search. `Waste` and `Luxury` are useful price descriptors but should eventually distinguish explicit item state from a word appearing in a tooltip or unrelated name. `Base.Katana` is the notable output exception: its item override preserves the rarity/weapon override but the final pricing tag record omits Quality and Origin. This should be checked when descriptor overrides are finalized.

### Rarity

Current distribution:

| Rarity | Rows |
|---|---:|
| `Rarity.Common` | 5,108 |
| `Rarity.Uncommon` | 157 |
| `Rarity.Rare` | 138 |
| `Rarity.Legendary` | 0 |
| `Rarity.UltraRare` | 0 |

Rarity is currently name-driven. The `Rare` needles include `military`, `generator`, `katana`, `machete`, `diamond`, `gold`, `hitech`, and `vintage`; `military` is an identity/role cue, not proof of scarcity. A future rarity pass should use acquisition frequency, loot/distribution evidence, explicit override data, and unique/legendary metadata before using names.

### Origin

Origin is the most deterministic descriptor because it is based on module/source identity rather than semantic substring matching:

| Origin | Rows |
|---|---:|
| `Origin.Vanilla` | 5,176 |
| `Origin.NnC` | 192 |
| `Origin.DTQuest` | 9 |
| `Origin.Bandits` | 8 |
| `Origin.WaybackRod` | 7 |
| Other discovered Workshop origins | 10 |

The `Origin.DTQuest` rows are merely present in the scanned universe; this audit does not modify or integrate Dynamic Trading. Origin should remain provenance, not a replacement for theme or gameplay role.

## Pricing impact

Theme descriptors are not cosmetic in the current configuration. For non-liquid items, `MS_Pricing` sends dotted descriptor tags to `Config.getSandboxTagMultiplier("Price", tags)`. The active sandbox/tag-price configuration contains:

| Tag | Current flat price addition |
|---|---:|
| `Theme.Combat` | 17 |
| `Theme.Industrial` | 15 |
| `Theme.Militia` | 20 |
| `Theme.Police` | 13 |
| `Theme.Primitive` | 7 |
| `Theme.Survival` | 20 |
| `Theme.Winter` | 15 |

Therefore the `NoBackpack`, `Copper`, `Scope`, `Guacamole`, and broad `WeaponCrafted` collisions can directly distort prices. Liquid rows now bypass these generic descriptor additions while their utility model is pending; fluid identity, amount, mixture, and player-effect evidence are shown separately.

There are currently two configuration concepts that should be reconciled before tuning theme prices:

1. `tag_price_additions` and `PriceTheme*Value` are used by the active sandbox price path;
2. `theme_additions` is loaded into runtime configuration but has no current consumer in the Lua source, and it omits `Combat`, `Survival`, and `Winter`.

Do not adjust both tables independently. Choose one authoritative theme-price contract in the implementation goal.

## Recommended implementation goal

### Goal

Replace the single lexical theme decision with a robust, multi-facet descriptor system that uses explicit fields first, numeric/runtime semantics second, and bounded name evidence last. Preserve existing main/subcategory classification and keep Dynamic Trading out of scope.

### Work order

1. **P0 — eliminate known false positives**
   - Remove or boundary-match `cop`.
   - Exclude negated tooltip tokens such as `nobackpack` from positive Survival evidence.
   - Prevent `camo` from matching `guacamole`.
   - Stop treating `WeaponCrafted` alone as proof of Primitive.

2. **P1 — introduce independent facets**
   - `Protection.Thermal` from insulation and wind resistance.
   - `Pattern.Camouflage` from explicit pattern evidence.
   - `Role.Military`, `Role.Police`, `Role.Survival`, and `Role.Industrial` from strong identity/function evidence.
   - `Construction.Primitive` and `Construction.Improvised` from material and recipe evidence.
   - Keep compatibility `Theme.*` only as a derived coarse label if needed.

3. **P2 — make the descriptor result auditable**
   - Expose `descriptorEvidence`, matched field, matched token, numeric thresholds, and rejected/negative cues.
   - Allow more than one facet while keeping one primary category.
   - Add a GUI filter for facet, evidence source, and confidence.
   - Keep liquid payload descriptors separate from container descriptors.

4. **P3 — reconcile pricing**
   - Select one active source for theme price additions and stock multipliers.
   - Give thermal protection and camouflage their own sandbox settings only after their false-positive rate is measured.
   - Add price audit entries that identify the exact descriptor contribution.

### Acceptance criteria

- Full 42.20 scan remains at 0 evaluator errors.
- `Base.Guacamole`, copper items, scopes, microscopes, and `NoBackpack` clothing no longer receive the unrelated descriptor.
- At least 59 of the 61 strongly thermal clothing rows expose thermal evidence; explicit Winter identity remains separate.
- A padded camouflage winter garment can expose both camouflage and thermal facets.
- `Theme.Primitive` is not assigned solely from `WeaponCrafted`.
- Descriptor matching records field/token evidence and rejects negated cues.
- No excluded item enters the default obtainable market output.
- Theme/descriptor price contributions are traceable in `priceAudit` and use one configuration source.
- Base-game and Workshop fixtures cover clothing, weapon, container, building/electronics, food, liquid, literature, medical, resource, tool, and Misc cases.
- Lua smoke tests, Python self-tests, `pz_verify`, and `git diff --check` remain clean.

## Reproduction and GUI workflow

```bash
cd /home/psychopatz/Zomboid/Workshop/MarketSense
PYTHONPATH=tools/src python3 -m marketsense_app --console --format json --availability all --chart none
PYTHONPATH=tools/src python3 -m marketsense_app --self-test
python3 tests/run_tests.py
```

In the GUI, inspect the full universe first, then filter by category and descriptor. The most useful initial searches are `Winter`, `camo`, `Copper`, `Scope`, `NoBackpack`, `WeaponCrafted`, and `Primitive`. Select the deepest item row and inspect runtime evidence before changing a Lua rule.

## Source map

- Theme generation: `Contents/mods/MarketSense/common/media/lua/shared/MarketSense/signatures/TagFilters/MS_filter_Theme.lua`
- Runtime loot evidence and rarity: `Contents/mods/MarketSense/common/media/lua/shared/MarketSense/MS_ItemAvailability.lua`
- Shared substring matching: `Contents/mods/MarketSense/common/media/lua/shared/MarketSense/MS_Core.lua`
- Context fields, insulation, wind resistance, and capabilities: `Contents/mods/MarketSense/common/media/lua/shared/MarketSense/MS_PropertyReader.lua`
- Descriptor application: `Contents/mods/MarketSense/common/media/lua/shared/MarketSense/MS_AutoTag.lua`
- Quality/rarity/origin filters: `Contents/mods/MarketSense/common/media/lua/shared/MarketSense/signatures/TagFilters/MS_filter_Quality.lua`, `MS_filter_Rarity.lua`, and `MS_filter_Origin.lua`
- Pricing application: `Contents/mods/MarketSense/common/media/lua/shared/MarketSense/MS_Pricing.lua`
- Sandbox descriptor lookup: `Contents/mods/MarketSense/common/media/lua/shared/MarketSense/MS_Config.lua`
- Descriptor defaults and active price additions: `Contents/mods/MarketSense/common/media/lua/shared/MarketSense/MS_HeuristicsDB.lua`, `Pricing/MS_PricingConfig_Data.lua`, `Pricing/MS_MarketModifiers_Data.lua`, and `Pricing/MS_SandboxOverrides_Data.lua`
- Offline evaluator provenance: `tools/src/marketsense_app/evaluation.py` and `tools/src/marketsense_app/bridge_runtime.lua`
