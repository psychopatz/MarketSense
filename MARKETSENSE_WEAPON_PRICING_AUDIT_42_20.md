# Market Sense weapon pricing and category audit — Project Zomboid 42.20

**Audit date:** 2026-08-30  
**Scope:** vanilla weapon-like item definitions, the current Market Sense Lua evaluator, and the offline Python/Lua harness.  This is a research document only; no Lua pricing behavior was changed during this pass and Dynamic Trading was not touched.

## Executive result

The weapon system needs two separate concepts before its price can be made reliable:

1. **Mechanical class:** what the item does in the combat engine — spear, axe, small blade, firearm, explosive, and so on.
2. **Market role:** what the item primarily serves outside combat — cooking, gardening, tool work, fishing, household use, material use, memento, or a secondary combat role.

The current evaluator sometimes treats the second concept as a replacement for the first. That makes the output difficult to audit and causes valid combat evidence to disappear from the category path. A future item record should preserve both, for example:

```text
domain: Weapon
combatClass: Spear
marketRoles: [Household]
state: [Usable]
evidence: [Categories=base:spear, displayCategory=HouseholdWeapon]
```

The most important measured findings are:

- The installed 42.20 scripts contain **5,092 unique base item definitions** from **15 item-script files**; the parser saw **5,105 raw definitions** before duplicate/patch consolidation.
- **420 definitions** are weapon-like: **409 `base:weapon`** items and **11 `base:weaponpart`** items.
- **354/420** expose `weaponCategories`; **409/420** expose damage, range, and hit-count data; **408/420** expose `conditionMax`.
- The native categories contain **29 spear**, **45 axe**, **14 long-blade**, and **1 unarmed** definition. The current final labels retain all 45 axes and 9 long blades, but only **24/29 spears** remain `WeaponSpear`; five umbrellas are deliberately rerouted to `Misc` by the post-label resolver.
- All **22 firearm-like definitions** currently finish as `Ammo`, including 20 real firearms and two cap-gun/memento items. They therefore receive the ammunition pricing branch instead of a firearm anchor.
- The current static weapon price formula uses damage, range, max hits, max condition, weight, and coarse bonuses. It does **not** use current condition, swing time, critical chance, reload time, jam chance, recoil, knockdown, pushback, tree/door damage, or character skill.
- The current `PropertyReader` stores a field named `reliability`, but it is actually the first available value from `getHitChance` or `getAimingTime`. Those are different concepts and should not share one field.
- The base-game script key is `TwoHandWeapon` while the offline bridge looks for `twoHandWeapon`; the real Java runtime exposes `InventoryItem.isTwoHandWeapon()`. This prevents correct rifle/shotgun separation in the present harness and is also a warning for the live reader.

The current generated medians are useful for spotting anomalies, but are **not approved economic anchors** until the firearm routing and multi-role model are corrected.

## Method and evidence

The audit used three sources of evidence:

### Installed Project Zomboid 42.20 definitions

The local game installation was scanned at:

```text
/home/psychopatz/.steam/debian-installation/steamapps/common/ProjectZomboid/projectzomboid/media/scripts
```

The weapon definitions are primarily in:

```text
media/scripts/generated/items/weapon.txt
media/scripts/generated/items/weaponpart.txt
```

The Python parser consolidated inherited/duplicate item definitions in the same way the existing tool uses for vanilla discovery. Counts in this document refer to those consolidated definitions unless explicitly called “raw”.

### Actual Market Sense Lua

The audit executed the current Lua modules rather than cloning their behavior in Python:

- `Contents/mods/MarketSense/common/media/lua/shared/MarketSense/MS_PropertyReader.lua`
- `Contents/mods/MarketSense/common/media/lua/shared/MarketSense/MS_Pricing.lua`
- `Contents/mods/MarketSense/common/media/lua/shared/MarketSense/signatures/tags/MS_RootArbiter.lua`
- `Contents/mods/MarketSense/common/media/lua/shared/MarketSense/signatures/tags/MS_Classifier.lua`
- `Contents/mods/MarketSense/common/media/lua/shared/MarketSense/signatures/tags/MS_Sig_Ammo.lua`
- `Contents/mods/MarketSense/common/media/lua/shared/MarketSense/signatures/tags/MS_Sig_Weapon.lua`
- `Contents/mods/MarketSense/common/media/lua/shared/MarketSense/signatures/tags/MS_PostLabelResolver.lua`
- `Contents/mods/MarketSense/common/media/lua/shared/MarketSense/ItemsRegistry/MS_ItemsRegistry_Build.lua`
- `Contents/mods/MarketSense/common/media/lua/shared/MarketSense/ItemsRegistry/MS_ItemsRegistry_Shared.lua`

The price call path is:

```text
Build.collectGeneratedItems
  -> Shared.getBasePrice
    -> Pricing.calculateRawScore
```

The offline bridge is `tools/src/marketsense_app/bridge_runtime.lua`. It supplies a PZ-shaped item object, then invokes the same Market Sense Lua reader, classifier, hierarchy generator, and price calculation. It is an emulator, not proof that every Java-side runtime value is available.

### Java runtime ground truth

The decompiled 42.20 Java baseline was used only to verify API semantics:

- `zombie.inventory.types.HandWeapon.getMinDamage()` returns the minimum damage.
- `HandWeapon.getMaxDamage()` can adjust the script maximum using sharpness.
- `HandWeapon.getMaxRange(IsoGameCharacter owner)` can add an aiming-perk-dependent modifier for ranged weapons.
- `HandWeapon.getMaxHitCount()`, `getHitChance()`, `getAimingTime()`, `getCriticalChance()`, `getReloadTime()`, and `getJamGunChance()` are separate runtime properties.
- `InventoryItem.getCondition()` returns current condition and `getConditionMax()` returns the maximum.
- `InventoryItem.isTwoHandWeapon()` returns the script item’s `twoHandWeapon` value.
- `Item.getWeaponCategories()` returns the native weapon-category set.

The Java source was read from the local decompiler baseline at:

```text
/home/psychopatz/Desktop/Projects/ZomboidDecompiler/output/source
```

The graph coverage for the cited Market Sense files had no recorded parse gaps. The Java project is a best-effort decompiler baseline, so runtime claims should still be confirmed against the actual game build when a live bridge is available.

## Vanilla weapon inventory

### Native mechanical categories

The counts below are overlapping category memberships; an item can be both `Improvised` and `Spear`, for example.

| Native `weaponCategories` token | Definitions |
|---|---:|
| `base:improvised` | 129 |
| `base:smallblunt` | 98 |
| `base:blunt` | 96 |
| `base:smallblade` | 59 |
| `base:axe` | 45 |
| `base:spear` | 29 |
| `base:longblade` | 14 |
| `base:unarmed` | 1 |

The important implication is that `Improvised` is a modifier-like mechanical label, not a complete economic class. Most improvised items also have a more specific combat category. The classifier should use the specific combat class as the anchor and retain `Improvised` as an orthogonal trait.

### Display-category purpose signals

`displayCategory` is not a pure combat taxonomy. It provides useful evidence about the player-facing purpose of a weapon-like item.

| Display category | Definitions | Likely market role |
|---|---:|---|
| `WeaponCrafted` | 115 | crafted/improvised combat item |
| `ToolWeapon` | 53 | tool with combat fallback |
| `Weapon` | 44 | primary combat item |
| `CookingWeapon` | 32 | cookware or kitchen implement |
| `MaterialWeapon` | 22 | material/component that happens to be weapon-like |
| `HouseholdWeapon` | 19 | household utility or improvised defense |
| `SportsWeapon` | 17 | sports item with combat behavior |
| `GardeningWeapon` | 17 | farming/gardening tool |
| `InstrumentWeapon` | 10 | musical instrument with blunt behavior |
| `AnimalPartWeapon` | 7 | bone/animal-part weapon |
| `JunkWeapon` | 18 | low-purpose or damaged-looking utility item |
| `FishingWeapon` | 4 | fishing tool with combat behavior |
| `VehicleMaintenanceWeapon` | 1 | vehicle-maintenance tool |
| `FirstAidWeapon` | 1 | medical implement with weapon behavior |
| `Explosives` | 33 | explosive device; its own root subtype |
| `WeaponPart` | 11 | attachment/component; not a wielded weapon |
| `BrokenWeapon` | 6 | damaged state overlay |
| `Memento` | 6 | display/collectible item; some are weapon-shaped |

This validates the need for multi-axis tagging. The vanilla data intentionally contains objects such as knives, pans, shovels, pens, fishing rods, umbrellas, and instruments whose combat fields coexist with another stronger player-facing purpose.

## Current classifier audit

### What currently works

- `MS_RootArbiter.weaponRoot` recognizes a weapon from positive damage, native weapon categories, weapon loot type, explosives, weapon parts, or weapon item type.
- `MS_Sig_Weapon` normalizes namespaced category values such as `base:spear` and checks native categories before using the name/tag fallback.
- The current exact category pass correctly retains all **45 axes** and **9 long blades** as those final combat labels.
- All **33 explosive definitions** finish as `WeaponExplosive`.
- All **11 weapon parts** finish as `WeaponPart`.
- The six `BrokenWeapon` display-category definitions remain `BrokenWeapon`, which is appropriate as a state/purpose overlay.

### What currently obscures valid weapon evidence

The current final-label matrix is:

| Audit class | Current final primary | Count | Interpretation |
|---|---|---:|---|
| Firearm-like | `Ammo` | 22 | Defect: firearm evidence is being captured by the ammo branch |
| Spear category | `WeaponSpear` | 24 | Correct mechanical label retained |
| Spear category | `Misc` | 5 | Deliberate umbrella reroute; combat evidence is hidden from the final path |
| Small blade | `WeaponSmallBlade` | 40 | Combat label retained |
| Small blade | `Cooking` | 15 | Market role wins over combat class |
| Small blade | `Tool`/`Gardening` | 4 | Market role wins over combat class |
| Small blunt | `WeaponSmallBlunt` | 68 | Combat label retained |
| Small blunt | `Tool` | 23 | Tool role wins over combat class |
| Small blunt | `Cooking`/`ContainerLiquid` | 6 | Kitchen/liquid role wins over combat class |
| Blunt | `WeaponBlunt` | 87 | Combat label retained |
| Blunt | `Tool`/`Memento` | 9 | Utility/collectible role wins over combat class |
| Improvised-only | `Tool`/`Memento`/`WeaponCrafted` | 12 | Improvised is not exposed as a dedicated final class |
| Unarmed | `Weapon` | 1 | No dedicated unarmed leaf |

The five umbrellas are especially useful for demonstrating the design issue. The weapon signature correctly produces `WeaponSpear`, but `MS_PostLabelResolver` sees “umbrella” and reroutes the final label to `Misc`. That may be reasonable for a single market list, but it is not safe as the shared item signature because consumers may need both facts:

```text
combatClass = Spear
marketRole  = Household
```

The same pattern explains why kitchen knives and pans are not necessarily detector false positives. They are weapon-like in the PZ combat model while being more valuable to the player as cooking equipment. The output should expose both instead of forcing the audit to infer what was discarded.

### Confirmed firearm routing defect

The weapon root pipeline is ordered as:

```text
Ammo -> Weapon -> BoxesAndStacks -> CategoryOverride
```

`MS_Sig_Ammo` attempts to exclude firearms with a local exact tag check, but it only checks `ctx.normalizedTags["firearm"]`. The normalized vanilla tag is `basefirearm`, and the weapon signature has a namespace alias while the ammo signature does not. The firearm rows also have an `ammoType`, so they still satisfy the generic ammunition test.

Measured result:

- 20 real firearms with display category `Weapon` become `Ammo`.
- `Base.Revolver_CapGun` and `Base.Rifle_CapGun` have `Memento` plus `FakeWeapon` evidence and also become `Ammo`; they should be treated as non-combat mementos or as a clearly marked fake firearm subtype.
- Their current prices are only **78–99**, with a median of **82**, because they enter the ammo pricing branch.

This is a high-priority correction for the next Lua pass. The fix should preserve the root as `Weapon`, but classify the item as a firearm subtype before generic ammo. Ammunition itself should be identified from its ammo display/category/type evidence, not merely from the presence of an ammo relationship on a firearm.

### Two-hand and firearm subtype evidence

The installed script uses the key `TwoHandWeapon = true`. The current offline bridge exposes `isTwoHandWeapon` by reading the lower-case property `twoHandWeapon`, so it returns false for static script definitions. The current `PropertyReader` also asks the script item for `isTwoHandWeapon`, while Java ground truth exposes the method on `InventoryItem`.

This matters because the current weapon signature intends to use two-hand state to split:

- shotgun versus rifle, using shell/slug/ammo/name evidence;
- rifle versus handgun, using two-hand state.

The next reader/bridge implementation should either normalize script keys case-insensitively or read the temporary/runtime `InventoryItem.isTwoHandWeapon()` value. It should also preserve evidence such as `RequiresEquippedBothHands` and `IsAimedHandWeapon` when available.

## Current price model

For a final `Weapon` root, the current configured formula is effectively:

```text
avgDamage = (minDamage + maxDamage) / 2
score = 18
      + avgDamage * 28
      + maxRange * 4
      + maxHitCount * 10
      + conditionMax * 2.2
      - actualWeight * 1.4
      + coarse subtype bonus
```

The code fallback weight penalty is `2.4` when the category configuration is absent; the current `Weapon` configuration supplies `1.4`. Ammunition resets the score to an ammo-specific base calculation. Firearms, explosives, parts, and ammunition then receive coarse bonuses when their tags survive classification.

The base price path rounds and clamps this result through `Shared.getBasePrice`. The current weapon configuration has a price ceiling of `1e30`, which is effectively no ceiling for a market. A later implementation should set a meaningful global/category ceiling or use a robust percentile/outlier clamp.

### Current generated price distributions

The following are **diagnostic outputs from the current evaluator**, grouped by independent audit class rather than trusting the current final primary. Format is `count / minimum / median / maximum`.

| Audit class | Current generated price distribution | Status |
|---|---:|---|
| Improvised | 12 / 30 / 66 / 88 | provisional; mementos/tools contaminate it |
| Small blade | 59 / 38 / 110 / 170 | provisional; cooking/tools are mixed in |
| Small blunt | 97 / 74 / 122 / 265 | provisional; cookware and tools are mixed in |
| Axe | 45 / 127 / 150 / 194 | strongest current melee anchor candidate |
| Blunt | 96 / 29 / 146 / 197 | provisional; utility/memento outliers present |
| Spear | 29 / 30 / 146 / 155 | provisional; umbrellas create the low tail |
| Long blade | 9 / 177 / 201 / 450 | useful shape, but Katana is a major outlier |
| Unarmed | 1 / 83 / 83 / 83 | not a meaningful sample |
| Firearm-like | 22 / 78 / 82 / 99 | invalid anchor until firearm routing is fixed |
| Explosive | 33 / 143 / 171 / 180 | separate device class; do not mix with melee |
| Weapon part | 11 / 86 / 87 / 100 | attachment class; separate from wielded weapons |
| Broken weapon | 6 / 86 / 138 / 154 | state/condition class; not a base class |

The current numbers show why a simple “one base price per `Weapon`” approach will not balance the market. Long blades and firearms require separate anchors, while cooking knives and household tools need role-aware treatment.

## Available weapon evidence and pricing relevance

### Static definition fields

| Evidence | Coverage in 420 weapon-like definitions | Pricing use |
|---|---:|---|
| `minDamage` / `maxDamage` | 409 | damage capability; static baseline |
| `maxRange` | 409 | reach/range baseline |
| `maxHitCount` | 409 | multi-target potential; needs normalization |
| `conditionMax` | 408 | durability capacity, not current state |
| `actualWeight` | 420 | portability/encumbrance penalty |
| `weaponCategories` | 354 | strongest mechanical class evidence |
| `ranged` | 22 | firearm/ranged evidence |
| `hitChance` | 22 | ranged accuracy evidence |
| `aimingTime` | 22 | ranged handling cost |
| `ammoType` | 22 | firearm/ammo relationship; not proof the item is ammo |
| `magazineType` | 7 | firearm loading model |
| `aimedFirearm` | 22 | firearm handling evidence |
| `partType` / `mountOn` | 11 | weapon-part identity and compatibility |
| `criticalChance` | 0 in parsed script context | runtime-only or not exposed in item scripts |
| `reloadTime` | 0 in parsed script context | runtime-only or not exposed in item scripts |
| `jamGunChance` | 0 in parsed script context | runtime-only or not exposed in item scripts |
| `swingTime` / `minimumSwingTime` | 0 in parsed script context | runtime-only or not exposed in item scripts |
| `knockdownMod` / `pushBackMod` | 0 in parsed script context | runtime-only or not exposed in item scripts |
| `treeDamage` / `doorDamage` | 0 in parsed script context | runtime-only or not exposed in item scripts |

The zeroes do not mean the Java methods do not exist. They mean the current offline item-definition input does not expose those values. A robust tool must report “missing evidence” rather than silently interpreting missing values as zero-quality weapons.

### State and context fields needed for dynamic pricing

The current evaluator uses `conditionMax`, but not the condition of an actual item instance. Dynamic price calculation should use a separate instance-state layer:

```text
conditionRatio = clamp(currentCondition / conditionMax, 0, 1)
```

The state layer should be applied after the static anchor. It should not rewrite the item’s mechanical category.

Recommended state inputs, in priority order:

1. Current condition and condition maximum.
2. Whether the weapon is broken, jammed, unloaded, or missing required parts.
3. Remaining ammunition/magazine state when pricing an actual instance.
4. Runtime sharpness or other modifiers that alter effective damage.
5. Character-context values only when the consumer explicitly supplies them; ranged max range depends on the owner’s aiming perk, so the static catalog should not pretend it has one universal runtime range.

A conservative condition curve should be monotonic and bounded. For example, a future design can use a square-root or logistic curve so a weapon at 90% condition is not priced almost the same as a ruined weapon, while a nearly ruined weapon still retains salvage value. The exact curve and coefficients should be tuned against a test fixture, not guessed in the detector.

## Recommended anchor taxonomy

These are proposed interface concepts, not a request to change native PZ item categories.

### Primary mechanical anchors

```text
Weapon.Melee.Improvised
Weapon.Melee.SmallBlade
Weapon.Melee.SmallBlunt
Weapon.Melee.Blunt
Weapon.Melee.Axe
Weapon.Melee.Spear
Weapon.Melee.LongBlade
Weapon.Melee.Unarmed
Weapon.Ranged.Handgun
Weapon.Ranged.Shotgun
Weapon.Ranged.Rifle
Weapon.Ranged.Explosive
Weapon.Part
```

`Improvised` should be retained as a modifier when a more specific native combat category exists. For example, a crafted spear should be `Weapon.Melee.Spear` plus `traits: [Improvised, Crafted]`, not only `WeaponCrafted`.

### Independent market-role tags

```text
Role.Tool
Role.Cooking
Role.Gardening
Role.Fishing
Role.Household
Role.Sports
Role.Instrument
Role.Material
Role.AnimalPart
Role.VehicleMaintenance
Role.FirstAid
Role.Memento
```

Examples:

| Item evidence | Mechanical class | Market role(s) | Pricing implication |
|---|---|---|---|
| `Base.SpearCrafted` | Spear | Crafted, Fishing-compatible | spear anchor plus crafted/role overlays |
| `Base.GardenFork` | Spear | Gardening | keep spear mechanics; add gardening role |
| `Base.BreadKnife` | SmallBlade | Cooking | kitchen anchor may dominate store presentation, but combat class remains queryable |
| `Base.Shovel` | Blunt | Gardening, Tool | price should reflect high utility and combat fallback separately |
| `Base.ClosedUmbrellaBlack` | Spear | Household | retain spear evidence; do not collapse to `Misc` |
| `Base.Katana` | LongBlade | Combat | long-blade anchor plus quality/rarity/origin overlays |
| `Base.Revolver_CapGun` | Fake firearm/memento | Memento | should not receive a real firearm anchor |

## Proposed procedural pricing model

The next implementation should use a stable anchor and bounded adjustments:

```text
staticAnchor = anchor(mechanicalClass, marketRole, craftedState, rarity/quality)
performance  = normalized(combat features with available evidence)
stateFactor  = bounded(condition/loadout/runtime-state factor)
roleFactor   = bounded secondary-purpose factor

price = clamp(round(staticAnchor * performanceFactor
                    * stateFactor * roleFactor), floor, ceiling)
```

### Performance features

For melee, the intended signal is effective damage throughput, not raw damage alone:

```text
throughput ≈ averageDamage * effectiveHitCount / effectiveAttackTime
```

`swingTime`, `minimumSwingTime`, `criticalChance`, `knockdownMod`, `pushBackMod`, and target-facing behavior should be added only when the runtime reader can observe them correctly. Until then, use the currently available damage/range/hit-count fields and lower confidence when fields are absent.

For firearms, the performance group should include:

- damage and effective hit count;
- hit chance;
- range under an explicit aiming context;
- aiming time;
- reload time and magazine capacity;
- jam chance/reliability;
- one-hand/two-hand handling;
- ammunition compatibility as a compatibility signal, not as an ammo-item identity signal.

### State factors

The item’s current condition belongs here, not in the static anchor. A suggested initial policy is:

- full condition: near `1.0` state factor;
- degraded but usable: smooth reduction;
- broken: a low salvage/repair factor or a dedicated broken-item policy;
- missing runtime condition: keep the static price and lower confidence rather than assuming zero.

### Crafting and learned recipes

The player’s learned recipe count should not be blindly added to every weapon’s price. Learned recipes are character knowledge and can be valuable independently of the item. For weapons, use item-definition evidence such as crafted tags, recipe-product evidence, material/quality traits, and actual provenance if the runtime exposes it. Keep “this item teaches a recipe” as a literature/knowledge value, not as a melee damage value.

## Harness test plan for the next implementation

The current harness already executes the real Lua evaluator and should gain focused assertions for the following cases:

1. **Firearm routing:** a pistol, shotgun, rifle, and both cap-guns must not enter the generic ammo branch.
2. **Two-hand parsing:** `TwoHandWeapon = true` must be visible in the bridge context and must separate long guns from handguns.
3. **Native category preservation:** every vanilla spear must retain a `combatClass=Spear` evidence field even if its market role is Household or Gardening.
4. **Multi-role output:** bread knife, saucepan, shovel, fishing rod, umbrella, and garden fork must expose both mechanical and market-role evidence.
5. **Unarmed:** `Base.BareHands` must have an explicit unarmed mechanical class.
6. **State pricing:** synthetic inventory instances at condition 100%, 50%, 1%, and broken must produce monotonic bounded prices.
7. **Missing-field safety:** a weapon with no swing/reload/runtime-only fields must remain evaluable without gaining an accidental penalty or bonus.
8. **Outlier guards:** Katana and cap-gun prices must be reported as intended outliers, not allowed to silently define the category anchor.
9. **Mod extensibility:** a Workshop weapon with namespaced categories and tags must pass through the same namespace normalization as vanilla.

Each assertion should print a compact chunk containing:

```text
fullType | mechanicalClass | marketRoles | evidence fields | state | anchor | final price | confidence
```

This keeps the terminal useful for debugging without flooding the model context with the complete catalog.

## Implementation order

1. Correct the evidence adapter: `base:` tag aliases, `TwoHandWeapon`/`isTwoHandWeapon`, and the ammo-versus-firearm ordering.
2. Add a non-destructive `mechanicalClass`/`marketRoles` result alongside the existing final primary label.
3. Add an explicit `WeaponImprovised` and `WeaponUnarmed` taxonomy leaf, or document the intentional mapping if compatibility requires keeping the current names.
4. Expose current condition and separate runtime weapon metrics in `PropertyReader` with per-field availability flags.
5. Build measured anchor tables from clean mechanical classes; do not derive anchors from rows that are still mixed with mementos, cookware, or ammunition.
6. Add bounded state/performance multipliers after the static anchor is stable.
7. Add the focused harness tests above, then use the GUI’s low-confidence and evidence panels to review Workshop items.

## Audit conclusion

The base game supplies enough evidence to build useful weapon anchors, but not enough to treat every item as a single flat category. Native `weaponCategories` are the best mechanical source; `displayCategory`, tags, item type, and runtime capabilities explain player purpose. Market Sense should preserve those as separate facts and let pricing combine them deliberately.

The first Lua changes should therefore target correctness of evidence flow, especially firearm detection and two-hand state, before tuning numerical coefficients. Otherwise the tool will continue to produce confident-looking prices for the wrong pricing branch.

## Implementation update

The melee portion of this audit is now implemented in the Market Sense Lua driver:

- Native weapon categories resolve to dedicated nested leaves such as `Weapon > Melee > Spear`, `Weapon > Melee > Axe`, `Weapon > Melee > LongBlade`, `Weapon > Melee > SmallBlade`, `Weapon > Melee > SmallBlunt`, `Weapon > Melee > Improvised`, and `Weapon > Melee > Unarmed`.
- `weaponEvidence` is retained separately from the market label, so a multi-purpose item can remain under `Building`, `Tool`, or `Misc` while still exposing its mechanical weapon class to future consumers.
- Melee prices use bounded damage, range, hit-count, durability, weight, subtype, two-handed, and runtime-condition factors. Static definitions remain deterministic; concrete inventory instances can be evaluated with `MarketSense.GetPriceDetailsForInstance`.
- The condition curve is intentionally bounded at a configurable floor (default `0.35`) and does not apply when live condition evidence is unavailable.
- Runtime-only combat fields that are not exposed by the current 42.20 item-definition reader remain listed as unavailable instead of being guessed.

The focused Lua smoke tests, Python harness smoke tests, and Kahlua compatibility scan pass after this implementation. Firearm/ammunition routing remains a separate follow-up from the melee pass.
