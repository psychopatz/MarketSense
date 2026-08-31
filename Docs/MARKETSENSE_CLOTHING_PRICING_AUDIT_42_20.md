# MarketSense clothing pricing audit and reset (Project Zomboid 42.20)

## Decision

Clothing is reset to a neutral, visible `clothing_v2_pending` heuristic until its
signals are normalized and calibrated. The previous score mixed raw defense,
warmth, wind resistance, and a global weight penalty, then stacked large flat
category and subtype additions. That made an armor item, a cosmetic item, and a
generic clothing item incomparable and allowed the same raw stat to mean very
different things across body slots.

The reset removes all `PriceClothing*` controls and clothing flat tag additions.
`StockClothing*` controls remain because stock pressure is independent of item
utility. Exact item and module overrides remain authoritative.

## Current classification structure

The root arbiter identifies clothing from a body-location token, a blood-clothing
type, or the engine clothing type. The apparel signature then maps body locations
to clothing families such as full body, outerwear, top, bottom, footwear, head,
hands, underwear, and accessories. Protective gear is represented as a separate
display family when the evidence supports it. Wound and state-only locations are
excluded from normal market classification.

The property reader currently supplies useful static evidence such as body
location, bite/scratch/bullet defense, insulation, wind resistance, condition,
condition ratio, and weight. The implementation phase must add and verify the
remaining runtime signals before using them in money calculations: water
resistance, temperature, run/combat speed modifiers, neck protection, fall risk,
wetness/wet weight, holes, dirtiness, and blood level.

## Recommended pricing anchor

Use a family anchor first, then value normalized delivered utility. A clothing
family is a comparison group, not a flat price addition:

```text
familyAnchor = calibrated anchor for the body-slot/family
protectionUtility = normalized bite + scratch + bullet protection × coverage
climateUtility = normalized insulation + wind + water + temperature utility
mobilityUtility = speed/combat benefits - speed/fall penalties
durabilityFactor = condition, holes, blood, dirtiness, and wetness state
carryingCost = weight relative to delivered utility

price = clamp(round(
    familyAnchor × (1 + protectionUtility + climateUtility + mobilityUtility)
    × durabilityFactor - carryingCost
), floor, ceiling)
```

This is a design contract, not an approved coefficient set. Coefficients should
be selected from monotonic test cases and representative item samples. Each
signal needs a bounded normalization and diminishing returns so a high raw value
cannot dominate the whole market. Missing signals must contribute zero evidence,
not an invented default.

## Positive anchors

- Effective bite, scratch, and bullet defense, discounted when condition is zero
  or a visual hole disables protection.
- Coverage and body-slot relevance. Protection on torso, head, neck, and other
  exposed slots should be compared within that slot rather than against jewelry.
- Insulation, wind resistance, water resistance, and temperature utility when
  those fields are verified for the item class.
- Positive movement or combat modifiers, when the engine semantics are confirmed.
- Maximum condition and repairability, only when they improve usable lifetime and
  are not double-counted with the current condition state.
- Verified functional accessory utility. A watch, radio, or other functional
  accessory should be valued by the utility it actually provides, not by the
  word “rare” or a cosmetic label.

## Negative anchors

- Weight and encumbrance relative to the protection or utility delivered.
- Run-speed, combat-speed, or fall-risk penalties.
- Broken or low-condition state, holes, and any defense-disabled state.
- Blood, dirtiness, and wetness when they create maintenance or immediate-use
  costs. Wet weight should affect carrying cost, not create a second utility.
- Neck-protection reduction or an uncovered/disabled critical area.
- Cosmetic, rarity, authority, tactical, or theme labels without verified
  mechanical utility. These may remain descriptive metadata, but should not be
  monetary anchors in the deterministic model.

## Family treatment

- Protective gear/armor: protection and coverage dominate; mobility, weight, and
  condition are strong counterweights.
- Outerwear, tops, bottoms, full body, headwear, and footwear: slot anchor plus
  climate utility and mobility/carrying cost.
- Hands and underwear: modest slot anchors; only verified protection or utility
  should materially increase value.
- Jewelry and other accessories: low base anchor unless engine or mod metadata
  proves a functional effect; do not price jewelry from rarity alone.
- Generic/cosmetic clothing: low baseline and no fabricated value for missing
  mechanical fields.

## Static versus runtime state

Static definition data determines family, body location, configured defenses,
climate properties, weight, maximum condition, and verified functional effects.
Instance data determines current condition, holes, wetness, blood, dirtiness, and
other wear state. The static catalog can therefore show a reference price or
evidence state, while instance pricing applies only the state factor and carrying
cost that are actually observable.

## Implementation order

1. Keep the current pending heuristic and expose all available clothing evidence
   in the resolver, debug catalog, terminal report, JSON, and audit trail.
2. Add a dedicated clothing pricing module rather than putting another raw-stat
   branch in the generic pricing function.
3. Extend `MS_PropertyReader` with verified engine fields and explicit
   availability flags, including wet weight and visual holes.
4. Implement family anchors and bounded, diminishing-return utility terms.
5. Add runtime-state factors with explicit broken/unknown behavior.
6. Calibrate against representative vanilla and modded clothing and enforce
   monotonic tests: more effective protection must not lower price; a broken item
   must not exceed its intact counterpart; equivalent utility in different slots
   must remain within the intended family ranges.

The cache version is bumped with this reset so old clothing dollars are not reused
after catalog refresh.
