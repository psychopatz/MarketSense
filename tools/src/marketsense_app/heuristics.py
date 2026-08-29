"""Compact audit helpers for finding items that still use broad buckets.

The Lua classifier remains authoritative.  This module only interprets the
classification provenance that Lua already exposes so the harness can answer
"which rows still need a more specific heuristic?" without inventing a second
classifier.
"""

from __future__ import annotations

from collections import Counter, defaultdict
from typing import Any


# These are intentionally conservative.  A fallback resolver by itself is not
# a gap: several valid specialised tags use one.  A row is actionable here
# only when the final primary tag is broad/root-only or the classifier reports
# that RootArbiter selected the broad bucket.
GENERIC_PRIMARY_BUCKETS = frozenset({
    "building",
    "buildingfurniture",
    "buildingmoveable",
    "electronics",
    "gardening",
    "misc",
})

_ROOT_ONLY_SUBCATEGORIES = frozenset({"", "general"})
_KIND_ORDER = {"missing": 0, "fallback": 1, "generic": 2, "root_only": 3}


def _text(value: Any) -> str:
    return str(value or "").strip()


def _number(value: Any) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def _hierarchy_value(row: dict[str, Any], key: str, default: str = "") -> str:
    value = _text(row.get(key))
    if value:
        return value
    hierarchy = row.get("hierarchy")
    if isinstance(hierarchy, dict):
        aliases = {"category": "root", "primary": "token"}
        return (
            _text(hierarchy.get(key))
            or _text(hierarchy.get(aliases.get(key, "")))
            or default
        )
    return default


def heuristic_gap(row: dict[str, Any]) -> dict[str, Any] | None:
    """Return a compact, actionable gap record or ``None``.

    The result is a review hint, not a false-positive verdict.  In particular,
    specialised categories with ``root_fallback`` remain clean when their
    primary tag is specific (for example ``MaterialButchering``).
    """

    if _text(row.get("error")):
        return None

    category = _hierarchy_value(row, "category", "Unclassified")
    subcategory = _hierarchy_value(row, "subcategory", "General")
    primary = _hierarchy_value(row, "primary", "Unclassified")
    detector = _text(row.get("detector"))
    resolver = _text(row.get("resolver"))
    category_cf = category.casefold()
    subcategory_cf = subcategory.casefold()
    primary_cf = primary.casefold()
    detector_cf = detector.casefold()

    if category == "Unclassified" or primary == "Unclassified":
        kind = "missing"
        bucket = category if category != "Unclassified" else primary
        reason = "missing category or primary; no stable heuristic target"
    elif primary_cf in GENERIC_PRIMARY_BUCKETS:
        # RootArbiter + a broad final tag is the strongest signal that no
        # specific signature matched.  Other detectors still deserve a
        # generic-bucket review, but are not called fallback failures.
        kind = "fallback" if detector_cf == "rootarbiter" else "generic"
        bucket = primary
        if kind == "fallback":
            reason = (
                f"RootArbiter selected broad bucket {primary}; inspect item evidence "
                "for a more-specific signature"
            )
        else:
            reason = (
                f"broad primary bucket {primary}; inspect item evidence before "
                "adding a more-specific signature"
            )
    elif (
        category_cf == primary_cf
        and subcategory_cf in _ROOT_ONLY_SUBCATEGORIES
    ):
        # This includes root-only Food/Tool/Container/Clothing rows, but does
        # not accuse specialised children such as Misc > Junk or Resource >
        # Material > Butchering of being wrong.
        kind = "fallback" if detector_cf == "rootarbiter" else "root_only"
        bucket = primary
        if kind == "fallback":
            reason = (
                f"RootArbiter left item in root-only bucket {primary}; inspect item "
                "evidence for a more-specific signature"
            )
        else:
            reason = (
                f"category and primary are both {primary} with a General subcategory; "
                "check for a more-specific signature"
            )
    else:
        return None

    path = _text(row.get("categoryPath"))
    if not path:
        path = " > ".join(part for part in (category, subcategory, primary) if part)
    return {
        "kind": kind,
        "bucket": bucket,
        "reason": reason,
        "category": category,
        "subcategory": subcategory,
        "primary": primary,
        "categoryPath": path,
        "detector": detector,
        "resolver": resolver,
        "confidence": row.get("confidence", 0),
        "workshopMod": _text(row.get("workshopMod")),
        "fullType": _text(row.get("fullType")),
    }


def heuristic_gap_rows(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Return original rows requiring heuristic-gap review in stable order."""

    selected = [row for row in rows if heuristic_gap(row) is not None]
    return sorted(
        selected,
        key=lambda row: (
            _KIND_ORDER.get((heuristic_gap(row) or {}).get("kind", ""), 99),
            _number(row.get("confidence")),
            _text(row.get("fullType")),
        ),
    )


def compact_heuristic_gap(row: dict[str, Any]) -> dict[str, Any] | None:
    """Build the small row shape used by terminal summaries and exports."""

    gap = heuristic_gap(row)
    if gap is None:
        return None
    return gap


def heuristic_kind_label(kind: Any) -> str:
    """Return a human-readable label without changing the JSON key."""

    return {"root_only": "root-only"}.get(_text(kind), _text(kind))


def heuristic_coverage(
    rows: list[dict[str, Any]], example_limit: int = 12,
) -> dict[str, Any]:
    """Return aggregate counts plus a bounded set of representative examples."""

    selected = heuristic_gap_rows(rows)
    gaps = {id(row): heuristic_gap(row) for row in selected}
    bucket_counts = Counter(
        _text(gaps[id(row)].get("bucket")) for row in selected if gaps[id(row)]
    )
    kind_counts = Counter(
        _text(gaps[id(row)].get("kind")) for row in selected if gaps[id(row)]
    )
    mod_counts = Counter(
        _text(row.get("workshopMod")) or "Unknown"
        for row in selected
    )

    # One example per bucket makes the compact report useful across a large
    # hot-swapped Workshop set; fill remaining slots by normal severity order.
    grouped: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in selected:
        gap = gaps[id(row)]
        if gap:
            grouped[_text(gap.get("bucket"))].append(row)
    bucket_order = sorted(
        grouped, key=lambda bucket: (-len(grouped[bucket]), bucket.casefold())
    )
    examples: list[dict[str, Any]] = []
    seen: set[int] = set()
    for bucket in bucket_order:
        if len(examples) >= max(0, example_limit):
            break
        row = grouped[bucket][0]
        seen.add(id(row))
        compact = compact_heuristic_gap(row)
        if compact:
            examples.append(compact)
    for row in selected:
        if len(examples) >= max(0, example_limit) or id(row) in seen:
            continue
        compact = compact_heuristic_gap(row)
        if compact:
            examples.append(compact)

    return {
        "candidate_count": len(selected),
        "bucket_counts": dict(sorted(
            bucket_counts.items(), key=lambda item: (-item[1], item[0].casefold())
        )),
        "kind_counts": dict(sorted(
            kind_counts.items(), key=lambda item: (_KIND_ORDER.get(item[0], 99), item[0])
        )),
        "mod_counts": dict(sorted(
            mod_counts.items(), key=lambda item: (-item[1], item[0].casefold())
        )),
        "example_limit": max(0, example_limit),
        "examples": examples,
        "interpretation": "triage candidates only; not confirmed false positives",
    }
