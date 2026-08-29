"""Fast, pure view filters for the cached GUI result.

The evaluator intentionally keeps its CLI semantics: command-line filters are
scan inputs.  The desktop inspector has a different workflow.  It scans and
caches the complete item universe once, then uses this module to narrow the
already-evaluated rows without touching Workshop discovery, Lua, or the disk
cache.
"""

from __future__ import annotations

from collections import Counter, defaultdict
from typing import Any, Iterable

from .heuristics import heuristic_coverage
from .reporting import price_distribution, price_stats
from .review import low_confidence_rows, review_count, review_row


AVAILABILITY_FILTERS = {
    "obtainable only": "obtainable",
    "obtainable": "obtainable",
    "all items": "all",
    "all": "all",
    "uncertain only": "uncertain",
    "uncertain": "uncertain",
    "excluded only": "excluded",
    "excluded": "excluded",
}


def normalize_view_availability(value: str | None) -> str:
    """Normalize a GUI label to the runtime availability status name."""

    return AVAILABILITY_FILTERS.get(
        str(value or "obtainable").strip().casefold(), "obtainable"
    )


def row_mod_id(row: dict[str, Any]) -> str:
    """Return the stable mod identity emitted by the Lua bridge."""

    return str(row.get("workshopMod") or row.get("mod") or "").strip()


def is_vanilla_row(row: dict[str, Any]) -> bool:
    """Identify base-game rows using the bridge's existing ``Base`` marker."""

    return row_mod_id(row).casefold() in {"base", "vanilla", "project zomboid"}


def row_availability(row: dict[str, Any]) -> str:
    availability = row.get("availability")
    if isinstance(availability, dict):
        return str(availability.get("status") or "uncertain").casefold()
    return "uncertain"


def _matches_mod(row: dict[str, Any], terms: tuple[str, ...]) -> bool:
    if not terms:
        return True
    row_id = row_mod_id(row).casefold()
    row_name = str(row.get("workshopName") or "").casefold()
    return any(
        term.casefold() == row_id
        or term.casefold() in row_id
        or term.casefold() in row_name
        for term in terms
        if str(term).strip()
    )


def filter_rows(
    rows: Iterable[dict[str, Any]],
    availability: str | None = "obtainable",
    mod_filters: tuple[str, ...] = (),
    skip_vanilla: bool = False,
    max_items: int = 0,
) -> list[dict[str, Any]]:
    """Filter cached rows without evaluating or rediscovering anything.

    A selected Workshop mod means that only that mod's rows are shown.  With
    ``All`` selected, ``skip_vanilla`` controls whether Base rows remain in
    the view.  Availability is read from the Lua-emitted runtime record, so
    the GUI does not introduce a second eligibility implementation.
    """

    selected_availability = normalize_view_availability(availability)
    visible: list[dict[str, Any]] = []
    for row in rows:
        if mod_filters:
            if not _matches_mod(row, mod_filters):
                continue
        elif skip_vanilla and is_vanilla_row(row):
            continue
        if (
            selected_availability != "all"
            and row_availability(row) != selected_availability
        ):
            continue
        visible.append(row)
    if max_items > 0:
        return visible[:max_items]
    return visible


def _valid_rows(rows: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
    return [
        row for row in rows
        if not row.get("error") and isinstance(row.get("price"), (int, float))
    ]


def _category_summary(rows: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    categories: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in _valid_rows(rows):
        categories[str(row.get("category") or "Unknown")].append(row)
    output: dict[str, dict[str, Any]] = {}
    for category, category_rows in sorted(categories.items()):
        stats = price_stats(category_rows)
        stats["primaries"] = Counter(
            str(row.get("primary") or "Unknown")
            for row in category_rows
        ).most_common(5)
        output[category] = stats
    return output


def view_summary(
    master_summary: dict[str, Any],
    rows: list[dict[str, Any]],
    master_rows: list[dict[str, Any]],
    availability: str | None,
) -> dict[str, Any]:
    """Recalculate presentation statistics for a filtered view.

    Metadata about the expensive scan (Workshop script counts, cache path,
    static audit counts, and detected mod list) is retained from the master
    summary.  Counts and charts that describe what the user currently sees
    are recomputed from the visible rows.
    """

    valid = _valid_rows(rows)
    summary = dict(master_summary)
    threshold = float(master_summary.get("confidence_threshold") or 0.5)
    status_counts = Counter(review_row(row)[0] for row in rows)
    availability_counts = Counter(row_availability(row) for row in rows)
    vanilla_items = sum(1 for row in rows if is_vanilla_row(row))
    summary.update({
        "evaluated": len(rows),
        "unique_items": len(rows),
        "listed_items": len(rows),
        "errors": len(rows) - len(valid),
        "categories": _category_summary(rows),
        "prices": price_stats(valid),
        "price_distribution": price_distribution(valid),
        "fallback_or_low_confidence": sum(
            1 for row in valid
            if float(row.get("confidence") or 0) < threshold
        ),
        "low_confidence_count": len(low_confidence_rows(rows, threshold)),
        "heuristic_coverage": heuristic_coverage(valid),
        "review_count": review_count(rows),
        "review_statuses": dict(status_counts),
        "vanilla_items": vanilla_items,
        "workshop_items": len(rows) - vanilla_items,
        "mods_with_items": dict(Counter(
            row_mod_id(row) or "Unknown"
            for row in valid
            if not is_vanilla_row(row)
        )),
        "availability_filter": normalize_view_availability(availability),
        "availability_counts": {
            "obtainable": availability_counts.get("obtainable", 0),
            "uncertain": availability_counts.get("uncertain", 0),
            "excluded": availability_counts.get("excluded", 0),
        },
        "master_evaluated": len(master_rows),
        "view_filtered_out": max(0, len(master_rows) - len(rows)),
    })
    return summary
