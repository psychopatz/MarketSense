# MarketSense resource pricing audit

Date: 2026-08-31

## Current structure

Resources are admitted from material display categories, material loot types,
fuel/fluid categories, paint and other material evidence. The existing taxonomy
is intentionally retained: `Resource` is the root, with material families such
as construction, metalworking, hardware, tailoring, fire source, glass, stone,
chemical, carpentry, wood, paper, pottery, butchering, and bundled material.

The retired score was not a useful market anchor. It combined a base score and
weight penalty with flat dollars for fuel, metal families, wood, chemicals, and
some material tags. That made an ore, a refined ingot, a box of hardware, and a
multi-output package comparable only by labels; it could not price delivered
quantity, processing stage, or recipe-backed utility without double counting.

## Evidence captured for calibration

`resource_v2_pending` records the classifier source and subtype, inferred
material form, item type and display metadata, weight, stackability, condition,
drainable uses, replacement/depletion state, craft-product and acquisition
signals, fluid identity when present, and the generic yield resolver result.
Yield output rows preserve child full type, quantity, maximum quantity, chance,
and resolution. A package is therefore visible as a package candidate, but an
unresolved or probabilistic child is never silently converted into a price.

The current numerical score is the neutral Resource anchor of `$5` while the
calibration set is assembled. Resource tag/sandbox price additions are removed;
Resource stock multipliers remain available because supply pressure is separate
from item utility.

## Proposed deterministic anchor contract

When calibration begins, the implementation should evaluate a resource in this
order:

1. Identify the mechanical role and material family from authoritative game
   evidence, then identify the delivered form: raw, processed, refined,
   packaged, fuel, part, or unknown.
2. Estimate positive utility from verified crafting/component demand, fuel or
   survival function, direct construction/repair use, and any other mechanic
   that the runtime exposes.
3. Multiply by deterministic usable quantity: stack quantity, remaining uses,
   measured fuel amount, or the sum of resolved child values for an unbundle
   recipe. A parent package must not also receive the full child value when the
   child rows are priced independently.
4. Apply costs for weight/encumbrance, raw or intermediate processing, required
   workstation/tool/fuel/power, handling hazard, and uncertain yield.
5. Apply condition, depletion, broken/empty state, and other live state only
   when it is actually available on the inventory instance.
6. Clamp and round through the common price path, then apply stock controls
   independently from the utility score.

## Positive anchors

- Direct, repeatable player utility: construction, repair, crafting, fuel,
  fire-starting, water/survival, tailoring, or other verified function.
- Recipe/component demand, weighted by how many recipes consume the resource and
  whether the resource is replaceable by alternatives.
- Refined or directly usable form when it removes a real processing step.
- Deterministic package yield, valued as child utility multiplied by quantity.
- Remaining drainable amount, stack quantity, or other measured usable amount.
- Utility delivered per unit of weight, when both utility and weight are known.

## Negative anchors

- Weight, bulk, and encumbrance relative to the utility delivered.
- Raw, ore, scrap, mold, powder, or other intermediate forms when processing is
  required before the player can use them.
- Empty, depleted, broken, damaged, or partial-use state.
- Required workstation, tool, fuel, power, skill, or additional processing.
- Poison, contamination, hazard, or harmful handling state when it reduces
  practical player utility.
- Unknown form, weak classification evidence, ambiguous output, or probabilistic
  yield. These should reduce confidence or apply a conservative discount, not
  invent child value.
- Rarity, theme, display name, and visual prestige without mechanical utility.
- Counting both a package and its resolved child outputs as independent full
  value.

## Calibration set

The first comparisons should include nails and other hardware, logs/planks,
ore/ingot/sheet/scrap, charcoal and other fuel, firewood bundles, cloth/rope,
chemicals/gunpowder, paper, animal parts, drainable supplies, and boxed or
bundled resources. Each family should be compared at equal quantity and then
equal carried weight. Package tests should include exact multi-output yields,
variable quantities, multiple outputs, and unresolved/probabilistic recipes.

Until those comparisons are calibrated against actual PZ utility and player
economy targets, the resolver intentionally displays evidence and returns the
neutral anchor instead of presenting guessed resource dollars as finished
pricing.
