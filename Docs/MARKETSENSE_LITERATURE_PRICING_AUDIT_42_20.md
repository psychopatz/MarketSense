# MarketSense Literature Pricing Audit — Project Zomboid 42.20

## Scope

This audit covers the Literature root and its current MarketSense pricing and
classification boundaries. The objective is a deterministic value based on
the usefulness of the item to the player, not a fixed price attached to a
display label such as `SkillBook` or `Magazine`.

The existing 42.20 subcategory audit reports approximately 539 literature
definitions, including recipes, skill books, softcovers, magazines,
hardcovers, junk literature, maps, and six hollow-book variants. That is wide
enough that one root addition or one subtype bonus cannot be a reliable price
model.

## Current structure

- `MS_RootArbiter` identifies Literature from display category, item type,
  map/recipe/skill evidence, and literature instances.
- `MS_Sig_Literature` classifies hollow books, writable items, recipes, skill
  books, maps, consumables, newspapers, picture books, covers, magazines,
  photos, and generic/junk literature.
- `MS_PropertyReader` already exposes learned recipes, skill name and levels,
  read type, boredom/unhappiness/stress changes, writing capability, weight,
  and runtime literature identity.
- Project Zomboid's Literature class also exposes number of pages, already-read
  pages, known recipes, read type, skill levels, writing state, and whether
  entertainment effects are still active. These fields are suitable inputs,
  but several are not currently carried by `MS_PropertyReader` and should be
  added deliberately during implementation.
- The pricing path previously used a generic Literature base plus flat root
  and subtype additions. The live sandbox contained root, book, cards, media,
  recipe, and skill-book price options. Some generated values conflicted,
  including a negative media value versus a positive category addition.

## Legacy reset

The flat Literature price additions and Literature price sandbox options have
been removed from the active path. Stock multipliers, classification tags,
exact item overrides, and module overrides remain available. Literature rows
now use a neutral fallback and expose:

```text
priceHeuristic.model = "literature_v2_pending"
priceHeuristic.status = "pending"
```

This keeps the catalog usable while making it impossible to mistake the old
flat prices for a completed heuristic. The pricing cache version is bumped so
old materialized Literature values are rebuilt.

## Recommended value model

Use one normalized feature vector with separate utility dimensions:

```text
knowledgeUtility       = skill progression + recipe unlock utility
informationUtility     = map or unique information value
entertainmentUtility   = boredom/stress/unhappiness relief
physicalUtility        = writing, collection, or hollow-book utility
stateFactor             = unread content, known content, blank/used state
formatCost              = reading time, weight, and carrying opportunity cost
```

The price should then be bounded and composed from the appropriate literature
family rather than summed from arbitrary tags:

```text
price = clamp(round(
    familyAnchor
    * (1 + knowledgeUtility + informationUtility + entertainmentUtility)
    * stateFactor
    * formatFactor
    + physicalUtility
), floor, ceiling)
```

The exact coefficients should be calibrated against representative vanilla
items after the evidence flow is complete. No numerical anchors are approved
by this reset.

## Positive anchors

### Skill books

- skill identity, when valid and non-empty;
- starting skill level and maximum level trained;
- number of levels covered;
- whether the book is still useful to the target player, when player state is
  intentionally supplied;
- reading effects that remain available before the book is finished.

Skill identity alone should not create a high price. A skill book's value comes
from the amount of progression it enables. Player knowledge should be an
optional runtime adjustment, not part of the static catalog price.

### Recipe literature

- number of recipes unlocked;
- recipe family and practical utility;
- whether recipes are craft, build, farming, survival, or otherwise useful;
- whether the recipe is already known to the player, when runtime state is
  available.

Each recipe should not automatically have equal value. A bounded count factor
plus a recipe-utility class is safer than a fixed per-recipe dollar amount.

### Maps and information

- map identity and whether it reveals a meaningful location or region;
- unique information unavailable from ordinary literature;
- whether reading consumes or permanently completes the information.

The current classifier can identify maps, but map coverage/detail should be
kept separate from the generic `LiteratureMap` label if the game exposes it.

### Entertainment and ordinary reading

- negative boredom change is beneficial;
- negative unhappiness change is beneficial;
- negative stress change is beneficial;
- readable/consumable purpose when it provides a real player effect.

These effects must use the native signed values. A positive boredom,
unhappiness, or stress change is a penalty, not a positive price anchor.

### Physical or hybrid utility

- writable blank pages provide a small utility value;
- hollow books should receive a separate storage/concealment value if their
  capacity and use are verified;
- collectible or presentation value may be a small bounded role factor.

## Negative anchors

- already-read pages or already-known recipes;
- empty, consumed, blank, damaged, or otherwise unusable content;
- `LiteratureOrJunk` when no positive utility evidence exists;
- long reading time when it gives no additional utility;
- weight and carrying cost, especially for low-value bulk literature;
- physical format cost without additional knowledge or entertainment;
- a writable flag by itself should not imply instructional value;
- a rare or themed label should not override missing usefulness evidence.

`canBeWrite` is a capability, not automatically a penalty: an empty notebook
may be useful as writing material, while a writable item with no meaningful
content should not be priced like a skill book.

## Classification concerns to resolve before calibration

1. The classifier currently checks `canBeWrite` before recipe and skill-book
   evidence. This can turn a multi-purpose writable item into
   `LiteratureOrJunk`; precedence should preserve stronger knowledge evidence.
2. Hollow books are currently kept under Literature to protect their semantic
   identity. Pricing should inspect verified container/storage utility instead
   of treating every hollow-book variant as an ordinary book.
3. Generic literature must remain a low-confidence/low-utility family, not a
   large negative flat adjustment. The debug view should show why it received
   that result.
4. Static catalog prices must not depend on player-specific knowledge unless a
   runtime instance/profile is explicitly passed. Static and runtime pricing
   should be visibly distinct.

## Implementation order

1. Add a dedicated `MS_LiteraturePricing` module and keep `MS_Pricing` as the
   category dispatcher.
2. Extend `MS_PropertyReader` with verified page/read-state/known-recipe
   fields and explicit availability flags.
3. Correct literature evidence precedence and preserve the existing
   subcategory taxonomy.
4. Implement family anchors for skill books, recipes, maps, entertainment,
   physical/hybrid, and generic literature.
5. Add bounded state and format factors, then calibrate against a representative
   42.20 sample.
6. Add monotonicity tests for level span, recipe count, signed mood effects,
   map utility, already-read state, and hollow-book capacity.
7. Keep the heuristic object and audit trail in the resolver/export output so
   false positives and missing evidence remain inspectable.
