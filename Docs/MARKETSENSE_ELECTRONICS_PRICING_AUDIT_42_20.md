# MarketSense electronics pricing audit and reset (Project Zomboid 42.20)

## Decision

Electronics pricing is reset to a visible `electronics_v2_pending` heuristic.
The old model used a generic weight penalty and flat dollars for generators,
batteries, radios, lights, and televisions. Those values were not comparable:
a flashlight, a powered appliance, a two-way radio, and a generator do not
deliver the same kind of player utility.

All `PriceElectronics*` controls, electronics price-tag additions, and the
legacy electronics category coefficients are removed. `StockElectronics*`
controls remain because supply pressure is separate from item usefulness.
Exact item and module overrides remain authoritative. Pricing cache version 15
forces details generated with the old electronics score to be rebuilt.

The reset deliberately does not guess the final coefficients. The resolver,
debug catalog, and terminal expose the evidence needed to calibrate the model
against real items and modded items first.

## Current structure

The root arbiter admits electronics from display/category evidence, radio and
alarm-clock item types, flashlight/light-source signals, selected moveable
device names, and verified world-object appliance capability. The electronics
signature currently identifies these comparison families:

- generator, laundry, clock, and powered appliance;
- flashlight, light bulb, and generic light source;
- battery, power component, and transmitter;
- radio, communicator, audio, television, and entertainment;
- personal/control electronics and a generic electronics residual.

The family is classification evidence, not a price. A modded item should be
able to enter the same family through the same verified behavior or metadata
without requiring a per-name price entry. Classification precedence remains
important: a specific verified capability should win over a broad electronics
fallback, while name-only matches remain lower-confidence evidence.

## Engine evidence and boundaries

The 42.20 Java baseline exposes these useful item/device signals:

- `InventoryItem.getLightStrength()` and `getLightDistance()` expose light
  output and coverage when the item class provides them.
- `InventoryItem.canEmitLight()` is an operability signal. For drainable light
  items, the engine also checks remaining uses, so it must not be treated as a
  permanent light-quality value.
- `Moveable.isLightUseBattery()` and `Moveable.isLightHasBattery()` expose
  battery-backed light state when the item is a moveable light.
- `Radio.getDeviceData()` exposes optional `DeviceData`; the reader now records
  battery-powered state, battery presence, television/two-way/portable/high-tier
  flags, channel bounds, transmit range, power state, and on/off state when
  available.
- `DeviceData.getPower()` returns the device's `powerDelta` state. It is not a
  universal generator-output or electrical-capacity number and must not receive
  a price coefficient without a family-specific interpretation.
- `DeviceData.getBattery(ItemContainer)` requires a container argument. The
  static catalog reader intentionally does not call it without an inventory
  context.
- World-object evidence can establish capabilities such as washing, drying,
  time display, electric appliance, and operating requirements. This evidence
  is not automatically available for every inventory item, so it must remain
  separate from portable item metadata.
- Generator fuel consumption and world-object generator behavior must be
  measured through the relevant world-object APIs. A name containing
  “generator” is not output evidence.

Missing methods or missing runtime objects are represented as unavailable.
They contribute zero until a safe source is found; they do not receive a
fabricated default and they do not imply a negative value.

## Recommended primitive pricing model

Use one bounded model with family-specific anchors and shared state/cost terms:

```text
familyAnchor = calibrated baseline for the electronics family
serviceUtility = diminishing-return function of verified functional output
stateFactor = condition × charge/uses × operability
accessFactor = portability/deployability/access when mechanically verified
carryingCost = weight, bulk, placement, and operating burden

price = clamp(round(
    familyAnchor
    × (1 + serviceUtility)
    × stateFactor
    × accessFactor
    + repairOrComponentUtility
    - carryingCost
    - operatingCost
), floor, ceiling)
```

This is the design contract, not a final coefficient set. The functions must
be normalized within a family and capped so one raw field cannot dominate all
others. The model should be monotonic within a family: more verified service,
coverage, remaining charge, or usable lifetime cannot lower the price of an
otherwise equivalent item.

Static catalog pricing should use script/item metadata and stable capability
evidence. Runtime pricing may additionally use current condition, battery,
remaining uses, and on/off/operability state when an item instance is supplied.
Player traits, current power availability, and character-specific access must
not be baked into a static catalog price.

## Positive anchors

- Verified functional role: the player action or service the item actually
  enables, with a family baseline so unlike roles remain comparable.
- Lights: light strength multiplied by coverage distance, with diminishing
  returns; `canEmitLight` and remaining charge determine whether that output is
  currently usable.
- Radios and communicators: receive/transmit capability, two-way operation,
  channel coverage, transmit range, and portability. High-tier flags matter
  only when they unlock a verified capability rather than merely naming a tier.
- Batteries and power components: measured remaining charge/uses, maximum
  usable capacity, compatible devices, and reusable component/recipe utility.
  Empty cells should retain only their verified component value.
- Generators and powered appliances: verified electrical service, output or
  coverage, fuel efficiency, and the actions made available while operating.
  These should be sourced from the correct world/device APIs, not a flat name
  bonus.
- Television, audio, and entertainment devices: verified entertainment or
  communication function, content/access coverage, and portability where the
  player can actually use it.
- Repairability, dismantling, compatible recipes, and reusable components when
  the recipe/action graph explicitly resolves them. This is secondary utility,
  not a replacement for the device's primary function.
- Deployability and portability when the item can be carried, equipped, or
  placed in a useful location by a verified mechanic.

## Negative anchors

- Weight, bulk, encumbrance, and placement burden relative to delivered service.
- Broken or low-condition state, depleted battery, exhausted uses, and an
  emitted-light/device state that is currently inoperable.
- Electricity, fuel, water, or other recurring operating requirements when the
  requirement is mechanically evidenced. A requirement should reduce net
  utility; it should not erase the item's replacement/component value.
- Stationary-only access, narrow radio range, weak light coverage, limited
  channel coverage, and incompatible power sources.
- Noise, visibility, risk, maintenance, and repair burden only when the game or
  a trusted mod API exposes them as actual player costs.
- Redundancy or a narrower capability compared with a broader item in the same
  family, using bounded relative utility rather than arbitrary penalties.
- Ambiguous name/tag classification, rarity, theme, or display labels without
  functional evidence. These may explain a diagnostic classification but must
  not create a large price by themselves.

## Family treatment

- **Portable lights:** service is strength × distance; charge, battery
  dependence, weight, and equip/access cost modify it. A light bulb should not
  inherit flashlight portability.
- **Radios and communicators:** range and communication mode are the core
  anchors. Receive-only, two-way, transmitter, television, and portable radio
  roles need separate family baselines to avoid paying twice for the same
  signal.
- **Batteries and power parts:** price measured usable energy or compatible
  component utility. Do not price the word “battery” as if every cell had the
  same charge.
- **Generators and appliances:** price verified service and resource
  efficiency. World-object power consumption is an operating cost, not output;
  inventory items without a safe output signal remain pending/low-evidence.
- **Television, audio, and entertainment:** use confirmed access/function and
  portability. A visual television signal only selects the family; it is not
  proof of broadcast range or content value.
- **Control, personal, and generic electronics:** require an explicit action,
  compatibility, or recipe signal for a material uplift. Otherwise use the
  residual baseline and expose the lack of evidence.

## Calibration and implementation order

1. Keep the pending heuristic and evidence fields visible in the resolver,
   debug catalog, and terminal. This reset is complete.
2. Build a small reference set for each family: light, battery, receive-only
   radio, two-way radio, transmitter, television, appliance, and generator.
3. Normalize each functional signal against that family and add bounded,
   diminishing-return anchors. Add no sandbox flat-price controls back.
4. Add runtime charge/condition/use-state factors and explicit availability
   flags. Keep static and runtime scores distinguishable.
5. Add verified repair, dismantling, compatibility, and reusable recipe utility
   without counting the same child/component value twice.
6. Calibrate against monotonic and cross-family fixtures, then promote the
   model from `pending` to an active version and bump the cache version again.

Required invariants include:

- higher light strength or distance cannot lower price within a light family;
- greater radio/transmit range or two-way capability cannot lower price;
- more charge/uses and better condition cannot lower price;
- depleted or inoperable instances cannot exceed equivalent usable instances;
- heavier equal-function electronics cannot outrank the lighter item solely due
  to weight;
- missing evidence cannot beat resolved evidence merely because of a name;
- static catalog values do not change from player traits or current world power;
- a nested component/recipe contribution is included at most once.
