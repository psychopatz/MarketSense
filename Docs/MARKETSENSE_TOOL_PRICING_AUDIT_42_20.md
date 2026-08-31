# MarketSense tool pricing audit and reset (Project Zomboid 42.20)

## Decision

Tool pricing now uses the active `tool_v2` heuristic. Its usefulness anchor is
augmented by deterministic recipe demand, so a tool accepted by many reusable
recipes is more valuable than an otherwise similar single-purpose tool. The
previous score multiplied `conditionMax` by a hard-coded coefficient, used any
positive `useDelta` as a high-durability signal, subtracted weight, and then
applied flat root and subtype additions. That could not distinguish a hammer,
a drainable blowtorch, a cookware item, and a weapon-like gardening tool.

All `PriceTool*` controls and tool flat tag additions are removed. `StockTool*`
controls remain because inventory pressure is independent from mechanical
utility. Exact item and module overrides remain authoritative.

## Current structure

The root arbiter recognizes tools from the `Tool`/`Tools` display category,
tool loot type, smokable/cookware aliases, and a separate gardening-tool gate
for sharpenable or tool-like gardening items. The tool signature then maps
verified tag/name evidence into families including blacksmithing, carpentry,
farming, maintenance, mechanics, pottery, tailoring, welding, measurement,
construction, utility, smoking, and a generic tool residual.

The current taxonomy is useful for selecting a family anchor, but the family
labels are classification evidence, not prices. A modded item with the same
verified script behavior should receive the same family treatment without
being added to a name table.

## Engine evidence and important semantics

The 42.20 Java baseline exposes these relevant boundaries:

- `InventoryItem.getConditionMax()` is the maximum condition capacity.
- `InventoryItem.getCondition()` is the current runtime condition and should
  affect instance pricing, not static catalog pricing.
- `InventoryItem.getConditionLowerChance()` delegates to the script item's
  condition-loss parameter. The engine uses it during `damageCheck`, so it is
  durability/failure evidence rather than a direct price.
- `InventoryItem.getUseDelta()` is the use fraction consumed by a drainable
  item. It is not a count of uses by itself.
- `InventoryItem.getMaxUses()` and `getCurrentUsesFloat()` expose total and
  remaining use state. The base `InventoryItem` implementation reports one
  use, while `DrainableComboItem` derives maximum uses from `useDelta` and
  reports its remaining fraction.
- `DrainableComboItem.getWeightEmpty()` separates reusable tool-body weight
  from the filled/charged item weight when available.
- `InventoryItem.getActualWeight()` is the carried weight and belongs in the
  handling/carrying-cost term, not in the usefulness anchor.
- `Item.getAcceptItemFunction()`, `getConditionMax()`, `getConditionLowerChance()`
  and `getEnduranceMod()` are script metadata that may support future verified
  action and handling evidence.
- `ScriptManager.getAllCraftRecipes()`, `CraftRecipe.getInputs()` and
  `InputScript.getPossibleInputItems()` provide the runtime recipe graph.
  `InputScript.isKeep()`, `isDestroy()`, `isToolLeft()`, and `isToolRight()`
  distinguish reusable tool inputs from consumed materials. Amounts are read
  through the input's no-argument amount methods for tag selectors and the
  item-specific overload for explicit item selectors.
- `HandWeapon` also exposes tool-relevant condition and endurance behavior.
  Weapon damage, range, and combat value must not be counted by the tool model
  unless the classification pipeline has explicitly assigned the item to the
  weapon subsystem.

## Recommended pricing anchor

The implemented model is additive and bounded. It keeps the signals visible in
the resolver rather than hiding them inside a name table:

```text
recipeDemandScore = min(1,
    .65 × log(1 + reusableRecipes) / log(49)
  + .25 × log(1 + reusableInputs) / log(73)
  + .10 × log(1 + toolFlagRecipes) / log(25))

raw = anchor + familyAnchor + conditionContribution
    + drainableContribution + recipeDemandWeight × recipeDemandScore
total = clamp(raw × stateFactor - handlingPenalty, floor, ceiling)
```

Recipe breadth has diminishing returns, and only distinct reusable recipe
uses drive the main demand score. Consumed recipe inputs remain visible as
diagnostic evidence but do not pretend that a hammer consumed by one recipe is
as valuable as a hammer retained across many recipes. Missing evidence
contributes zero; it does not receive a guessed default.

## Positive anchors

- Verified player actions the item enables, counted by distinct mechanics rather
  than by the number of matching names or tags.
- Condition maximum and condition-loss resistance for condition-based tools.
- Total uses and remaining uses for drainable tools, with remaining charge
  affecting runtime instance value.
- Repairability, sharpening, or maintenance support when the engine exposes
  reliable evidence.
- Specialized but verified utility: carpentry, blacksmithing, welding,
  mechanics, farming, tailoring, pottery, cooking, measurement, or medical
  interaction.
- Resource efficiency or compatible resource flexibility when it is
  mechanically observable.
- Reusable tool body value after a drainable charge is exhausted.

## Negative anchors

- Weight and endurance cost relative to the amount of work delivered.
- Current damage, broken state, depleted charge, or low remaining uses.
- Two-handed or awkward handling when it imposes a real player cost.
- Fuel/material consumption and a high replacement burden.
- Narrow, gated, or redundant functionality compared with a broader tool in
  the same family.
- Missing, ambiguous, or contradictory capability evidence.
- Rarity, theme, display labels, or name matches without mechanical utility.
- Weapon damage or combat attributes when the item is being valued as a tool;
  those belong to the weapon model and must not be double-counted.

## Family treatment

- Durable hand tools: condition lifetime, condition-loss resistance, verified
  action breadth, and carrying cost dominate.
- Drainable or powered tools: remaining/maximum uses and empty-body value are
  separate. A full charge may contribute resource value only when the resource
  is not valued elsewhere, preventing double counting.
- Crafting and repair tools: family capability is useful only when supported by
  verified script/action evidence. `ToolBlacksmith` or `ToolCarpentry` alone
  selects the comparison family; recipe demand supplies the additional
  usefulness evidence and is bounded by diminishing returns.
- Cooking and cookware: usable cooking actions and recipe compatibility should
  anchor value. The old `PriceToolCookwareValue` flat option is removed.
- Gardening, smoking, and utility tools: use the same primitive evidence model
  with family-specific anchors; do not create one-off name-price tables.
- Tool/weapon hybrids: the root/category owner must be explicit. A tool model
  must not inherit weapon damage, while a weapon model must not lose verified
  tool maintenance value accidentally. The current weapon-pending path bridges
  only reusable recipe demand, which is why a native weapon such as a hammer
  can receive tool value without pretending its combat score is calibrated.

## Static versus runtime state

Static catalog data determines family, maximum condition, condition-loss
resistance, maximum drainable uses, expected weight, and verified capability.
Runtime pricing may additionally use current condition and remaining uses.
Static catalog generation must not pretend every item is freshly charged or
fully repaired unless that is an explicit catalog policy.

## Implemented path and remaining calibration

1. `MS_ToolRecipeDemand` builds a runtime index from the engine's resolved
   possible-input lists. The offline evaluator builds the same evidence from
   exact and tag selectors, including Workshop definitions.
2. `MS_ToolPricing` combines family, condition, drainable-use, recipe-demand,
   state, and handling terms. It is dispatched directly from `MS_Pricing`; the
   old tool score and pending compatibility alias are removed.
3. The catalog resolver and terminal output show recipe count, reusable count,
   criticality, demand score, and the full recipe evidence record. A current
   42.20 base scan finds `Base.Hammer` accepted by 53 recipes, 52 of them
   reusable; the exact count can change when mods add or replace recipes.
4. Cache version 14 forces old tool scores to be rebuilt.
5. Future calibration should add monotonic tests: more reusable recipes cannot
   lower price; consumed-only demand cannot outrank reusable demand; higher
   condition cannot lower price; a heavier equal-function tool cannot become
   more valuable; and depleted instances cannot exceed full ones.
