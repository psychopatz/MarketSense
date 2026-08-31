# MarketSense Liquid Pricing Audit — 42.20

## Reset decision

The former Liquid model was a hand-authored dollars-per-litre table. It used
fluid name plus the primary-fluid amount, so it could not distinguish a useful
drink from a harmful liquid, a mixture whose other components were unknown, or
a fluid that only has value after processing. It also created a second pricing
contract in the inspector. The table, optional override module, and editor are
removed.

Liquid classification remains separate from vessel classification. Filled
fluid containers can be `Liquid`; empty containers remain in the `Container`
root. The pending model uses the engine-backed fluid evidence already exposed
by `PropertyReader`.

## Evidence captured now

`liquid_v2_pending` records:

- fluid type and display type;
- fluid categories discovered through `FluidCategory.getList()` and
  `Fluid:isCategory(...)`;
- total amount, capacity, primary-fluid amount, fill ratio, empty state, and
  mixture state;
- container name and item weight as vessel/handling evidence;
- hydration, nutrition, mood, alcohol, medical, and harmful-state fields when
  present;
- runtime age, freshness, rotten, frozen, and poison fields when available;
- yield recipe/status and every discovered output quantity.

The primary amount is not treated as the whole value for mixtures. Project
Zomboid's `FluidContainer` chooses the largest component for
`getPrimaryFluid()`/`getPrimaryFluidAmount()`, so a mixture is explicitly
flagged for review until all components can be enumerated or the mixture's
mechanical behavior is verified.

## Proposed anchor contract

The eventual numerical model should be deterministic and layered:

1. establish a content utility anchor from verified player effects or verified
   non-player function;
2. scale by measured usable amount, never capacity alone;
3. apply state and safety modifiers;
4. apply processing/access costs and vessel burden once;
5. replace a package's value with the sum of deterministic child values times
   quantity when a yield is resolved;
6. reject or discount ambiguous/probabilistic yields instead of inventing
   output value;
7. clamp and round through the normal MarketSense price pipeline.

Positive anchors:

- actual drinkable hydration, nutrition, mood, or health benefit;
- verified fuel, medical, cleaning, dye, or industrial function;
- usable amount and safe transfer/consumption compatibility;
- stable shelf life or preserved state when the engine exposes it;
- deterministic child-item yield multiplied by output quantity.

Negative anchors:

- empty or zero-amount content;
- rotten, tainted, poisonous, or harmful content;
- mixture uncertainty when only the largest component is visible;
- unknown type/category/effect or missing mechanical proof;
- weight, bulk, encumbrance, and handling burden;
- required equipment, fuel, power, or processing;
- ambiguous, unresolved, or probabilistic package yield;
- capacity being mistaken for content value or vessel value being counted twice.

## Calibration sequence

The first calibration set should contain equal-volume water, soda, alcohol,
fuel, medical/chemical fluids, tainted or poisonous fluids, empty vessels, and
known mixtures. The next set should compare identical fluids in different
vessels to verify that the content anchor and container anchor do not overlap.
Finally, resolved package recipes should be checked against their child values
and unresolved packages should remain visible as evidence gaps.

Until those comparisons are complete, Liquid uses the neutral category anchor
and exposes all inputs in the resolver, terminal report, cache export, and
offline fixture output.
