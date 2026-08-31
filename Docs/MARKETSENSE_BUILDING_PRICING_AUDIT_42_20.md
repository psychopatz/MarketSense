# MarketSense Building pricing audit (42.20)

## Decision

Building pricing is reset to a visible `building_v2_pending` model while the anchors are calibrated. The old score was not a reliable market value: it started with a category base, added raw inventory capacity, subtracted weight, and then added flat dollars for storage, appliances, gardens, survival objects, and vehicles. Those coefficients made heterogeneous world objects look comparable when they were not.

The old `PriceBuilding*` sandbox controls, generated price recommendations, Building price tag additions, and Building price coefficients are removed. `StockBuilding*` controls remain because supply is a separate market signal. The pricing heuristic cache version is now 17.

The pending score intentionally uses the neutral Building anchor (`5`) and records evidence for the future model. This makes bad classifications and missing engine evidence visible in the resolver without allowing uncalibrated guesses to inflate prices.

## Current classification structure

Building is a broad root. `MS_RootArbiter.buildingRoot` admits gardening evidence, compostable items, seeds, and the broader `Signals.buildingToken` result. `Signals.buildingToken` covers placeable furniture and lighting, storage and surfaces, appliances and plumbing, crafting and processing, agriculture, survival, recreation, display, logistics, traffic, and medical/funeral objects. A Building label therefore identifies an object with building/world utility; it does not by itself identify a price family.

The classifier and the pricing model must stay separate:

* Classification answers “what can this item be?”
* Pricing answers “what verified utility does this particular item deliver, in what state, with what cost to use or carry?”

The current reader already exposes the inputs needed for that separation: item weight, condition, moveability, inventory capacity, weight reduction, world-object sprite/static model, world-object properties, capabilities, requirements, power source, and resolved child yields. `MS_BuildingPricing.lua` snapshots these fields and marks which metrics were actually observed.

## Proposed Building model

Use a family anchor plus measured utility rather than one flat Building bonus:

```text
price = clamp(round(
    familyAnchor
    * serviceFactor
    * deploymentFactor
    * stateFactor
    + storageUtility
    + deterministicPackageValue
    - requirementCost
    - carryingCost
    - ambiguityPenalty
), floor, ceiling)
```

The terms should be defined as follows:

* `familyAnchor`: calibrated reference value for storage, fixture/appliance, crafting/processing, agriculture, survival/shelter, recreation/display, infrastructure, or another verified family.
* `serviceFactor`: value of a verified action or service, such as storage, crafting, sleep, irrigation, laundry, medical transport, recreation, traffic control, or material logistics. Capability evidence must come from engine/world data or a resolved recipe, not only a name token.
* `deploymentFactor`: portability, placeability, access, footprint, and setup burden. A movable object may be more useful because it can be recovered and repositioned; a large stationary object may be less useful despite stronger output.
* `stateFactor`: condition, operability, completeness, and whether the item is usable in its current form.
* `storageUtility`: capacity and weight reduction, with context caveats. Inventory capacity is not automatically the same as a world container’s capacity, and vehicle-context capacity must not be treated as a universal item constant.
* `deterministicPackageValue`: resolved child-item value multiplied by quantity. Unresolved, variable, or chance-based contents do not receive guessed package value.
* `requirementCost`: electricity, water, fuel, consumables, maintenance, specialist setup, or other required operating resources.
* `carryingCost`: item weight, bulk, encumbrance, and handling burden relative to the delivered function.
* `ambiguityPenalty`: missing or conflicting world/recipe evidence. Ambiguity should reduce confidence and usually reduce price; it must never create a positive utility bonus.

Do not add a capability bonus and a family bonus for the same fact. Family anchors establish the comparable baseline; verified capabilities and measured outputs provide the differentiators.

## Positive anchors

These are candidates for the calibrated score, ordered from strongest to weakest evidence:

1. Verified player action or service enabled by the object.
2. Deterministic recipe/action unlocks, weighted by reusable access and practical criticality when the recipe graph is resolved.
3. Storage capacity and weight reduction, normalized within storage families.
4. Reliable output or processing throughput, including agriculture and crafting where the engine data exposes it.
5. Shelter, sleeping, medical, recreation, logistics, or traffic utility that is mechanically verified.
6. Moveable/placeable access when it changes where the service can be used.
7. Condition, repairability, reusability, and completeness.
8. Deterministic child-item yield multiplied by each output quantity. A box that produces twelve eggs must be valued against twelve eggs, not against the box’s empty visual form.

## Negative anchors

These should subtract value or cap the uplift:

* Weight, bulk, encumbrance, footprint, and difficult handling.
* Electricity, water, fuel, consumables, maintenance, and specialist operating requirements.
* Stationary-only placement, poor access, or expensive deployment.
* Broken, damaged, incomplete, empty, or unusable state.
* Unresolved, ambiguous, variable, or chance-based package contents.
* Cosmetic/display status when no additional mechanical utility is present.
* A world sprite, name, rarity, or theme label with no verified function.
* Duplicate counting of capacity, capability, recipe access, or package contents.

## Initial family anchors

The first calibration set should be small and representative:

* Storage and furniture: crate, cabinet, shelf, table, counter, chair, and bed. Separate container capacity, surface utility, sleep utility, and weight reduction.
* Fixtures and appliances: refrigerator, stove, sink, generator-like fixture, and laundry object. Record output/service and operating requirements separately.
* Crafting and processing: generic crafting surface, forge, masonry, and other processing stations. Count verified recipe access and avoid treating a visual workbench as a universal crafting station.
* Agriculture and garden: seed, planter, compostable, protection, irrigation, and decorative garden objects. Separate consumable yield from decor.
* Survival and shelter: tent, sleeping surface, trap, and deployable survival objects. Include portability, setup, durability, and actual survival service.
* Recreation, display, and infrastructure: entertainment, map/certificate/noticeboard, traffic, logistics, and medical/funeral services. Keep cosmetic display values near neutral until a mechanical use is proven.
* Bundles and boxed items: resolve exact outputs first; apply quantity; then subtract packaging, weight, and ambiguity costs. Never price the package as one generic Building item.

## Static and runtime boundaries

Static analysis may use item definitions, world sprite/static model, world property data, capability evidence, recipe graphs, deterministic yield, nominal weight, and nominal capacity. Runtime analysis may use actual condition, operability, contents, placement context, and vehicle/container context. Player-specific urgency, scarcity, and current demand belong to the market layer, not the deterministic item anchor.

The engine evidence has important limits. `Item.getWorldObjectSprite` and `Moveable.getWorldSprite` identify world representations, while world-property inspection identifies capabilities such as containers, surfaces, beds, and crafting surfaces. `ItemContainer.getCapacity` can change with its containing context and vehicle seat rules; it must be labeled as contextual capacity. `InventoryItem.getItemCapacity` and `InventoryContainer.getWeightReduction` are useful item-side measurements, but they are not interchangeable.

## Invariants for calibration

The implementation should enforce these comparisons:

* More verified service, capacity, deterministic output, deployability, or condition must not lower value inside the same family.
* Adding an operating requirement must not raise value.
* An unusable object must not outrank an otherwise equal usable object.
* An equal-function object that is heavier or harder to deploy must not be more valuable solely because of that burden.
* A deterministic bundle should not be worth less than its child contents before packaging and handling costs, unless the family policy explicitly models a real loss.
* Missing or ambiguous evidence cannot create an uplift.
* The same physical fact is counted once.

## Calibration sequence

1. Keep the pending reset and inspect the resolver/terminal output for missing or false capability and yield evidence.
2. Select reference items for each family and record their verified services, capacities, requirements, states, and deployment properties.
3. Normalize service, storage, and deterministic package anchors against those references.
4. Add negative requirement, carrying, deployment, and state adjustments.
5. Test boxed and bundled objects against their resolved children and quantities.
6. Activate the calibrated model, restore only deliberate Building sandbox controls, and bump the heuristic cache version again.

Until that sequence is complete, a neutral price is preferable to a false precision price, while the resolver exposes the evidence needed to finish the model.
