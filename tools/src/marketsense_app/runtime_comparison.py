"""Compare offline harness rows with the runtime ``DT_Items`` cache."""

from __future__ import annotations

import math
import re
from collections import Counter
from pathlib import Path
from typing import Any, Iterable


DESCRIPTOR_ROOTS = {"Quality", "Origin", "Rarity", "Theme"}
RUNTIME_INDEX_NAME = "DT_ItemsIndex.lua"


def _number(value: Any) -> int | float | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)) and math.isfinite(float(value)):
        return value
    try:
        parsed = float(str(value).strip())
    except (TypeError, ValueError):
        return None
    if not math.isfinite(parsed):
        return None
    return int(parsed) if parsed.is_integer() else parsed


def _integer(value: Any) -> int | None:
    parsed = _number(value)
    if parsed is None:
        return None
    return int(parsed)


def _tags(values: Any) -> list[str]:
    if isinstance(values, str):
        values = values.split("|")
    if not isinstance(values, (list, tuple, set)):
        return []
    return sorted({str(value).strip() for value in values if str(value).strip()})


def _primary(tags: Iterable[str]) -> str:
    for tag in tags:
        if str(tag).split(".", 1)[0] not in DESCRIPTOR_ROOTS:
            return str(tag)
    return "Misc"


def _header_value(headers: dict[str, str], key: str, default: str = "") -> str:
    value = str(headers.get(key) or default).strip()
    return value


def _runtime_files(root: Path) -> tuple[list[Path], dict[str, Any], list[dict[str, Any]]]:
    """Select the text files that the PZ runtime actually loads.

    ``DT_ItemsIndex.lua`` is the runtime manifest.  Falling back to discovered
    text files keeps the reader useful for older/manual fixtures that predate
    the manifest, while an existing manifest is treated as authoritative.
    """

    discovered = sorted(root.rglob("*.txt"), key=lambda path: str(path).casefold())
    discovered_by_relative = {
        path.relative_to(root).as_posix(): path for path in discovered
    }
    index_path = root / RUNTIME_INDEX_NAME
    metadata: dict[str, Any] = {
        "path": str(index_path),
        "present": index_path.exists(),
        "indexedFileCount": 0,
        "indexedMissingFiles": [],
        "unindexedFileCount": 0,
        "unindexedFiles": [],
    }
    errors: list[dict[str, Any]] = []

    if not index_path.exists():
        return discovered, metadata, errors

    try:
        index_source = index_path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        errors.append({
            "path": RUNTIME_INDEX_NAME,
            "line": 0,
            "kind": "index",
            "message": f"Could not read runtime index: {error}",
        })
        return [], metadata, errors

    indexed_names: list[str] = []
    seen_names: set[str] = set()
    for match in re.finditer(r'path\s*=\s*"([^"\\]*(?:\\.[^"\\]*)*)"', index_source):
        raw_name = match.group(1)
        # Runtime paths are generated as plain slash-separated strings.  Decode
        # the two escapes that can occur without executing the Lua manifest.
        relative_name = raw_name.replace("\\\\", "\\").replace('\\"', '"')
        candidate = (root / relative_name).resolve()
        try:
            candidate.relative_to(root)
        except ValueError:
            errors.append({
                "path": RUNTIME_INDEX_NAME,
                "line": index_source.count("\n", 0, match.start()) + 1,
                "kind": "index",
                "message": f"Runtime index path escapes DT_Items: {relative_name}",
            })
            continue
        normalized_name = candidate.relative_to(root).as_posix()
        if normalized_name in seen_names:
            errors.append({
                "path": RUNTIME_INDEX_NAME,
                "line": index_source.count("\n", 0, match.start()) + 1,
                "kind": "index",
                "message": f"Runtime index lists a file more than once: {normalized_name}",
            })
            continue
        seen_names.add(normalized_name)
        indexed_names.append(normalized_name)

    if not indexed_names:
        errors.append({
            "path": RUNTIME_INDEX_NAME,
            "line": 0,
            "kind": "index",
            "message": "Runtime index contains no readable file entries.",
        })

    selected: list[Path] = []
    missing: list[str] = []
    for relative_name in indexed_names:
        path = discovered_by_relative.get(relative_name)
        if path is None:
            missing.append(relative_name)
            errors.append({
                "path": RUNTIME_INDEX_NAME,
                "line": 0,
                "kind": "index",
                "message": f"Runtime index references missing file: {relative_name}",
            })
            continue
        selected.append(path)

    unindexed = sorted(set(discovered_by_relative) - set(indexed_names))
    metadata["indexedFileCount"] = len(indexed_names)
    metadata["indexedMissingFiles"] = missing
    metadata["unindexedFileCount"] = len(unindexed)
    metadata["unindexedFiles"] = unindexed
    return selected, metadata, errors


def load_runtime_items(runtime_dir: Path) -> tuple[dict[str, dict[str, Any]], dict[str, Any]]:
    """Parse the PZ-generated ``DT_Items/*.txt`` files.

    The parser intentionally reads the grouped text files instead of the Lua
    index.  The text files contain the item-level values that DynamicTrading
    consumes, and remain inspectable even when an index was generated by an
    older game/mod version.
    """

    root = runtime_dir.expanduser().resolve()
    if not root.exists():
        raise FileNotFoundError(f"Runtime DT_Items directory does not exist: {root}")
    if not root.is_dir():
        raise NotADirectoryError(f"Runtime DT_Items path is not a directory: {root}")

    files, index_metadata, index_errors = _runtime_files(root)
    items: dict[str, dict[str, Any]] = {}
    errors: list[dict[str, Any]] = list(index_errors)

    for path in files:
        relative_path = str(path.relative_to(root))
        headers: dict[str, str] = {}
        origin = "Vanilla"
        group_tags: list[str] = []
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except (OSError, UnicodeError) as error:
            errors.append({
                "path": relative_path,
                "line": 0,
                "kind": "read",
                "message": str(error),
            })
            continue

        for line_number, raw_line in enumerate(lines, start=1):
            line = raw_line.strip()
            if not line:
                continue
            if line.startswith("#"):
                declaration = line[1:].strip()
                if "=" in declaration:
                    key, value = declaration.split("=", 1)
                    headers[key.strip()] = value.strip()
                continue
            if line.startswith("@"):
                declaration = line[1:]
                if "=" in declaration:
                    key, value = declaration.split("=", 1)
                    key = key.strip()
                    if key == "origin":
                        origin = value.strip() or "Vanilla"
                    elif key == "tags":
                        group_tags = _tags(value)
                continue

            fields = [field.strip() for field in line.split("|")]
            if len(fields) < 4 or not fields[0]:
                errors.append({
                    "path": relative_path,
                    "line": line_number,
                    "kind": "row",
                    "message": "Expected fullType|basePrice|stockMin|stockMax.",
                })
                continue

            full_type = fields[0]
            base_price = _number(fields[1])
            stock_min = _integer(fields[2])
            stock_max = _integer(fields[3])
            if base_price is None or stock_min is None or stock_max is None:
                errors.append({
                    "path": relative_path,
                    "line": line_number,
                    "kind": "value",
                    "fullType": full_type,
                    "message": "Invalid base price or stock value.",
                })
                continue
            if full_type in items:
                errors.append({
                    "path": relative_path,
                    "line": line_number,
                    "kind": "duplicate",
                    "fullType": full_type,
                    "message": "Item appeared in more than one runtime group.",
                })

            items[full_type] = {
                "fullType": full_type,
                "basePrice": base_price,
                "stock": {"min": max(0, stock_min), "max": max(0, stock_max)},
                "tags": list(group_tags),
                "origin": origin,
                "root": _header_value(headers, "root"),
                "category": _header_value(headers, "category"),
                "subcategory": _header_value(headers, "subcategory"),
                "leaf": _header_value(headers, "leaf"),
                "primaryPrefix": _header_value(headers, "primaryPrefix"),
                "path": relative_path,
                "line": line_number,
            }

    metadata = {
        "directory": str(root),
        "fileCount": len(files),
        "itemCount": len(items),
        "index": index_metadata,
        "parseErrors": errors,
        "parseErrorCount": len(errors),
    }
    return items, metadata


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

    ``DT_Items`` is a lean cache: its price column is the generated base price,
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
                "message": "Text files exist below DT_Items but are not referenced by DT_ItemsIndex.lua.",
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
            "DT_Items stores generated basePrice. Final lazy GetPriceDetails price "
            "is not serialized in the DT_Items text schema."
        ),
    }
