# MarketSense Food Pricing Plan

Status: food valuation v2 boundary and provisional anchor.

## Current structure

Food classification and food valuation are currently mixed downstream of the
same context:

```text
PropertyReader.buildContext
  -> AutoTag.generate / MS_Sig_Food
  -> Pricing.calculateRawScore
  -> Pricing.applyBalances
  -> Stock.calculate
```

The classifier and taxonomy are useful and remain in place. The obsolete food
valuation was concentrated in `MS_Pricing.calculateRawScore`, the Food entries
in generated pricing data, flat Food/Beverage tag additions, and the three
`PriceFood*Value` sandbox options. Those values were additive and operated on
raw PZ hunger units. In the current scan, `ChickenWhole` produced a raw score
near 25,648 because `-160` hunger was treated as `160 * 160`.

## Provisional anchor

The first calibration anchor is **$10 for one standard food ration**:

- approximately 30 displayed hunger points (`Food.getHungerChange() = -0.30`);
- approximately 500–800 calories;
- neutral mood effects;
- fresh, edible, and normally portable.

This is a calibration unit, not a hard-coded price for a specific item. The
anchor should be exposed later as `Food.anchor` in the authoritative pricing
profile and adjusted by the server's economy settings.

## Food valuation model

The new model has four independent stages:

1. **Intrinsic food utility**: hunger, thirst, and calories converted into
   bounded, diminishing-ratio ration units.
2. **Food role**: edible food, drink, ingredient, spice, seed, pet food, or
   other non-direct-consumption roles.
3. **State**: static storage horizon, live age, stale/rotten state, frozen/cooked/burnt state, and
   preparation risk when the runtime exposes it.
4. **Market policy**: global multiplier, exact item override, and later supply
   or demand adjustments. These must not be confused with intrinsic utility.

The first implementation uses this conceptual form:

```text
intrinsic = Food.anchor * rationUnits
price = intrinsic * roleMultiplier * moodMultiplier * shelfLifeMultiplier
        * freshnessMultiplier * preparationMultiplier * bulkMultiplier
```

The final result is clamped by the Food profile floor and ceiling. Nutrition
features are transformed before weighting; raw hunger/calorie values are never
used as direct dollar additions.

## Positive anchors

| Signal | Treatment | Reason |
| --- | --- | --- |
| Negative hunger change | High positive contribution | Direct fullness and survival utility |
| Negative thirst change | Medium positive contribution | Hydration utility, including foods such as watermelon |
| Calories | Medium, diminishing contribution | Longer-term energy; do not count macros again as separate calories |
| Negative unhappiness/boredom/stress | Small bounded multiplier | Quality-of-life utility, not the primary food value |
| Days before spoilage | Small static preservation multiplier | Longer planning horizon; must not dominate nutrition; separate from current age |
| Canned/preserved/packaged | Small role/state multiplier | Better storage and transport, not a second full food value |

## Negative anchors

| Signal | Treatment | Reason |
| --- | --- | --- |
| Positive hunger/thirst change | Bounded penalty | The item makes the survivor less fed or hydrated |
| Positive unhappiness/boredom/stress | Bounded penalty | Direct negative effect |
| Stale or nearly rotten runtime state | Freshness multiplier | Immediate sale value is lower because usable time is short |
| Rotten state | Strong floor multiplier | It is no longer normal edible inventory |
| Poison/dung | Strong bounded penalty or review flag | Not normal human food |
| Dangerous uncooked food | Preparation-risk penalty until cooked | A raw item is not equivalent to a ready meal |
| High weight relative to ration utility | Small bulk penalty | Carrying cost, without making large food worthless |
| Insect/pet food/seed/spice roles | Role-specific bounded multiplier | These are not interchangeable with a normal meal |

`FoodInsect` should initially be a modest configurable multiplier, roughly
`0.70–0.85`, rather than a flat dollar deduction. Pet food and seeds should
use lower role multipliers because their human-consumption utility is limited.
Spices should have low direct nutrition value and later gain recipe utility
from a food-recipe graph.

## Important PZ API rules

- PZ food changes are signed: negative hunger/thirst is beneficial; positive
  values are harmful. The existing context keeps magnitude fields for
  classifier compatibility, while the new valuation reads signed fields.
- Item scripts store hunger/thirst changes in hundredths; pricing uses the
  native runtime getter values, so `HungerChange = -30` is `-0.30` here.
- `daysFresh` and `daysTotallyRotten` are static definition thresholds. Live
  inventory age must come from `InventoryItem:getAge()`.
- Use `Food:isRotten()` for the food-specific rotten state. Do not treat the
  static spoilage thresholds as the current age.
- PZ food getters may already adjust values for cooked, burnt, stale, and
  frozen states. Food valuation therefore reads unmodified Food getters and
  applies the explicit MarketSense state curve once; it never combines both
  adjustments for the same effect.
- `CantEat` is a role signal. Whole ingredients such as an uncut watermelon
  must not receive full direct-consumption nutrition value.

## Legacy removal boundary

Remove from the active food price path:

- the Food/Beverage branch in `MS_Pricing.calculateRawScore`;
- Food-specific raw coefficient fields such as `hunger_weight`,
  `thirst_weight`, `calorie_weight`, `shelf_life_weight`, and additive food
  bonuses;
- Food and Beverage entries from flat price-addition data;
- `FoodNonPerishableCanned` price addition, while retaining its stock rule;
- `PriceFoodValue`, `PriceFoodMediumNutritionValue`, and
  `PriceFoodNonPerishableValue` sandbox declarations and translations.

Keep food classification, food audit evidence, stock settings, global price
policy, exact per-item overrides, and liquid pricing unchanged.

## Calibration tests

The regression set should include:

- potato, bread, chicken, pizza, pasta, and watermelon;
- fresh, stale, nearly rotten, and rotten instances;
- canned versus unpackaged food;
- insect food, pet food, seed, spice, and non-edible ingredients;
- beneficial versus harmful mood effects;
- an unknown Workshop food with only minimal metadata.

Required properties are monotonicity, boundedness, no double-counted spoilage,
and neutral behavior when optional metadata is absent. The full obtainable
scan must continue to produce zero evaluator errors.
