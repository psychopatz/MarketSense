#!/usr/bin/env python3
"""Small isolated Lua smoke-test runner for MarketSense."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TESTS = ROOT / "tests"
MOD_ROOT = ROOT / "Contents" / "mods" / "MarketSense"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("filters", nargs="*")
    args = parser.parse_args()

    tests = sorted(TESTS.glob("*_smoke.lua"))
    if args.filters:
        lowered = [item.casefold() for item in args.filters]
        tests = [path for path in tests if any(item in path.stem.casefold() for item in lowered)]

    if not tests:
        print("No MarketSense smoke tests matched.", file=sys.stderr)
        return 2

    environment = os.environ.copy()
    environment["MARKET_SENSE_TEST_MOD"] = str(MOD_ROOT)
    failed = 0
    for path in tests:
        result = subprocess.run(
            ["lua", str(path)],
            cwd=ROOT,
            env=environment,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        print(f"[{path.name}]")
        print(result.stdout.rstrip())
        if result.returncode != 0:
            failed += 1

    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
