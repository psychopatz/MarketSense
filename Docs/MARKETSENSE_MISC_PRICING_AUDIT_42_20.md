# MarketSense Misc Pricing Audit — 42.20

## Scope

This pass covers the pricing boundary for the `Misc` root after the
classification and capability work. It does not change Misc taxonomy or move
items between roots.

## Current structure

`Misc` is both a real collection of utility families and the final fallback for
items that do not have enough evidence for Food, Weapon, Tool, Container,
Clothing, Medical, Electronics, Literature, Building, Liquid, or Resource.
The current taxonomy can identify families such as:

- `Memento` and `Junk`;
- `MiscFishing`, `MiscFire`, `MiscSafety`, `MiscSecurity`, and
  `MiscNavigation`;
- `MiscHousehold`, `MiscRecreation`, `MiscEntertainment`, `MiscTrapping`,
  `MiscAnimal`, and `MiscUtility`.

The same root therefore contains fishing hooks, lighters, filters, keys,
maps, household goods, recreation items, decorative keepsakes, junk, and
unknown mod content. A single flat root or subtype bonus cannot represent that
range safely.

## Legacy pricing removed

The old Misc monetary inputs were a `$17` root addition, a `$17` sandbox
option, and flat subtype bonuses for fire starters, purification, filters,
hygiene, cosmetics, morale, crafting, jars/boxes, keys, cameras, and material
weight. Those values were not comparable across item functions and could make
unknown or decorative rows look valuable. They are removed while the existing
Misc stock multiplier remains available.

## Evidence model

Misc rows use `misc_v2_pending` for ordinary and unresolved items. The raw
price remains the neutral Misc anchor (`$2`) until the family anchors below are
calibrated. One high-confidence transform is now implemented: an exact recipe
that opens a Misc item is valued from its child raw scores, with each child
score multiplied by its exact output quantity. The parent package receives only
that computed output value, so its own neutral anchor is not added again.

The resolver records:

- final subtype and classifier provenance;
- direct capability, requirement, world-object, and power evidence;
- fishing-lure, water-storage, drainable, recipe-product, moveable,
  packaged, poison, dung, loot, and forage state flags;
- weight, empty weight, stackability, stack count, condition, drainable uses,
  replacement, and disappearance signals;
- opening/double-click recipe signals and deterministic child outputs,
  including total output quantity for package candidates.

Exact multi-output transforms expose `mode`, `yieldValue`, and per-output
`contributions` in the heuristic and catalog diagnostics. Ambiguous,
probabilistic, cyclic, unavailable, or otherwise unresolved outputs remain
diagnostic-only and retain the neutral score. This keeps uncertain package
contents from creating false positives while allowing boxes, cartons, packs,
and similar items to be priced from individualized outputs.

## Positive anchors to calibrate

Positive value should come from verified player outcomes, not from a name or
rarity label alone:

1. A direct player capability or action enabled by the item.
2. A deterministic child-item yield, valued as the individual child value
   multiplied by the output quantity. The parent package must not also receive
   the full child value during the same calculation.
3. Reusable uses, remaining drainable amount, or stack quantity.
4. Proven fishing, fire, safety, security, navigation, household, crafting,
   agriculture, processing, or recreation utility.
5. A recipe transform that exposes useful contents or materially reduces the
   work required to reach a usable item.
6. Delivered utility per unit of weight and encumbrance.

## Negative anchors to calibrate

Negative value should reduce delivered utility or increase the player's cost:

1. Fallback, ambiguous, or unknown classification.
2. Decorative memento, junk, or cosmetic identity without a mechanical use.
3. Weight, bulk, placement, and handling burden relative to utility.
4. Single-use, depleted, empty, damaged, broken, or partial-use state.
5. Electricity, water, fuel, a station, or another operating requirement.
6. Poison, waste, contamination, or harmful handling state.
7. Probabilistic or unresolved package contents.
8. Rarity, theme, source, or display labels without verified player utility.

## Calibration order

The first calibration set should be high-confidence and mechanically distinct:

1. Fishing and fire items with explicit tags or capabilities.
2. Safety and security items with verified state/requirements.
3. Deterministic package transforms and multi-output bundles.
4. Reusable household/utility items with known uses or capability evidence.
5. Mementos, junk, and broad `Misc` fallback rows as the low-utility control
   group.

Until the remaining calibration is complete, non-transform Misc items keep the
neutral score. The catalog and terminal diagnostics show transform mode,
calculated yield value, blocked-yield reasons, and per-output contributions so
false positives can be reviewed before family anchors are enabled.
