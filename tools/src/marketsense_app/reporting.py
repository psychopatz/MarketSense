"""JSON-friendly and CSV reporting for harness results."""

from __future__ import annotations

import csv
import json
import math
import statistics
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

from .config import DEFAULT_GAME_VERSION
from .models import WorkshopMod
from .review import low_confidence_rows, review_row


def percentile(values: list[float], fraction: float) -> float:
    if not values:
        return 0.0
    if len(values) == 1:
        return values[0]
    position = (len(values) - 1) * fraction
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return values[lower]
    return values[lower] + (values[upper] - values[lower]) * (position - lower)


def price_stats(rows: list[dict[str, Any]]) -> dict[str, Any]:
    prices = sorted(
        float(row["price"])
        for row in rows
        if isinstance(row.get("price"), (int, float))
    )
    if not prices:
        return {"count": 0, "min": 0, "p05": 0, "median": 0, "p95": 0, "max": 0, "unique": 0}
    return {
        "count": len(prices),
        "min": prices[0],
        "p05": percentile(prices, 0.05),
        "median": statistics.median(prices),
        "p95": percentile(prices, 0.95),
        "max": prices[-1],
        "unique": len(set(prices)),
    }


def price_distribution(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    boundaries = [25, 50, 100, 250, 500, 1000, 2500]
    counts = [0] * (len(boundaries) + 1)
    for row in rows:
        price = row.get("price")
        if not isinstance(price, (int, float)):
            continue
        for index, boundary in enumerate(boundaries):
            if float(price) <= boundary:
                counts[index] += 1
                break
        else:
            counts[-1] += 1
    labels = [f"<= {boundary}" for boundary in boundaries] + [f"> {boundaries[-1]}"]
    return [
        {"bucket": label, "count": count}
        for label, count in zip(labels, counts)
        if count
    ]


def build_summary(
    rows: list[dict[str, Any]],
    mods: list[WorkshopMod],
    definition_count: int,
    source_files: int,
    duplicate_count: int,
    base_definition_count: int,
    base_source_files: int,
    game_scripts_root: Path | None,
    game_version: str | None,
    confidence_threshold: float = 0.5,
    availability_records: dict[str, dict[str, Any]] | None = None,
    runtime_evaluated: int | None = None,
    availability_filter: str = "obtainable",
    availability_source_files: int = 0,
    availability_source_roots: list[str] | None = None,
    availability_candidates: int | None = None,
    availability_eligible: int | None = None,
    max_items_omitted: int = 0,
) -> dict[str, Any]:
    valid = [
        row for row in rows
        if not row.get("error") and isinstance(row.get("price"), (int, float))
    ]
    categories: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in valid:
        categories[str(row.get("category") or "Unknown")].append(row)
    category_summary = {}
    for category, category_rows in sorted(categories.items()):
        stats = price_stats(category_rows)
        stats["primaries"] = Counter(
            str(row.get("primary") or "Unknown") for row in category_rows
        ).most_common(5)
        category_summary[category] = stats
    review_statuses = Counter(review_row(row)[0] for row in rows)
    low_confidence = low_confidence_rows(rows, confidence_threshold)
    vanilla_items = sum(1 for row in rows if str(row.get("workshopMod") or "") == "Base")
    availability_records = availability_records or {}
    availability_status_counts = Counter(
        str(record.get("status") or "uncertain")
        for record in availability_records.values()
    )
    runtime_count = runtime_evaluated if runtime_evaluated is not None else len(rows)
    candidate_count = availability_candidates if availability_candidates is not None else runtime_count
    eligible_count = availability_eligible if availability_eligible is not None else len(rows)
    return {
        "workshop_mods": len(mods),
        "workshop_script_selection": (
            f"{game_version or DEFAULT_GAME_VERSION} (highest compatible per mod + common)"
        ),
        "script_files": source_files,
        "item_definitions": definition_count,
        "base_script_files": base_source_files,
        "base_item_definitions": base_definition_count,
        "base_scripts": str(game_scripts_root) if game_scripts_root else None,
        "unique_items": len(rows),
        "duplicate_definitions": duplicate_count,
        "evaluated": len(rows),
        "errors": len(rows) - len(valid),
        "categories": category_summary,
        "prices": price_stats(valid),
        "price_distribution": price_distribution(valid),
        "fallback_or_low_confidence": sum(
            1 for row in valid if float(row.get("confidence") or 0) < confidence_threshold
        ),
        "confidence_threshold": confidence_threshold,
        "low_confidence_count": len(low_confidence),
        "review_count": sum(
            count for status, count in review_statuses.items() if status != "OK"
        ),
        "review_statuses": dict(review_statuses),
        "vanilla_items": vanilla_items,
        "workshop_items": len(rows) - vanilla_items,
        "runtime_evaluated": runtime_count,
        "listed_items": len(rows),
        "candidate_items": candidate_count,
        "availability_eligible_items": eligible_count,
        "filtered_out": max(0, candidate_count - eligible_count),
        "max_items_omitted": max(0, max_items_omitted),
        "availability_filter": availability_filter,
        "availability_counts": {
            "obtainable": availability_status_counts.get("obtainable", 0),
            "uncertain": availability_status_counts.get("uncertain", 0),
            "excluded": availability_status_counts.get("excluded", 0),
        },
        "availability_source_files": availability_source_files,
        "availability_source_roots": availability_source_roots or [],
        "mods_with_items": dict(
            Counter(
                str(row.get("workshopMod") or "Unknown")
                for row in valid
                if str(row.get("workshopMod") or "") != "Base"
            )
        ),
        "mods": [
            {
                "id": mod.mod_id,
                "name": mod.name,
                "workshop_id": mod.workshop_id,
                "source": mod.source_kind,
                "script_version": mod.script_version,
                "root": str(mod.root),
            }
            for mod in mods
        ],
    }


def bar(value: float, maximum: float, width: int = 28) -> str:
    if maximum <= 0:
        return ""
    return "#" * max(1, round((value / maximum) * width))


def format_number(value: Any) -> str:
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    if isinstance(value, (int, float)):
        return f"{value:.2f}" if abs(value) < 1000 and value % 1 else f"{value:.0f}"
    return str(value or "-")


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    path = path.expanduser().resolve()
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = [
        "fullType", "category", "subcategory", "leaf", "primaryPrefix", "categoryPath",
        "primary", "detector", "resolver", "price", "rawScore", "confidence", "source",
        "availabilityStatus", "availabilityConfidence", "availabilityChannels",
        "availabilityReason", "availabilityReferences", "availabilityExclusions",
        "reviewStatus", "reviewReason",
        "moduleName", "typeName", "weight", "hunger", "thirst", "calories", "daysFresh",
        "daysRotten", "minDamage", "maxDamage", "maxRange", "conditionMax", "capacity",
        "workshopMod", "workshopName", "workshopId", "workshopVersion", "scriptPath",
        "description", "tags", "definitionSources", "priceAudit", "context", "detection",
    ]
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        for row in rows:
            output = dict(row)
            output["reviewStatus"], output["reviewReason"] = review_row(row)
            hierarchy = row.get("hierarchy") if isinstance(row.get("hierarchy"), dict) else {}
            output["subcategory"] = row.get("subcategory") or hierarchy.get("subcategory", "")
            output["leaf"] = row.get("leaf") or hierarchy.get("leaf", "")
            output["primaryPrefix"] = row.get("primaryPrefix") or hierarchy.get("primaryPrefix", "")
            output["categoryPath"] = row.get("categoryPath", "")
            availability = row.get("availability") if isinstance(row.get("availability"), dict) else {}
            output["availabilityStatus"] = availability.get("status", "")
            output["availabilityConfidence"] = availability.get("confidence", "")
            output["availabilityChannels"] = ";".join(availability.get("channelLabels") or availability.get("channels") or [])
            output["availabilityReason"] = availability.get("reason", "")
            output["availabilityReferences"] = ";".join(availability.get("references") or [])
            output["availabilityExclusions"] = ";".join(availability.get("exclusions") or [])
            output["tags"] = ";".join(row.get("tags") or [])
            output["definitionSources"] = ";".join(row.get("definitionSources") or [])
            output["priceAudit"] = json.dumps(row.get("priceAudit") or [], sort_keys=True)
            output["context"] = json.dumps(row.get("context") or {}, sort_keys=True)
            output["detection"] = json.dumps(row.get("detection") or {}, sort_keys=True)
            writer.writerow(output)


def _export_row(row: dict[str, Any], threshold: float) -> dict[str, Any]:
    output = dict(row)
    output["reviewStatus"], output["reviewReason"] = review_row(row)
    output["lowConfidenceThreshold"] = threshold
    return output


def write_low_confidence_report(
    path: Path, rows: list[dict[str, Any]], threshold: float,
) -> Path:
    """Write all low-confidence rows without printing the full scan to stdout."""

    target = path.expanduser().resolve()
    selected = low_confidence_rows(rows, threshold)
    if target.suffix.casefold() == ".csv":
        write_csv(target, selected)
    elif target.suffix.casefold() == ".jsonl":
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open("w", encoding="utf-8") as handle:
            for row in selected:
                handle.write(json.dumps(_export_row(row, threshold), sort_keys=True) + "\n")
    else:
        target = target.with_suffix(".json") if not target.suffix else target
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(
            json.dumps({
                "confidenceThreshold": threshold,
                "count": len(selected),
                "items": [_export_row(row, threshold) for row in selected],
            }, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    return target
