"""Command-line orchestration for the MarketSense offline application."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

from .bridge import find_lua
from .config import (
    DEFAULT_CACHE_DIR,
    DEFAULT_GAME_VERSION,
    DEFAULT_INSPECTOR_SETTINGS_PATH,
    DEFAULT_SANDBOX_SETTINGS_PATH,
)
from .evaluation import ScanOptions, evaluate
from .reporting import (
    write_csv,
    write_heuristic_gap_report,
    write_low_confidence_report,
)
from .sandbox import SandboxSettingsError, load_sandbox_settings, load_sandbox_option_specs
from .terminal import print_terminal
from .testing import print_self_test, self_test
from .workshop_paths import default_roots


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="marketsense-offline",
        description=(
            "Run MarketSense against Project Zomboid Workshop item scripts "
            "without starting the game."
        )
    )
    parser.add_argument(
        "--workshop-root",
        action="append",
        type=Path,
        help="Workshop root; repeat for multiple roots. Defaults to Steam and ~/Zomboid/Workshop.",
    )
    parser.add_argument(
        "--mod",
        action="append",
        default=[],
        help="Only scan mods whose id, name, or Workshop id contains this value.",
    )
    parser.add_argument(
        "--category",
        default="",
        help=(
            "Audit one top-level category (for example Food) instead of the "
            "complete catalog; unknown categories fall back to a full scan."
        ),
    )
    parser.add_argument(
        "--max-items",
        type=int,
        default=0,
        help="Evaluate at most this many unique items; 0 means all discovered items.",
    )
    parser.add_argument("--top", type=int, default=12, help="Rows shown in top/bottom tables.")
    parser.add_argument(
        "--confidence-threshold", type=float, default=0.5,
        help="Rows below this confidence appear in the low-confidence export (default: 0.5).",
    )
    parser.add_argument(
        "--low-confidence-out", type=Path,
        help="Write all low-confidence rows to .json, .jsonl, or .csv without flooding stdout.",
    )
    parser.add_argument(
        "--heuristic-gap-out", type=Path,
        help=(
            "Write all broad/default-bucket heuristic candidates to .json, .jsonl, "
            "or .csv without flooding stdout."
        ),
    )
    parser.add_argument(
        "--chunk-size", type=int, default=25,
        help="Rows per compact terminal chunk (default: 25).",
    )
    parser.add_argument(
        "--low-confidence-chunk", type=int, default=1,
        help="1-based low-confidence chunk shown in the terminal report (default: 1).",
    )
    parser.add_argument(
        "--availability-chunk", type=int, default=1,
        help="1-based uncertain/excluded availability chunk shown in the terminal report (default: 1).",
    )
    parser.add_argument(
        "--heuristic-gap-chunk", type=int, default=1,
        help="1-based generic/default-bucket candidate chunk shown in the terminal report (default: 1).",
    )
    parser.add_argument("--chart", choices=["all", "categories", "prices", "none"], default="all")
    parser.add_argument("--format", choices=["terminal", "json", "jsonl"], default="terminal")
    parser.add_argument("--csv-out", type=Path, help="Also write evaluated rows as CSV.")
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="Run deterministic fixtures through the real MarketSense Lua evaluator.",
    )
    parser.add_argument("--lua", help="Lua executable; defaults to lua5.1, lua, or luajit.")
    parser.add_argument(
        "--game-root",
        type=Path,
        help="Project Zomboid install root or media/scripts directory for vanilla item inheritance.",
    )
    parser.add_argument(
        "--game-version",
        default=DEFAULT_GAME_VERSION,
        help="Game version ceiling (default: 42.20); each mod uses its highest compatible folder.",
    )
    parser.add_argument(
        "--no-base-game",
        action="store_true",
        help="Do not load installed vanilla item scripts before Workshop patches.",
    )
    parser.add_argument(
        "--availability",
        choices=("obtainable", "all", "uncertain", "excluded"),
        default="obtainable",
        help=(
            "Item availability list: obtainable (default), all, uncertain, or excluded. "
            "Obtainable requires loot/craft/forage/farm/fishing/animal evidence."
        ),
    )
    parser.add_argument(
        "--gui",
        action="store_true",
        help="Open the desktop GUI instead of printing the terminal report.",
    )
    parser.add_argument(
        "--console",
        action="store_true",
        help="Explicitly select the terminal report (useful with run.sh).",
    )
    parser.add_argument(
        "--cache-dir",
        type=Path,
        default=DEFAULT_CACHE_DIR,
        help=f"Result cache directory (default: {DEFAULT_CACHE_DIR}).",
    )
    parser.add_argument(
        "--no-cache",
        action="store_true",
        help="Always evaluate the scan and do not read or write cached results.",
    )
    parser.add_argument(
        "--refresh-cache",
        action="store_true",
        help="Evaluate the scan even when cached results exist, then replace the cache.",
    )
    parser.add_argument(
        "--sandbox-config", type=Path, default=DEFAULT_SANDBOX_SETTINGS_PATH,
        help=f"JSON sandbox override file (default: {DEFAULT_SANDBOX_SETTINGS_PATH}).",
    )
    parser.add_argument(
        "--settings-config", type=Path, default=DEFAULT_INSPECTOR_SETTINGS_PATH,
        help=f"GUI path/settings file (default: {DEFAULT_INSPECTOR_SETTINGS_PATH}).",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    if not 0.0 <= args.confidence_threshold <= 1.0:
        print("--confidence-threshold must be between 0 and 1.", file=sys.stderr)
        return 2
    if (
        args.chunk_size < 1 or args.low_confidence_chunk < 1
        or args.availability_chunk < 1 or args.heuristic_gap_chunk < 1
    ):
        print(
            "--chunk-size, --low-confidence-chunk, --availability-chunk, "
            "and --heuristic-gap-chunk must be positive.",
            file=sys.stderr,
        )
        return 2
    if args.gui:
        from .gui import launch

        return launch(args)
    try:
        lua = find_lua(args.lua)
        if args.self_test:
            passed, checks = self_test(lua)
            if args.format == "json":
                print(json.dumps({"passed": passed, "checks": checks}, indent=2, sort_keys=True))
            elif args.format == "jsonl":
                for check in checks:
                    print(json.dumps(check, sort_keys=True))
            else:
                print_self_test(checks)
            return 0 if passed else 1
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f"MarketSense offline harness failed: {error}", file=sys.stderr)
        return 1

    try:
        sandbox_specs = load_sandbox_option_specs(args.game_version)
        sandbox_options = load_sandbox_settings(args.sandbox_config, sandbox_specs)
    except SandboxSettingsError as error:
        print(f"Invalid sandbox settings: {error}", file=sys.stderr)
        return 2

    roots = [root.expanduser().resolve() for root in (args.workshop_root or default_roots())]
    roots = [root for root in roots if root.is_dir()]
    if not roots:
        print("No Workshop roots found. Use --workshop-root PATH.", file=sys.stderr)
        return 2
    try:
        summary, rows = evaluate(
            lua,
            ScanOptions(
                workshop_roots=tuple(roots),
                filters=tuple(args.mod),
                game_version=args.game_version,
                game_root=args.game_root,
                no_base_game=args.no_base_game,
                max_items=args.max_items,
                cache_dir=args.cache_dir,
                use_cache=not args.no_cache,
                refresh_cache=args.refresh_cache,
                confidence_threshold=args.confidence_threshold,
                sandbox_options=sandbox_options,
                availability_filter=args.availability,
                category_filter=args.category,
            ),
        )
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f"MarketSense offline harness failed: {error}", file=sys.stderr)
        return 1

    if args.csv_out:
        write_csv(args.csv_out.expanduser().resolve(), rows)
    if args.low_confidence_out:
        output_path = write_low_confidence_report(
            args.low_confidence_out, rows, args.confidence_threshold
        )
        print(
            f"Wrote {summary.get('low_confidence_count', 0)} low-confidence rows to {output_path}",
            file=sys.stderr,
        )
    if args.heuristic_gap_out:
        output_path = write_heuristic_gap_report(args.heuristic_gap_out, rows)
        print(
            f"Wrote {summary.get('heuristic_coverage', {}).get('candidate_count', 0)} "
            f"heuristic-gap candidates to {output_path}",
            file=sys.stderr,
        )
    if args.format == "json":
        print(json.dumps({"summary": summary, "items": rows}, indent=2, sort_keys=True))
    elif args.format == "jsonl":
        for row in rows:
            print(json.dumps(row, sort_keys=True))
    else:
        print_terminal(
            summary,
            rows,
            max(1, args.top),
            args.chart,
            args.confidence_threshold,
            args.chunk_size,
            args.low_confidence_chunk,
            args.availability_chunk,
            args.heuristic_gap_chunk,
        )
    return 0
