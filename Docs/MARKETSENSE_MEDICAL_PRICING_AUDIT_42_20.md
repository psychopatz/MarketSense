# MarketSense medical pricing audit and reset (Project Zomboid 42.20)

## Decision

Medical pricing is reset to a visible `medical_v2_pending` heuristic. The
legacy score was a flat category bonus (`base + 12 - weight`) with additional
FirstAid and Bandage tag dollars. That cannot distinguish a basic bandage,
infection treatment, symptom medicine, surgical item, or medical kit.

The reset removes the `PriceMedical*` sandbox controls, medical tag-price
additions, old medical category coefficients, and old FirstAid/Bandage price
recommendations. Medical stock controls remain separate from usefulness.
Exact item and module overrides remain authoritative. Pricing cache version 16
forces materialized details made with the old score to be rebuilt.

The final coefficients are intentionally not guessed yet. The resolver, debug
catalog, and terminal expose the evidence needed to calibrate the model against
vanilla and modded medical items first.

## Current structure

The root arbiter admits medical items from FirstAid/medical display evidence,
medical/first-aid loot evidence, and verified bandage or infection-treatment
signals. The current signature deliberately remains broad: it can identify
FirstAid from display or treatment context, but the existing taxonomy is not a
complete medical-family classifier. Names such as “antibiotic” or “painkiller”
must not become price anchors by themselves.

The pending payload now records:

- medical loot and bandage capability;
- bandage, infection, alcohol, pain, flu, and food-sickness effects when the
  runtime object exposes them;
- condition, weight, use delta, maximum/remaining uses, replacement output,
  and disappearance-on-use behavior;
- deterministic yield status and output count;
- which evidence fields were actually available, plus planned positive and
  negative anchors.

## Engine evidence and boundaries

The 42.20 Java baseline exposes useful medical signals through
`InventoryItem.getBandagePower()`, `getReduceInfectionPower()`,
`getAlcoholPower()`, and `isCanBandage()`. Script/item metadata also exposes
medical-loot and use behavior such as `isUseSelf()`, `getReplaceOnUse()`,
`getUseDelta()`, and `isDisappearOnUse()`.

Food-like medicine may expose `getPainReduction()`, `getFluReduction()`, and
`getFoodSicknessChange()`. These are optional signals, not assumptions about
every medical item. In particular, `getReduceInfectionPower()` applies runtime
state modifiers for burnt/aged/cooked food objects, so static script evidence
and current-instance evidence must remain distinguishable.

Scripted `OnCreate`/`OnUse` behavior and arbitrary mod Lua may not be statically
introspectable. Missing effect data contributes no fabricated effect value;
the item remains visible as low-evidence or pending rather than receiving a
large name-based bonus.

## Recommended primitive model

Use one bounded model with family-specific anchors and shared state/cost terms:

```text
familyAnchor = calibrated baseline for the medical family
treatmentUtility = diminishing function of verified effect magnitude and target
doseUtility = deterministic doses, uses, and replacement behavior
stateFactor = condition × remaining uses × expiry/operability
accessFactor = self-use, target compatibility, and coverage
carryingCost = weight, bulk, and handling burden
packageValue = sum(child unit values × deterministic quantity)

price = clamp(round(
    familyAnchor
    × (1 + treatmentUtility)
    × doseUtility
    × stateFactor
    × accessFactor
    + packageValue
    + reusableMedicalUtility
    - carryingCost
    - sideEffectOrOperatingCost
), floor, ceiling)
```

This is a design contract, not a final coefficient set. Every raw signal must
be normalized within its family and capped. Package value is used only when a
yield resolver proves the child item and quantity; a box/carton gets no flat
premium merely because its name contains “box”. Retained reusable packaging
may add its own verified utility.

## Positive anchors

- Verified treatment effect and patient-facing outcome: bandage power,
  infection reduction, alcohol cleaning, pain relief, flu relief, or
  food-sickness relief.
- Treatment compatibility and coverage, including `canBandage`, self-use,
  accepted target/body-part behavior, and whether the item can actually be
  applied in the relevant action.
- Deterministic doses, maximum/remaining uses, use delta, and replacement
  outputs. A multi-use item should be valued per usable dose, not as one
  indistinguishable object.
- Sterile/clean state only when it changes the actual treatment behavior.
- Verified surgical, immobilization, diagnostic, repair, or reusable medical
  utility from an action or recipe graph.
- Deterministic bundle/kit/carton output, individualized as child value times
  quantity.
- Treatment delivered per unit of weight, after the primary utility is known.

## Negative anchors

- Weight, bulk, encumbrance, and handling cost per treatment delivered.
- Depleted uses, consumed-on-use state, missing replacement output, or an item
  that is no longer operable.
- Broken, damaged, stale/expired, or otherwise unusable state when the engine
  exposes that state. Do not infer expiry from a display label alone.
- Toxicity, addiction, fatigue, stress, pain, or other side effects only when
  mechanically evidenced; “painkiller” is not proof of a risk value.
- Narrow target compatibility, self-only/world-only access, and limited
  treatment coverage when those restrictions are mechanically known.
- Dirty/nonsterile state only when it changes the actual treatment outcome.
- Ambiguous names, rarity, theme, or display labels without effect evidence.
  These can explain classification, but must not create a large price.

## Family treatment

- **Wound care:** bandage power, infection reduction, bandage capability,
  coverage, and clean/dirty state. A basic dressing and a high-power dressing
  need separate calibrated baselines.
- **Infection and cleaning:** infection reduction or alcohol power, target
  eligibility, dose count, and state-sensitive effectiveness.
- **Symptom relief:** pain, flu, food-sickness, fatigue, or stress effects only
  when exposed by the item API. Normalize relief per dose and cap it.
- **Pills and consumables:** use delta, doses, remaining uses, disappearance,
  replacement, side effects, and carrying efficiency.
- **Surgical, immobilization, and diagnostic items:** require action,
  compatibility, or recipe evidence before receiving a material uplift.
- **Medical kits, boxes, and cartons:** resolve deterministic child outputs and
  sum child unit values times quantities. Add package utility only if the
  package itself remains useful after opening.
- **Generic FirstAid residual:** use a conservative pending baseline until
  mechanical evidence assigns a more specific family.

## Static versus runtime inputs

Static catalog pricing should use script/item metadata, stable capabilities,
weight, maximum doses, and deterministic recipes. Runtime pricing may add
current condition, remaining uses, age/food state, charge, and operability
when an item instance is supplied. Player-specific need or scarcity should be
an optional market-demand layer, not part of the deterministic item utility
price.

## Calibration order

1. Keep the pending heuristic and evidence visible in the resolver, debug
   catalog, terminal, and smoke fixtures.
2. Expand the medical classifier into evidence-backed families while retaining
   FirstAid compatibility for existing mods.
3. Build reference items for wound care, cleaning/infection treatment,
   antibiotics, symptom medicine, pills, splints/sutures, and kits/boxes.
4. Normalize effect per dose and target, then add bounded diminishing returns.
5. Integrate condition, remaining uses, expiry/state, and deterministic yields.
6. Promote the calibrated model to active and bump the cache version again.

## Invariants

- More verified treatment effect or usable doses cannot lower price within a
  family.
- More remaining uses or better condition cannot lower price for an otherwise
  equivalent item.
- Depleted, expired, or unusable items cannot outrank usable equivalents.
- A heavier item with equal verified function cannot outrank a lighter one
  solely because it is heavier.
- A deterministic bundle is at least the value of its resolved child outputs,
  absent an explicitly negative package/handling cost.
- Missing evidence cannot beat a resolved item solely through its name.
- Child values are not counted both as a package yield and as an unrelated
  flat bundle bonus.
