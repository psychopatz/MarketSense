#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${MARKETSENSE_VENV:-$SCRIPT_DIR/.venv}"
PYTHON_BIN="${PYTHON_BIN:-python3}"

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
    echo "MarketSense requires Python 3.10+; '$PYTHON_BIN' was not found." >&2
    exit 1
fi

if ! "$PYTHON_BIN" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)'; then
    echo "MarketSense requires Python 3.10 or newer." >&2
    exit 1
fi

if [ ! -x "$VENV_DIR/bin/python" ]; then
    echo "Creating MarketSense virtual environment at $VENV_DIR" >&2
    "$PYTHON_BIN" -m venv "$VENV_DIR"
fi

if [ ! -x "$VENV_DIR/bin/python" ]; then
    echo "Failed to create the MarketSense virtual environment at $VENV_DIR" >&2
    exit 1
fi

if ! "$VENV_DIR/bin/python" -m pip --version >/dev/null 2>&1; then
    echo "Installing pip into the MarketSense virtual environment" >&2
    "$VENV_DIR/bin/python" -m ensurepip --upgrade
fi

"$VENV_DIR/bin/python" -m pip install \
    --disable-pip-version-check \
    --no-input \
    -r "$SCRIPT_DIR/requirements.txt" >&2

if [ "$#" -eq 0 ]; then
    set -- --gui
fi

export PYTHONPATH="$SCRIPT_DIR/src${PYTHONPATH:+:$PYTHONPATH}"
exec "$VENV_DIR/bin/python" -m marketsense_app "$@"
