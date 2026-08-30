"""Compare offline harness rows with the MarketSense runtime cache."""

from __future__ import annotations

import math
from collections import Counter
from pathlib import Path
from typing import Any, Iterable

from .runtime_loading import load_runtime_items
from .runtime_values import _integer, _number, _primary, _tags

def _hierarchy(row: dict[str, Any]) -> dict[str, str]:
    hierarchy = row.get("hierarchy")
    hierarchy = hierarchy if isinstance(hierarchy, dict) else {}
    return {
        "category": str(row.get("category") or hierarchy.get("root") or ""),
        "subcategory": str(row.get("subcategory") or hierarchy.get("subcategory") or ""),
        "leaf": str(row.get("leaf") or hierarchy.get("leaf") or ""),
        "primaryPrefix": str(
            row.get("primaryPrefix") or hierarchy.get("primaryPrefix") or ""
        ),
    }

def _expected_base_stock(row: dict[str, Any]) -> dict[str, int] | None:
    value = row.get("baseStock")
    if not isinstance(value, dict):
        return None
    minimum = _integer(value.get("min"))
    maximum = _integer(value.get("max"))
    if minimum is None or maximum is None:
        return None
    return {"min": minimum, "max": maximum}


def _compact_expected(row: dict[str, Any]) -> dict[str, Any]:
    output: dict[str, Any] = {
        "tags": _tags(row.get("tags")),
        "primary": str(row.get("primary") or ""),
        **_hierarchy(row),
    }
    if row.get("basePrice") is not None:
        output["basePrice"] = row.get("basePrice")
    base_stock = _expected_base_stock(row)
    if base_stock is not None:
        output["stock"] = base_stock
    return output


def _compact_runtime(item: dict[str, Any]) -> dict[str, Any]:
    return {
        "tags": _tags(item.get("tags")),
        "primary": _primary(_tags(item.get("tags"))),
        "category": item.get("category", ""),
        "subcategory": item.get("subcategory", ""),
        "leaf": item.get("leaf", ""),
        "primaryPrefix": item.get("primaryPrefix", ""),
        "basePrice": item.get("basePrice"),
        "stock": item.get("stock") or {},
        "origin": item.get("origin", ""),
        "path": item.get("path", ""),
    }


def _same_number(left: Any, right: Any) -> bool:
    left_number = _number(left)
    right_number = _number(right)
    if left_number is None or right_number is None:
        return False
    return math.isclose(float(left_number), float(right_number), abs_tol=0.01)


def _item_difference(expected: dict[str, Any], actual: dict[str, Any]) -> dict[str, Any]:
    fields: list[str] = []
    expected_tags = _tags(expected.get("tags"))
    actual_tags = _tags(actual.get("tags"))
    if expected_tags != actual_tags:
        fields.append("tags")

    expected_primary = str(expected.get("primary") or "")
    actual_primary = _primary(actual_tags)
    if expected_primary and expected_primary != actual_primary:
        fields.append("primary")

    for field in ("category", "subcategory", "leaf", "primaryPrefix"):
        expected_value = str(expected.get(field) or "")
        actual_value = str(actual.get(field) or "")
        if expected_value and expected_value != actual_value:
            fields.append(field)

    if "basePrice" in expected and not _same_number(
        expected.get("basePrice"), actual.get("basePrice")
    ):
        fields.append("basePrice")

    expected_stock = expected.get("stock")
    actual_stock = actual.get("stock")
    if isinstance(expected_stock, dict) and isinstance(actual_stock, dict):
        if (
            _integer(expected_stock.get("min")) != _integer(actual_stock.get("min"))
            or _integer(expected_stock.get("max")) != _integer(actual_stock.get("max"))
        ):
            fields.append("stock")

    return {
        "fullType": expected.get("fullType") or actual.get("fullType") or "",
        "status": "match" if not fields else "mismatch",
        "fields": fields,
        "expected": _compact_expected(expected),
        "actual": _compact_runtime(actual),
    }


def compare_harness_to_runtime(
    harness_rows: Iterable[dict[str, Any]], runtime_dir: Path,
) -> dict[str, Any]:
    """Compare obtainable offline rows with the PZ-generated runtime cache.

    ``MS_Items`` is a lean cache: its price column is the generated base price,
    not the final lazy ``GetPriceDetails`` value.  The harness therefore uses
    its explicit ``basePrice``/``baseStock`` fields when available and reports
    missing fields as incomplete instead of manufacturing a false mismatch.
    """

    runtime_items, runtime_metadata = load_runtime_items(runtime_dir)
    harness_by_type: dict[str, dict[str, Any]] = {}
    harness_errors = 0
    non_obtainable = 0
    for row in harness_rows:
        if not isinstance(row, dict):
            continue
        full_type = str(row.get("fullType") or "")
        if not full_type or row.get("error"):
            harness_errors += 1
            continue
        availability = row.get("availability")
        availability_status = (
            str(availability.get("status") or "uncertain")
            if isinstance(availability, dict) else "uncertain"
        )
        if availability_status != "obtainable":
            non_obtainable += 1
            continue
        harness_by_type[full_type] = row

    differences: list[dict[str, Any]] = []
    field_counts: Counter[str] = Counter()
    unavailable_fields: Counter[str] = Counter()
    for error in runtime_metadata.get("parseErrors") or []:
        error_field = "index" if error.get("kind") == "index" else "parse"
        error_status = (
            "runtime-index-error" if error_field == "index"
            else "runtime-parse-error"
        )
        differences.append({
            "fullType": error.get("fullType", "<runtime file>"),
            "status": error_status,
            "fields": [error_field],
            "expected": None,
            "actual": error,
        })
        field_counts[error_field] += 1
    index_metadata = runtime_metadata.get("index") or {}
    unindexed_files = index_metadata.get("unindexedFiles") or []
    if unindexed_files:
        differences.append({
            "fullType": "<runtime cache>",
            "status": "runtime-unindexed-files",
            "fields": ["index"],
            "expected": None,
            "actual": {
                "message": "Text files exist below MS_Items but are not referenced by MS_ItemsIndex.txt.",
                "files": unindexed_files,
            },
        })
        field_counts["index"] += 1
    for full_type in sorted(set(harness_by_type) | set(runtime_items)):
        expected = harness_by_type.get(full_type)
        actual = runtime_items.get(full_type)
        if expected is None:
            difference = {
                "fullType": full_type,
                "status": "unexpected-runtime",
                "fields": ["membership"],
                "expected": None,
                "actual": _compact_runtime(actual or {}),
            }
            differences.append(difference)
            field_counts["membership"] += 1
            continue
        if actual is None:
            difference = {
                "fullType": full_type,
                "status": "missing-runtime",
                "fields": ["membership"],
                "expected": _compact_expected(expected),
                "actual": None,
            }
            differences.append(difference)
            field_counts["membership"] += 1
            continue

        expected_base_price = expected.get("basePrice")
        if expected_base_price is None:
            unavailable_fields["basePrice"] += 1
        if _expected_base_stock(expected) is None:
            unavailable_fields["stock"] += 1
        difference = _item_difference(
            {"fullType": full_type, **_compact_expected(expected)},
            actual,
        )
        if difference["status"] != "match":
            differences.append(difference)
            for field in difference["fields"]:
                field_counts[field] += 1

    mismatch_count = sum(
        1 for difference in differences if difference["status"] == "mismatch"
    )
    missing_count = sum(
        1 for difference in differences if difference["status"] == "missing-runtime"
    )
    unexpected_count = sum(
        1 for difference in differences if difference["status"] == "unexpected-runtime"
    )
    incomplete = bool(unavailable_fields)
    has_failure = bool(
        differences or runtime_metadata["parseErrorCount"] or harness_errors
    )
    status = "mismatch" if has_failure else "incomplete" if incomplete else "match"

    return {
        "status": status,
        "runtime": runtime_metadata,
        "harnessItems": len(harness_by_type),
        "harnessNonObtainable": non_obtainable,
        "harnessErrors": harness_errors,
        "runtimeItems": len(runtime_items),
        "compared": len(harness_by_type) - missing_count,
        "matches": len(harness_by_type) - missing_count - mismatch_count,
        "differenceCount": len(differences),
        "mismatchCount": mismatch_count,
        "missingRuntimeCount": missing_count,
        "unexpectedRuntimeCount": unexpected_count,
        "fieldMismatches": dict(sorted(field_counts.items())),
        "unavailableFields": dict(sorted(unavailable_fields.items())),
        "differences": differences,
        "priceNote": (
            "MarketSense MS_Items stores generated basePrice. Final lazy GetPriceDetails price "
            "is not serialized in the MS_Items text schema."
        ),
    }
