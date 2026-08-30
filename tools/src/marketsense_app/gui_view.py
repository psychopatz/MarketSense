"""Compatibility facade for modular MarketSense GUI view construction."""

from __future__ import annotations

from typing import Any

from .gui_view_controls import build_scan_controls
from .gui_view_runtime import initialize_runtime
from .gui_view_tabs import bind_view_events, build_notebook


def initialize_view(
    view: Any,
    root: Any,
    tk: Any,
    ttk: Any,
    scrolledtext: Any,
    filedialog: Any,
    messagebox: Any,
    simpledialog: Any,
    args: Any,
) -> None:
    """Compose runtime state, controls, tabs, and bindings in load order."""
    initialize_runtime(
        view,
        root,
        tk,
        ttk,
        scrolledtext,
        filedialog,
        messagebox,
        simpledialog,
        args,
    )
    build_scan_controls(view, root)
    build_notebook(view, root, scrolledtext)
    bind_view_events(view, root)
