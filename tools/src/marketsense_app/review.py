"""Conservative, explainable review flags for offline classification inspection.

These flags are triage hints for the inspector.  They do not assert that an
item is misclassified; the user still needs to inspect the item's definition
and the evaluator evidence before changing a heuristic.
"""

from __future__ import annotations

from typing import Any


CONFIDENCE_REVIEW_THRESHOLD = 0.5


def _text(value: Any) -> str:
    return str(value or "").strip()


def _number(value: Any) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def _sequence_text(value: Any) -> str:
    if isinstance(value, (list, tuple)):
        return ", ".join(_text(item) for item in value if _text(item))
    return _text(value)


def review_row(row: dict[str, Any]) -> tuple[str, str]:
    """Return ``(status, reason)`` for one evaluated row.

    ``REVIEW`` means that a row has evidence worth checking, not that a false
    positive has been proven.  The rules intentionally use only fields emitted
    by the real MarketSense Lua bridge, so the GUI cannot silently invent a
    second classification model.
    """

    error = _text(row.get("error"))
    if error:
        return "ERROR", f"evaluation error: {error}"

    reasons: list[str] = []
    category = _text(row.get("category"))
    primary = _text(row.get("primary"))
    source = _text(row.get("source"))
    expanded_tags = row.get("expandedTags") or []

    if not category or not primary:
        reasons.append("missing category or primary tag")
    if category.casefold() == "misc" or primary.casefold() == "misc":
        reasons.append("broad Misc bucket")
    if "fallback" in source.casefold() or "missing_context" in source.casefold():
        reasons.append(f"fallback resolver ({source})")
    if _number(row.get("confidence")) < CONFIDENCE_REVIEW_THRESHOLD:
        reasons.append(
            f"low confidence ({_number(row.get('confidence')):.2f} < "
            f"{CONFIDENCE_REVIEW_THRESHOLD:.2f})"
        )
    if isinstance(expanded_tags, (list, tuple)) and category:
        expanded = {_text(tag).casefold() for tag in expanded_tags if _text(tag)}
        if expanded and category.casefold() not in expanded:
            reasons.append("category is absent from expanded tags")

    if reasons:
        return "REVIEW", "; ".join(reasons)
    return "OK", "classification has no automatic review flags"


def searchable_text(row: dict[str, Any]) -> str:
    """Build a case-insensitive search haystack from all useful item evidence."""

    status, reason = review_row(row)
    fields = (
        row.get("fullType"), row.get("category"), row.get("primary"),
        row.get("subcategory"), row.get("leaf"), row.get("primaryPrefix"),
        row.get("categoryPath"), row.get("detector"), row.get("resolver"),
        row.get("source"), row.get("workshopMod"), row.get("workshopName"),
        row.get("workshopId"), row.get("workshopVersion"), row.get("description"),
        _sequence_text(row.get("tags")), _sequence_text(row.get("expandedTags")),
        _sequence_text(row.get("definitionSources")), status, reason,
    )
    availability = row.get("availability")
    if isinstance(availability, dict):
        fields += (
            availability.get("status"), availability.get("reason"),
            _sequence_text(availability.get("channels")),
            _sequence_text(availability.get("channelLabels")),
            _sequence_text(availability.get("references")),
            _sequence_text(availability.get("exclusions")),
        )
    return " ".join(_text(field) for field in fields if _text(field)).casefold()


def low_confidence_rows(
    rows: list[dict[str, Any]], threshold: float = CONFIDENCE_REVIEW_THRESHOLD,
) -> list[dict[str, Any]]:
    """Return evaluable rows below the requested confidence threshold."""

    return sorted(
        (
            row for row in rows
            if not _text(row.get("error")) and _number(row.get("confidence")) < threshold
        ),
        key=lambda row: (_number(row.get("confidence")), _text(row.get("fullType"))),
    )


def review_count(rows: list[dict[str, Any]]) -> int:
    return sum(1 for row in rows if review_row(row)[0] != "OK")
