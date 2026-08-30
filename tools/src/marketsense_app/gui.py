"""Tk entry point for the modular MarketSense desktop inspector."""

from __future__ import annotations

import os
import sys
from pathlib import Path
from typing import Any

from .config import (
    DEFAULT_INSPECTOR_SETTINGS_PATH,
    DEFAULT_SANDBOX_SETTINGS_PATH,
)
from .gui_audits import AuditMixin
from .gui_controller import ALL_MODS_LABEL, ControllerMixin
from .gui_items import ItemsMixin
from .gui_overview import OverviewMixin
from .gui_sandbox import SandboxMixin
from .gui_widgets import WidgetMixin
from .preferences import load_preferences, normalize_preferences
from .sandbox import (
    SandboxSettingsError,
    sandbox_definition_audit,
    load_sandbox_option_specs,
    load_sandbox_settings,
)
from .scan_scope import CATEGORY_SCOPE_CHOICES, category_scope_label
from .workshop_paths import default_roots, game_scripts_root


class MarketSenseGui(
    WidgetMixin,
    OverviewMixin,
    ItemsMixin,
    AuditMixin,
    SandboxMixin,
    ControllerMixin,
):
    """Compose the inspector from focused view and controller mixins.

    The public class and ``launch`` function remain stable for the CLI. Each
    mixin owns one UI concern, while ControllerMixin owns the shared state and
    asynchronous scan lifecycle.
    """

    def __init__(
        self,
        root: Any,
        tk: Any,
        ttk: Any,
        scrolledtext: Any,
        filedialog: Any,
        messagebox: Any,
        simpledialog: Any,
        args: Any,
    ) -> None:
        self.root, self.tk, self.ttk = root, tk, ttk
        self.filedialog, self.messagebox = filedialog, messagebox
        self.simpledialog = simpledialog
        self.args = args
        self.scrolledtext = scrolledtext
        self.busy = False
        self.summary: dict[str, Any] | None = None
        self.rows: list[dict[str, Any]] = []
        # ``master_rows`` is the complete cached evaluation.  ``rows`` is
        # only the current local GUI view and may change many times per
        # second as filters/searches are adjusted.
        self.master_summary: dict[str, Any] | None = None
        self.master_rows: list[dict[str, Any]] = []

        self.preferences_path = Path(
            getattr(args, "settings_config", None)
            or DEFAULT_INSPECTOR_SETTINGS_PATH
        ).expanduser()
        self.preferences = normalize_preferences(
            load_preferences(self.preferences_path)
        )
        self._preferences_after_id: str | None = None
        self._mod_filter_after_id: str | None = None
        self._view_filter_after_id: str | None = None

        root.title(
            f"MarketSense Inspector — Project Zomboid "
            f"{getattr(args, 'game_version', '42.20')}"
        )
        root.geometry("1280x860")
        root.minsize(980, 680)
        root.columnconfigure(0, weight=1)
        root.rowconfigure(1, weight=1)

        controls = self.ttk.LabelFrame(root, text="Scan settings", padding=8)
        controls.grid(row=0, column=0, sticky="ew", padx=8, pady=(8, 4))
        controls.columnconfigure(1, weight=1)
        controls.columnconfigure(3, weight=1)
        controls.columnconfigure(4, weight=1)

        configured_roots = getattr(args, "workshop_root", None) or [
            Path(value) for value in self.preferences.get("workshopRoots", [])
        ] or default_roots()
        configured_game_root = (
            getattr(args, "game_root", None)
            or self.preferences.get("gameRoot")
            or game_scripts_root(None)
        )
        auto_game_root = game_scripts_root(None)
        configured_game_root_text = str(configured_game_root or "")
        self._auto_game_root = auto_game_root
        self._game_root_is_auto = (
            not getattr(args, "game_root", None)
            and bool(auto_game_root)
            and Path(configured_game_root_text).expanduser().resolve()
            == auto_game_root
        )

        configured_filters = self._configured_mod_filters(args)
        self.initial_mod_filters = tuple(configured_filters)
        self.mod_filter_options: dict[str, tuple[str, ...]] = {
            ALL_MODS_LABEL: ()
        }
        self.workshop_var = self.tk.StringVar(
            value=os.pathsep.join(str(path) for path in configured_roots)
        )
        # Leave this blank until the metadata pass maps legacy CLI/preferences
        # terms to a discovered label (or falls back to All).
        self.mod_filter_var = self.tk.StringVar(value="")
        self.mod_filter_count_var = self.tk.StringVar(value="0 mods detected")
        configured_category = (
            getattr(args, "category", None)
            or self.preferences.get("categoryFilter")
            or ""
        )
        self.category_scope_var = self.tk.StringVar(
            value=category_scope_label(configured_category)
        )
        self.version_var = self.tk.StringVar(
            value=str(
                self.preferences.get("gameVersion")
                or getattr(args, "game_version", "42.20")
            )
        )
        self.game_root_var = self.tk.StringVar(
            value=str(configured_game_root or "")
        )
        configured_max_items = (
            getattr(args, "max_items", 0)
            or self.preferences.get("maxItems")
            or 0
        )
        self.max_items_var = self.tk.StringVar(value=str(configured_max_items))
        self.no_base_var = self.tk.BooleanVar(
            value=bool(
                getattr(args, "no_base_game", False)
                or self.preferences.get("skipVanilla", False)
            )
        )
        self.use_cache_var = self.tk.BooleanVar(
            value=(
                not getattr(args, "no_cache", False)
                and bool(self.preferences.get("useCache", True))
            )
        )
        # Refresh is a one-shot rebuild control and is intentionally not
        # restored from the preferences file.
        self.refresh_cache_var = self.tk.BooleanVar(
            value=getattr(args, "refresh_cache", False)
        )
        availability_filter = getattr(args, "availability", "obtainable")
        availability_labels = {
            "obtainable": "Obtainable only",
            "all": "All items",
            "uncertain": "Uncertain only",
            "excluded": "Excluded only",
            "changed": "Changed only",
            "blacklisted": "Blacklisted only",
            "whitelisted": "Whitelisted only",
            "overridden": "Overridden only",
        }
        self.availability_var = self.tk.StringVar(
            value=availability_labels.get(
                str(
                    self.preferences.get("availability")
                    or availability_filter
                ),
                "Obtainable only",
            )
        )

        configured_sandbox = getattr(args, "sandbox_config", None)
        configured_sandbox_path = (
            Path(configured_sandbox).expanduser().resolve()
            if configured_sandbox else None
        )
        default_sandbox_path = DEFAULT_SANDBOX_SETTINGS_PATH.expanduser().resolve()
        self.sandbox_path = Path(
            configured_sandbox
            if configured_sandbox_path and configured_sandbox_path != default_sandbox_path
            else self.preferences.get("sandboxConfig")
            or configured_sandbox
            or DEFAULT_SANDBOX_SETTINGS_PATH
        ).expanduser()
        self.sandbox_specs = load_sandbox_option_specs(self.version_var.get())
        self.sandbox_spec_by_key = {
            spec.key: spec for spec in self.sandbox_specs
        }
        self.sandbox_audit = sandbox_definition_audit(self.version_var.get())
        self.sandbox_overrides: dict[str, int | float] = {}
        self.sandbox_settings_error = ""
        try:
            self.sandbox_overrides = load_sandbox_settings(
                self.sandbox_path, self.sandbox_specs
            )
        except SandboxSettingsError as error:
            self.sandbox_settings_error = str(error)

        self._entry(
            controls, 0, 0, "Workshop root(s)", self.workshop_var, 46
        )
        self.ttk.Button(
            controls, text="Browse…", command=self._browse_workshop
        ).grid(row=0, column=2, padx=(6, 12), sticky="w")
        self.ttk.Label(controls, text="Mod filter (view)").grid(
            row=0, column=3, sticky="w", padx=(0, 6), pady=2
        )
        self.mod_filter_combo = self.ttk.Combobox(
            controls,
            textvariable=self.mod_filter_var,
            state="readonly",
            width=32,
        )
        self.mod_filter_combo.grid(
            row=0, column=4, sticky="ew", pady=2
        )
        self.mod_filter_combo.bind(
            "<<ComboboxSelected>>",
            lambda _event: self._on_mod_filter_selected(),
        )
        self.ttk.Label(
            controls, textvariable=self.mod_filter_count_var
        ).grid(row=3, column=3, columnspan=2, sticky="w", pady=(0, 2))
        self._entry(
            controls, 1, 0, "Game version", self.version_var, 12
        )
        self._entry(
            controls, 1, 3, "Game root", self.game_root_var, 32
        )
        self.ttk.Button(
            controls, text="Browse…", command=self._browse_game_root
        ).grid(row=1, column=2, padx=(6, 12), sticky="w")
        self.ttk.Label(controls, text="Category (scan)").grid(
            row=2, column=0, sticky="w", padx=(0, 6), pady=2
        )
        category_choices = list(CATEGORY_SCOPE_CHOICES)
        selected_category = self.category_scope_var.get()
        if selected_category not in category_choices:
            category_choices.append(selected_category)
        self.category_scope_combo = self.ttk.Combobox(
            controls,
            textvariable=self.category_scope_var,
            values=tuple(category_choices),
            state="readonly",
            width=18,
        )
        self.category_scope_combo.grid(row=2, column=1, sticky="w", pady=2)
        self.category_scope_combo.bind(
            "<<ComboboxSelected>>",
            lambda _event: self._on_category_scope_selected(),
        )
        cache_options = self.ttk.Frame(controls)
        cache_options.grid(row=2, column=3, columnspan=2, sticky="w")
        self.ttk.Checkbutton(
            cache_options, text="Skip vanilla (view)", variable=self.no_base_var
        ).pack(side="left")
        self.ttk.Checkbutton(
            cache_options, text="Use cache", variable=self.use_cache_var
        ).pack(side="left", padx=(10, 0))
        self.ttk.Checkbutton(
            cache_options, text="Refresh", variable=self.refresh_cache_var
        ).pack(side="left", padx=(10, 0))
        self._entry(controls, 3, 0, "Max shown (view)", self.max_items_var, 12)
        self.ttk.Label(controls, text="Availability (view)").grid(
            row=4, column=0, sticky="w", padx=(0, 6), pady=2
        )
        self.availability_combo = self.ttk.Combobox(
            controls,
            textvariable=self.availability_var,
            values=(
                "Obtainable only",
                "All items",
                "Uncertain only",
                "Excluded only",
                "Changed only",
                "Blacklisted only",
                "Whitelisted only",
                "Overridden only",
            ),
            state="readonly",
            width=18,
        )
        self.availability_combo.grid(row=4, column=1, sticky="w", pady=2)
        self.availability_combo.bind(
            "<<ComboboxSelected>>",
            lambda _event: self._apply_view_filters(),
        )

        buttons = self.ttk.Frame(controls)
        buttons.grid(row=5, column=0, columnspan=5, sticky="w", pady=(8, 0))
        self.scan_button = self.ttk.Button(
            buttons, text="Scan selected scope / cache", command=self.scan
        )
        self.scan_button.pack(side="left")
        self.test_button = self.ttk.Button(
            buttons, text="Run self-test", command=self.self_test
        )
        self.test_button.pack(side="left", padx=6)
        self.save_button = self.ttk.Button(
            buttons,
            text="Save JSON…",
            command=self.save_json,
            state="disabled",
        )
        self.save_button.pack(side="left")
        self.csv_button = self.ttk.Button(
            buttons,
            text="Save CSV…",
            command=self.save_csv,
            state="disabled",
        )
        self.csv_button.pack(side="left", padx=6)
        self.clear_button = self.ttk.Button(
            buttons, text="Clear cache", command=self.clear_cache
        )
        self.clear_button.pack(side="left")
        self.progress = self.ttk.Progressbar(
            buttons, mode="indeterminate", length=160
        )
        self.progress.pack(side="left", padx=(16, 0))

        self.notebook = self.ttk.Notebook(root)
        self.notebook.grid(row=1, column=0, sticky="nsew", padx=8, pady=4)
        self._build_overview()
        self._build_items()
        self._build_availability_overview()
        self._build_review()
        self._build_runtime_verification()
        self._build_low_confidence()
        self._build_heuristic_gaps()
        self._build_sandbox()
        self._build_mods()
        self.log = scrolledtext.ScrolledText(
            self.notebook, wrap="none", state="disabled"
        )
        self.notebook.add(self.log, text="Diagnostics")
        self._append_log(self._sandbox_audit_log())
        self.status_var = self.tk.StringVar(
            value="Ready — choose Scan selected scope / cache to begin."
        )
        self.ttk.Label(root, textvariable=self.status_var, anchor="w").grid(
            row=2, column=0, sticky="ew", padx=10, pady=(2, 8)
        )

        for variable in (
            self.workshop_var,
            self.mod_filter_var,
            self.category_scope_var,
            self.version_var,
            self.game_root_var,
            self.max_items_var,
            self.no_base_var,
            self.use_cache_var,
            self.availability_var,
        ):
            variable.trace_add(
                "write", lambda *_args: self._queue_save_preferences()
            )
        self.workshop_var.trace_add(
            "write", lambda *_args: self._queue_mod_filter_refresh()
        )
        self.game_root_var.trace_add(
            "write", lambda *_args: self._mark_game_root_explicit()
        )
        self.max_items_var.trace_add(
            "write", lambda *_args: self._queue_view_filter_refresh()
        )
        self.no_base_var.trace_add(
            "write", lambda *_args: self._apply_view_filters()
        )
        self._refresh_mod_filter_choices()
        root.protocol("WM_DELETE_WINDOW", self._close)
        root.after(80, self._restore_cached_result)

    def _configured_mod_filters(self, args: Any) -> list[str]:
        configured = getattr(args, "mod", None)
        if configured:
            return [str(value).strip() for value in configured if str(value).strip()]
        return [
            value.strip()
            for value in str(self.preferences.get("modFilters") or "").split(",")
            if value.strip()
        ]


def launch(args: Any) -> int:
    try:
        import tkinter as tk
        from tkinter import filedialog, messagebox, scrolledtext, simpledialog, ttk
    except ImportError as error:
        print(f"MarketSense GUI requires tkinter: {error}", file=sys.stderr)
        return 1
    try:
        root = tk.Tk()
    except tk.TclError as error:
        print(
            f"MarketSense GUI could not open a desktop window: {error}",
            file=sys.stderr,
        )
        return 1
    MarketSenseGui(
        root, tk, ttk, scrolledtext, filedialog, messagebox, simpledialog, args
    )
    root.mainloop()
    return 0


if __name__ == "__main__":
    from .cli import parse_args

    gui_args = parse_args(sys.argv[1:])
    raise SystemExit(launch(gui_args))
