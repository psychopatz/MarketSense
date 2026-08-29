"""Human-readable terminal charts and ranked item tables."""

from __future__ import annotations

from collections import Counter
import math
from typing import Any

from .heuristics import (
    compact_heuristic_gap,
    heuristic_coverage,
    heuristic_gap_rows,
    heuristic_kind_label,
)
from .reporting import bar, format_number
from .review import low_confidence_rows, review_row


def print_terminal(
    summary: dict[str, Any], rows: list[dict[str, Any]], top: int, chart: str,
    confidence_threshold: float = 0.5, chunk_size: int = 25,
    low_confidence_chunk: int = 1, availability_chunk: int = 1,
    heuristic_gap_chunk: int = 1,
) -> None:
    prices = summary["prices"]
    print("MarketSense offline PZ harness")
    print("Runtime: real MarketSense Lua + PZ-shaped ScriptManager/Item shims")
    print(f"Workshop script selection: {summary['workshop_script_selection']}")
    cache = summary.get("cache") or {"status": "disabled"}
    print(f"Result cache: {cache['status']}" + (f" ({cache['path']})" if cache.get("path") else ""))
    print(
        f"Workshop mods: {summary['workshop_mods']} | script files: {summary['script_files']} | "
        f"items: {summary['unique_items']} unique / {summary['item_definitions']} definitions"
    )
    if summary["base_scripts"]:
        print(
            f"Vanilla inheritance: {summary['base_item_definitions']} base definitions "
            f"from {summary['base_scripts']}"
        )
    else:
        print("Vanilla inheritance: unavailable (partial Workshop blocks may be under-classified)")
    print(
        f"Evaluated: {summary['evaluated']} | errors: {summary['errors']} | "
        f"review flags: {summary.get('review_count', 0)} | "
        f"duplicate definitions: {summary['duplicate_definitions']}"
    )
    availability = summary.get("availability_counts") or {}
    print(
        f"Availability gate: {summary.get('availability_filter', 'obtainable')} | "
        f"listed: {summary.get('listed_items', summary['evaluated'])} | "
        f"obtainable: {availability.get('obtainable', 0)} | "
        f"uncertain: {availability.get('uncertain', 0)} | "
        f"excluded: {availability.get('excluded', 0)} | "
        f"filtered out: {summary.get('filtered_out', 0)}"
    )
    verification = summary.get("availability_verification") or {}
    if verification:
        print(
            f"  Lua authority verification: {verification.get('matches', 0):,}/"
            f"{verification.get('checked', 0):,} match static audit | "
            f"mismatches: {verification.get('mismatch_count', 0):,}"
        )
    if summary.get("max_items_omitted"):
        print(
            f"  evaluation limit omitted: {summary['max_items_omitted']} eligible items "
            f"after selecting the first {summary.get('evaluated', 0)}"
        )
    if summary.get("availability_source_files"):
        print(
            f"Static comparison evidence: {summary['availability_source_files']} base/Workshop "
            "runtime source files scanned (Lua remains authoritative)"
        )
    print(
        f"Item sources: {summary.get('vanilla_items', 0)} vanilla | "
        f"{summary.get('workshop_items', summary['evaluated'])} Workshop"
    )
    print()
    print("PRICE VARIATION")
    print(
        f"  min={format_number(prices['min'])} p05={format_number(prices['p05'])} "
        f"median={format_number(prices['median'])} p95={format_number(prices['p95'])} "
        f"max={format_number(prices['max'])} unique_prices={prices['unique']}"
    )
    if prices["count"] and prices["unique"] <= 1:
        print("  WARNING: every evaluated item has the same generated price.")
    if summary["fallback_or_low_confidence"]:
        print(f"  low-confidence/fallback rows: {summary['fallback_or_low_confidence']}")
    if summary["evaluated"] == 0:
        print("  WARNING: no item definitions matched the selected Workshop roots/filters.")
    print()

    sandbox = summary.get("sandbox") or {}
    requested_sandbox = sandbox.get("overrides") or {}
    effective_sandbox = sandbox.get("requested") or {}
    runtime_sandbox = sandbox.get("runtime") or {}
    runtime_pricing = runtime_sandbox.get("pricing") or {}
    print("SANDBOX PRICING")
    print(
        f"  overrides={len(requested_sandbox)} | effective settings={len(effective_sandbox)} | "
        f"price_multiplier={format_number(runtime_pricing.get('baseMultiplier'))} | "
        f"global_price_add={format_number(runtime_pricing.get('globalValue'))}"
    )
    if requested_sandbox:
        option_items = sorted(requested_sandbox.items())
        total_chunks = max(1, math.ceil(len(option_items) / chunk_size))
        chunk_number = min(low_confidence_chunk, total_chunks)
        start = (chunk_number - 1) * chunk_size
        selected = option_items[start:start + chunk_size]
        print(
            f"  override chunk {chunk_number}/{total_chunks} "
            f"(rows {start + 1}-{start + len(selected)} of {len(option_items)})"
        )
        for key, value in selected:
            print(f"    {key}={format_number(value)}")
        if total_chunks > chunk_number:
            print(f"  ... use --low-confidence-chunk {chunk_number + 1} for the next chunk")
    else:
        print("  no overrides; using the mod's declared/default sandbox values")
    print()

    print("WORKSHOP MOD COVERAGE")
    mod_counts = summary["mods_with_items"]
    if not mod_counts:
        print("  no evaluated mod items")
    else:
        mod_versions = {mod["id"]: mod["script_version"] for mod in summary["mods"]}
        ranked_mods = sorted(mod_counts.items(), key=lambda entry: (-entry[1], entry[0]))
        for mod_id, count in ranked_mods[:top]:
            print(f"  {mod_id:<32} {mod_versions.get(mod_id, '-'):<14} {count:>6} items")
        if len(ranked_mods) > top:
            print(
                f"  ... {len(ranked_mods) - top} more; use --format json for the complete mod inventory"
            )
    print()

    low_confidence = low_confidence_rows(rows, confidence_threshold)
    if low_confidence:
        total_chunks = max(1, math.ceil(len(low_confidence) / chunk_size))
        chunk_number = min(low_confidence_chunk, total_chunks)
        start = (chunk_number - 1) * chunk_size
        selected = low_confidence[start:start + chunk_size]
        print(
            f"LOW-CONFIDENCE / FALLBACK CHUNK {chunk_number}/{total_chunks} "
            f"(threshold < {confidence_threshold:.2f}; rows "
            f"{start + 1}-{start + len(selected)} of {len(low_confidence)})"
        )
        print("  confidence | category     | primary | item")
        for row in selected:
            print(
                f"  {float(row.get('confidence') or 0):>10.2f} | "
                f"{str(row.get('category') or '-'):<12} | "
                f"{str(row.get('primary') or '-'):<7} | {row.get('fullType', '-')}")
        if total_chunks > chunk_number:
            print(
                f"  ... use --low-confidence-chunk {chunk_number + 1} "
                f"for the next {chunk_size} rows; use --low-confidence-out for all rows"
            )
        elif len(low_confidence) > chunk_size:
            print("  ... all remaining rows are in the saved low-confidence export")
        print()

    heuristic_candidates = heuristic_gap_rows(rows)
    heuristic_stats = summary.get("heuristic_coverage") or heuristic_coverage(rows)
    print("HEURISTIC COVERAGE")
    print(
        "  generic/default bucket candidates: "
        f"{heuristic_stats.get('candidate_count', len(heuristic_candidates)):,}"
        " (triage only; not confirmed false positives)"
    )
    bucket_counts = heuristic_stats.get("bucket_counts") or {}
    if bucket_counts:
        print("  buckets: " + ", ".join(
            f"{bucket}={count:,}" for bucket, count in bucket_counts.items()
        ))
    kind_counts = heuristic_stats.get("kind_counts") or {}
    if kind_counts:
        print("  kinds: " + ", ".join(
            f"{heuristic_kind_label(kind)}={count:,}" for kind, count in kind_counts.items()
        ))
    gap_mod_counts = heuristic_stats.get("mod_counts") or {}
    if gap_mod_counts:
        ranked_gap_mods = list(gap_mod_counts.items())
        shown_gap_mods = ranked_gap_mods[:max(1, top)]
        suffix = (
            f" (+{len(ranked_gap_mods) - len(shown_gap_mods)} more)"
            if len(ranked_gap_mods) > len(shown_gap_mods) else ""
        )
        print("  mods: " + ", ".join(
            f"{mod}={count:,}" for mod, count in shown_gap_mods
        ) + suffix)
    if heuristic_candidates:
        total_chunks = max(1, math.ceil(len(heuristic_candidates) / chunk_size))
        chunk_number = min(heuristic_gap_chunk, total_chunks)
        start = (chunk_number - 1) * chunk_size
        selected = heuristic_candidates[start:start + chunk_size]
        print(
            f"  candidate chunk {chunk_number}/{total_chunks} "
            f"(rows {start + 1}-{start + len(selected)} of {len(heuristic_candidates)})"
        )
        print("  kind       | bucket             | confidence | item | mod")
        for row in selected:
            gap = compact_heuristic_gap(row) or {}
            print(
                f"  {heuristic_kind_label(gap.get('kind')):<10} | "
                f"{str(gap.get('bucket') or '-'):<18} | "
                f"{float(row.get('confidence') or 0):>10.2f} | "
                f"{row.get('fullType', '-')} | {row.get('workshopMod', '-')}"
            )
        if total_chunks > chunk_number:
            print(
                f"  ... use --heuristic-gap-chunk {chunk_number + 1} "
                f"for the next {chunk_size} rows; use --heuristic-gap-out for all rows"
            )
        elif len(heuristic_candidates) > chunk_size:
            print("  ... all remaining rows are in the saved heuristic-gap export")
    else:
        print("  no generic/default bucket candidates")
    print()

    availability_findings = [
        row for row in rows
        if str((row.get("availability") or {}).get("status") or "uncertain") != "obtainable"
    ]
    if availability_findings:
        total_chunks = max(1, math.ceil(len(availability_findings) / chunk_size))
        chunk_number = min(availability_chunk, total_chunks)
        start = (chunk_number - 1) * chunk_size
        selected = availability_findings[start:start + chunk_size]
        print(
            f"AVAILABILITY FINDINGS CHUNK {chunk_number}/{total_chunks} "
            f"(rows {start + 1}-{start + len(selected)} of {len(availability_findings)})"
        )
        print("  status     | item | reason")
        for row in selected:
            availability = row.get("availability") or {}
            print(
                f"  {str(availability.get('status') or 'uncertain'):<10} | "
                f"{row.get('fullType', '-'):<36} | {availability.get('reason', '-')}"
            )
        if total_chunks > chunk_number:
            print(
                f"  ... use --availability-chunk {chunk_number + 1} "
                f"for the next {chunk_size} rows"
            )
        print()

    review_flags = [row for row in rows if review_row(row)[0] != "OK"]
    if review_flags:
        print("CLASSIFICATION REVIEW FLAGS")
        print("  status | category     | primary | reason | item")
        for row in sorted(review_flags, key=lambda item: str(item.get("fullType", "")))[:top]:
            status, reason = review_row(row)
            print(
                f"  {status:<6} | {str(row.get('category') or '-'):<12} | "
                f"{str(row.get('primary') or '-'):<7} | {reason} | {row.get('fullType', '-')}"
            )
        if len(review_flags) > top:
            print(f"  ... {len(review_flags) - top} more; inspect JSONL for all rows")
        print()

    lineage = [row for row in rows if len(row.get("definitionSources") or []) > 1]
    if lineage and summary["duplicate_definitions"]:
        print("DEFINITION LINEAGE (inheritance/duplicate evidence)")
        for row in lineage[:top]:
            print(
                f"  {row.get('fullType', '-')}: "
                f"{len(row.get('definitionSources') or [])} source blocks"
            )
        if len(lineage) > top:
            print(f"  ... {len(lineage) - top} more; inspect definitionSources in JSON/JSONL")
        print()

    category_summary = summary["categories"]
    if chart in {"all", "categories"}:
        print("CATEGORY COUNTS")
        max_count = max((value["count"] for value in category_summary.values()), default=0)
        for category, value in category_summary.items():
            print(f"  {category:<12} {value['count']:>6} {bar(value['count'], max_count)}")
        print()
        primary_counts = Counter(
            str(row.get("primary") or "Unknown")
            for row in rows
            if not row.get("error")
        )
        print("PRIMARY TAG COUNTS")
        max_primary_count = max(primary_counts.values(), default=0)
        for primary, count in sorted(primary_counts.items(), key=lambda entry: (-entry[1], entry[0])):
            print(f"  {primary:<32} {count:>6} {bar(count, max_primary_count)}")
        print()
    if chart in {"all", "prices"}:
        print("PRICE DISTRIBUTION")
        distribution = summary["price_distribution"]
        max_bucket = max((bucket["count"] for bucket in distribution), default=0)
        for bucket in distribution:
            print(f"  {bucket['bucket']:<8} {bucket['count']:>6} {bar(bucket['count'], max_bucket)}")
        print()
        print("PRICE BY CATEGORY (min / median / max)")
        max_median = max((value["median"] for value in category_summary.values()), default=0)
        for category, value in category_summary.items():
            print(
                f"  {category:<12} {format_number(value['min']):>7} / "
                f"{format_number(value['median']):>7} / {format_number(value['max']):>7} "
                f"{bar(value['median'], max_median)}"
            )
        print()

    valid = [row for row in rows if not row.get("error")]
    valid.sort(
        key=lambda row: (float(row.get("price") or 0), str(row.get("fullType"))),
        reverse=True,
    )
    print(f"TOP {top} PRICES")
    print("  price | category     | primary                         | raw    | item")
    for row in valid[:top]:
        print(
            f"  {format_number(row.get('price')):>5} | "
            f"{str(row.get('category') or '-'):<12} | "
            f"{str(row.get('primary') or '-'):<31} | "
            f"{format_number(row.get('rawScore')):>6} | {row['fullType']}"
        )
    print()
    print(f"BOTTOM {top} PRICES")
    for row in valid[-top:][::-1]:
        print(
            f"  {format_number(row.get('price')):>5} | "
            f"{str(row.get('category') or '-'):<12} | "
            f"{str(row.get('primary') or '-'):<31} | "
            f"{format_number(row.get('rawScore')):>6} | {row['fullType']}"
        )
    print()
    print("ASSISTANT-FRIENDLY CHECKS")
    print(
        f"  categories={len(category_summary)} "
        f"price_range={format_number(prices['max'] - prices['min'])} "
        f"median={format_number(prices['median'])} errors={summary['errors']}"
    )
    for category, value in category_summary.items():
        if value["unique"] <= 1 and value["count"] > 1:
            print(
                f"  WARNING: {category} has no price variation across {value['count']} items."
            )
