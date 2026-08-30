"""Notebook sections and event bindings for the MarketSense GUI."""

from __future__ import annotations

from typing import Any


def build_notebook(view: Any, root: Any, scrolledtext: Any) -> None:
    """Build independent tab sections and the status footer."""
    view.notebook = view.ttk.Notebook(root)
    view.notebook.grid(row=1, column=0, sticky="nsew", padx=8, pady=4)
    view._build_overview()
    view._build_items()
    view._build_availability_overview()
    view._build_review()
    view._build_runtime_verification()
    view._build_low_confidence()
    view._build_heuristic_gaps()
    view._build_sandbox()
    view._build_mods()
    view.log = scrolledtext.ScrolledText(
        view.notebook, wrap="none", state="disabled"
    )
    view.notebook.add(view.log, text="Diagnostics")
    view._append_log(view._sandbox_audit_log())
    view.status_var = view.tk.StringVar(
        value="Ready — choose Scan selected scope / cache to begin."
    )
    view.ttk.Label(root, textvariable=view.status_var, anchor="w").grid(
        row=2, column=0, sticky="ew", padx=10, pady=(2, 8)
    )


def bind_view_events(view: Any, root: Any) -> None:
    """Attach preference, filtering, close, and cache-restore events."""
    for variable in (
        view.workshop_var,
        view.mod_filter_var,
        view.category_scope_var,
        view.version_var,
        view.game_root_var,
        view.max_items_var,
        view.no_base_var,
        view.use_cache_var,
        view.availability_var,
    ):
        variable.trace_add(
            "write", lambda *_args: view._queue_save_preferences()
        )
    view.workshop_var.trace_add(
        "write", lambda *_args: view._queue_mod_filter_refresh()
    )
    view.game_root_var.trace_add(
        "write", lambda *_args: view._mark_game_root_explicit()
    )
    view.max_items_var.trace_add(
        "write", lambda *_args: view._queue_view_filter_refresh()
    )
    view.no_base_var.trace_add(
        "write", lambda *_args: view._apply_view_filters()
    )
    view._refresh_mod_filter_choices()
    root.protocol("WM_DELETE_WINDOW", view._close)
    root.after(80, view._restore_cached_result)
