"""Public terminal report entry point.

The CLI contract remains print_terminal; rendering is delegated to focused
sections so new report panels do not grow one monolithic function.
"""

from __future__ import annotations

from typing import Any

from .terminal_sections import (
    print_charts_and_rankings,
    print_diagnostic_sections,
    print_pricing_statuses,
    print_scan_header,
)


def print_terminal(
    summary: dict[str, Any], rows: list[dict[str, Any]], top: int, chart: str,
    confidence_threshold: float = 0.5, chunk_size: int = 25,
    low_confidence_chunk: int = 1, availability_chunk: int = 1,
    heuristic_gap_chunk: int = 1,
) -> None:
    print_scan_header(summary)
    print_pricing_statuses(summary, rows, top)
    print_diagnostic_sections(
        summary,
        rows,
        confidence_threshold,
        chunk_size,
        low_confidence_chunk,
        availability_chunk,
        heuristic_gap_chunk,
    )
    print_charts_and_rankings(summary, rows, top, chart)
