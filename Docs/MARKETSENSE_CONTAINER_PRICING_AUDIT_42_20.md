# MarketSense container pricing audit and reset (Project Zomboid 42.20)

## Decision

Container pricing is reset to a visible `container_v2_pending` heuristic until
storage utility, carrying cost, portability, and deterministic contents are
normalized into one model. The previous score added raw capacity and weight
reduction, subtracted a generic item-weight penalty, and then stacked large flat
root/bag/subtype additions. That made a large heavy box, a wearable backpack,
an empty water vessel, and a medical kit incomparable.

All `PriceContainer*` controls and container flat tag additions are removed.
`StockContainer*` controls remain because stock pressure is independent from
storage utility. Exact item and module overrides remain authoritative.

## Current structure

The root arbiter checks liquid content before containers, then recognizes a
container from water-container display metadata, native container type,
capacity, an empty fluid container, or water-storage capability. A filled fluid
container is therefore priced by the separate `Liquid` subsystem while its
empty vessel remains `ContainerLiquid`.

The container signature currently separates bags and worn bags, wearable ammo,
ammo cases, boxes, liquid vessels, key rings, medical kits, coolers, tool rolls,
seed bags, wallets/personal storage, parcels, gifts, utility bags, and a generic
container residual. Body/equip slots are stronger evidence for worn bags than
names alone. The existing taxonomy audit found the main remaining gap in
`Container > General > General`: those rows should be refined by verified
container function, not by price labels.

## Engine evidence and important semantics

The 42.20 Java baseline gives the following usable boundaries:

- `InventoryContainer.getCapacity()` returns the container capacity after the
  engine's internal limit based on the item's actual weight.
- `InventoryContainer.getEffectiveCapacity(character)` can vary with character
  traits such as Organized or Disorganized. That player-specific result must not
  be baked into the static catalog price.
- `InventoryContainer.getWeightReduction()` is a separate integer reduction
  value and should be treated as carry utility, not as storage capacity.
- `ItemContainer.getCapacityWeight()` reports current contents/inventory weight;
  it is not the static advertised capacity and must not be used as the item
  anchor.
- `InventoryItem.getItemCapacity()` and `getMaxCapacity()` are generic item
  fields used by some item classes. They must only be used for container pricing
  after the item class and meaning are verified.

## Recommended pricing anchor

Use a family anchor, then price delivered storage utility and its cost:

```text
familyAnchor = calibrated anchor for bag, box, vessel, kit, or utility family
storageUtility = normalized usable capacity within that family
carryUtility = normalized weight reduction or saved carry weight
portabilityUtility = wearable/access utility when verified
specialFunction = verified ammo, medical, cooling, tool, seed, or personal use
contentUtility = deterministic child output value, when explicitly resolved
stateFactor = condition, damage, opened, empty/filled, and accessibility state
carryingCost = container weight relative to usable capacity and utility

price = clamp(round(
    familyAnchor × (1 + storageUtility + carryUtility
                    + portabilityUtility + specialFunction)
    × stateFactor - carryingCost + contentUtility
), floor, ceiling)
```

This is a design contract, not an approved coefficient set. Every numeric
feature needs bounded normalization and diminishing returns. Missing evidence
must contribute zero, not an invented default.

## Positive anchors

- Usable capacity relative to comparable containers in the same family.
- Weight reduction and the amount of carried weight saved.
- Verified wearable access or portability, including the appropriate body slot.
- Verified specialized utility: ammunition organization, medical storage,
  cooling/preservation, tool storage, seed storage, or personal organization.
- Deterministic child-content value when a recipe/yield resolver identifies the
  exact outputs and quantities. For example, a package yielding multiple child
  items should contribute the individualized child prices multiplied by their
  quantities, plus only a bounded package utility premium.
- Repairability and usable lifetime when the item exposes meaningful condition
  data and that evidence is not double-counted.

## Negative anchors

- Container weight and encumbrance relative to capacity and saved weight.
- Low capacity, unusable capacity, or an item that is only labeled as a container
  without functional storage evidence.
- Movement/access cost from a bulky or poorly portable container.
- Broken, damaged, or inaccessible state.
- Ambiguous, missing, or misleading package contents. Do not infer contents from
  “box of” text when no deterministic output source exists.
- Empty/filled state only when it is relevant to the item family. A filled fluid
  vessel must not be charged both for the fluid content and an invented container
  premium; the liquid subsystem owns the payload.
- Rarity, theme, luxury, or family labels without verified mechanical utility.

## Content and nested-container rule

Container utility and contained-item utility are separate dimensions. If a
resolver proves that a container opens into `n` instances of a child item, value
the child item individually and multiply by `n`. For mixed outputs, sum each
child's deterministic value. Add the reusable container's storage value only
when the opened package leaves a meaningful container behind; otherwise charge
only a bounded packaging/convenience adjustment. If outputs are ambiguous or
unresolved, expose that status and do not fabricate a yield value.

This rule is intentionally generic so it can support boxes, cartons, kits,
bundles, modded packages, and future recipe outputs without a per-item name
table.

## Family treatment

- Bags: capacity, weight reduction, wearable slot, and movement cost dominate.
- Boxes/crates/parcels: capacity and content yield dominate; portability and
  reusability determine whether the package adds lasting value.
- Liquid vessels: empty-vessel utility is separate; filled liquid value belongs
  to `Liquid` and is measured by the fluid subsystem.
- Ammo/medical/tool/seed containers: family function is useful only when the
  item actually provides that storage or access behavior.
- Wallets, key rings, gifts, and personal utility containers: modest anchors
  unless capacity or verified function justifies more.
- Generic residual containers: low baseline and no fabricated value for missing
  fields.

## Static versus runtime state

Static data determines family, advertised capacity, weight reduction, item weight,
wearability, and verified function. Runtime state determines current condition,
contents, opened/empty state, and character-specific effective capacity. Static
catalog pricing must not assume Organized/Disorganized traits or current contents.
Runtime pricing may apply those factors only when explicitly supplied.

## Implementation order

1. Keep the pending heuristic and expose capacity, weight reduction, weight,
   family, and content-yield evidence in resolver/debug/terminal output.
2. Add a dedicated `MS_ContainerPricing` module; keep `MS_Pricing` as the
   dispatcher.
3. Extend `MS_PropertyReader` with verified item-class/container fields and
   explicit availability flags, including content/instance state where safe.
4. Implement family anchors and bounded capacity/weight-reduction utility.
5. Integrate deterministic child yields exactly once and guard recursion for
   nested containers.
6. Add monotonic tests: more capacity must not lower price within a family;
   more weight reduction must not lower price; a heavier equal-capacity item
   must not become more valuable; unresolved content must not exceed resolved
   content solely because of a name; and filled liquid payloads must not change
   the empty-vessel valuation.
