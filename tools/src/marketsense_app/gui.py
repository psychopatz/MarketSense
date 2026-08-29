"""Tk desktop front end for the shared MarketSense scan pipeline."""

from __future__ import annotations

import json
import os
import sys
import threading
import traceback
from pathlib import Path
from typing import Any

from .bridge import find_lua
from .cache import clear_cache as clear_result_cache
from .config import DEFAULT_CACHE_DIR, DEFAULT_SANDBOX_SETTINGS_PATH
from .evaluation import ScanOptions, evaluate
from .fixtures import self_test as run_self_test
from .reporting import write_csv, write_low_confidence_report
from .review import low_confidence_rows, review_count, review_row, searchable_text
from .sandbox import (
    SandboxOption,
    SandboxSettingsError,
    load_sandbox_option_specs,
    load_sandbox_settings,
    normalize_settings,
    save_sandbox_settings,
)
from .workshop_paths import default_roots


class MarketSenseGui:
    def __init__(self, root: Any, tk: Any, ttk: Any, scrolledtext: Any,
                 filedialog: Any, messagebox: Any, args: Any) -> None:
        self.root, self.tk, self.ttk = root, tk, ttk
        self.filedialog, self.messagebox = filedialog, messagebox
        self.args = args
        self.scrolledtext = scrolledtext
        self.busy = False
        self.summary: dict[str, Any] | None = None
        self.rows: list[dict[str, Any]] = []

        root.title("MarketSense Inspector — Project Zomboid 42.20")
        root.geometry("1280x860")
        root.minsize(980, 680)
        root.columnconfigure(0, weight=1)
        root.rowconfigure(1, weight=1)

        controls = self.ttk.LabelFrame(root, text="Scan settings", padding=8)
        controls.grid(row=0, column=0, sticky="ew", padx=8, pady=(8, 4))
        controls.columnconfigure(1, weight=1)
        controls.columnconfigure(3, weight=1)
        self.workshop_var = self.tk.StringVar(
            value=os.pathsep.join(str(path) for path in (args.workshop_root or []))
        )
        self.filter_var = self.tk.StringVar(value=", ".join(args.mod or []))
        self.version_var = self.tk.StringVar(value=args.game_version)
        self.game_root_var = self.tk.StringVar(value=str(args.game_root or ""))
        self.max_items_var = self.tk.StringVar(value=str(args.max_items or 0))
        self.no_base_var = self.tk.BooleanVar(value=args.no_base_game)
        self.use_cache_var = self.tk.BooleanVar(value=not args.no_cache)
        self.refresh_cache_var = self.tk.BooleanVar(value=args.refresh_cache)
        self.sandbox_path = Path(
            getattr(args, "sandbox_config", None) or DEFAULT_SANDBOX_SETTINGS_PATH
        ).expanduser()
        self.sandbox_specs = load_sandbox_option_specs(self.version_var.get())
        self.sandbox_spec_by_key = {spec.key: spec for spec in self.sandbox_specs}
        self.sandbox_overrides: dict[str, int | float] = {}
        self.sandbox_settings_error = ""
        try:
            self.sandbox_overrides = load_sandbox_settings(
                self.sandbox_path, self.sandbox_specs
            )
        except SandboxSettingsError as error:
            self.sandbox_settings_error = str(error)
        self._entry(controls, 0, 0, "Workshop root(s)", self.workshop_var, 46)
        self.ttk.Button(controls, text="Browse…", command=self._browse_workshop).grid(
            row=0, column=2, padx=(6, 12), sticky="w"
        )
        self._entry(controls, 0, 3, "Mod filter(s)", self.filter_var, 32)
        self._entry(controls, 1, 0, "Game version", self.version_var, 12)
        self._entry(controls, 1, 3, "Game root", self.game_root_var, 32)
        self._entry(controls, 2, 0, "Max items", self.max_items_var, 12)
        cache_options = self.ttk.Frame(controls)
        cache_options.grid(row=2, column=3, sticky="w", padx=(0, 12))
        self.ttk.Checkbutton(
            cache_options, text="Skip vanilla", variable=self.no_base_var
        ).pack(side="left")
        self.ttk.Checkbutton(
            cache_options, text="Use cache", variable=self.use_cache_var
        ).pack(side="left", padx=(10, 0))
        self.ttk.Checkbutton(
            cache_options, text="Refresh", variable=self.refresh_cache_var
        ).pack(side="left", padx=(10, 0))
        buttons = self.ttk.Frame(controls)
        buttons.grid(row=3, column=0, columnspan=4, sticky="w", pady=(8, 0))
        self.scan_button = self.ttk.Button(buttons, text="Scan Workshop", command=self.scan)
        self.scan_button.pack(side="left")
        self.test_button = self.ttk.Button(buttons, text="Run self-test", command=self.self_test)
        self.test_button.pack(side="left", padx=6)
        self.save_button = self.ttk.Button(buttons, text="Save JSON…", command=self.save_json, state="disabled")
        self.save_button.pack(side="left")
        self.csv_button = self.ttk.Button(buttons, text="Save CSV…", command=self.save_csv, state="disabled")
        self.csv_button.pack(side="left", padx=6)
        self.clear_button = self.ttk.Button(buttons, text="Clear cache", command=self.clear_cache)
        self.clear_button.pack(side="left")
        self.progress = self.ttk.Progressbar(buttons, mode="indeterminate", length=160)
        self.progress.pack(side="left", padx=(16, 0))

        self.notebook = self.ttk.Notebook(root)
        self.notebook.grid(row=1, column=0, sticky="nsew", padx=8, pady=4)
        self._build_overview()
        self._build_items()
        self._build_review()
        self._build_low_confidence()
        self._build_sandbox()
        self._build_mods()
        self.log = scrolledtext.ScrolledText(self.notebook, wrap="none", state="disabled")
        self.notebook.add(self.log, text="Diagnostics")
        self.status_var = self.tk.StringVar(value="Ready — choose Scan Workshop to begin.")
        self.ttk.Label(root, textvariable=self.status_var, anchor="w").grid(
            row=2, column=0, sticky="ew", padx=10, pady=(2, 8)
        )

    def _entry(self, parent: Any, row: int, label_column: int, label: str,
               variable: Any, width: int) -> None:
        self.ttk.Label(parent, text=label).grid(row=row, column=label_column, sticky="w", padx=(0, 6), pady=2)
        self.ttk.Entry(parent, textvariable=variable, width=width).grid(
            row=row, column=label_column + 1, sticky="ew", pady=2
        )

    def _build_overview(self) -> None:
        frame = self.ttk.Frame(self.notebook, padding=8)
        frame.columnconfigure(0, weight=1)
        frame.columnconfigure(1, weight=1)
        frame.rowconfigure(1, weight=1)
        frame.rowconfigure(2, weight=1)
        self.notebook.add(frame, text="Overview")
        metrics = self.ttk.Frame(frame)
        metrics.grid(row=0, column=0, columnspan=2, sticky="ew", pady=(0, 8))
        self.metric_vars = {}
        for column, (name, label) in enumerate((
            ("items", "Evaluated items"), ("prices", "Price range"),
            ("categories", "Categories"), ("review", "Review flags"),
            ("errors", "Errors"),
        )):
            metrics.columnconfigure(column, weight=1)
            box = self.ttk.LabelFrame(metrics, text=label, padding=6)
            box.grid(row=0, column=column, sticky="ew", padx=3)
            variable = self.tk.StringVar(value="—")
            self.metric_vars[name] = variable
            self.ttk.Label(box, textvariable=variable, font=("TkDefaultFont", 14, "bold")).pack()
        self.category_chart = self.tk.Canvas(frame, height=250, background="white", highlightthickness=1)
        self.category_chart.grid(row=1, column=0, sticky="nsew", padx=(0, 4))
        self.price_chart = self.tk.Canvas(frame, height=250, background="white", highlightthickness=1)
        self.price_chart.grid(row=1, column=1, sticky="nsew", padx=(4, 0))
        self.category_chart.bind("<Configure>", lambda event: self._redraw())
        self.price_chart.bind("<Configure>", lambda event: self._redraw())
        categories = self.ttk.LabelFrame(frame, text="Category price summary", padding=4)
        categories.grid(row=2, column=0, columnspan=2, sticky="nsew", pady=(8, 0))
        self.category_tree = self._tree(categories, [
            ("category", 170), ("count", 80), ("min", 80),
            ("median", 90), ("max", 80), ("unique", 80),
        ])

    def _tree(self, parent: Any, columns: list[tuple[str, int]], hierarchical: bool = False) -> Any:
        frame = self.ttk.Frame(parent)
        frame.pack(fill="both", expand=True)
        tree = self.ttk.Treeview(
            frame, columns=[name for name, _ in columns],
            show="tree headings" if hierarchical else "headings",
        )
        y_scrollbar = self.ttk.Scrollbar(frame, orient="vertical", command=tree.yview)
        x_scrollbar = self.ttk.Scrollbar(frame, orient="horizontal", command=tree.xview)
        tree.configure(yscrollcommand=y_scrollbar.set, xscrollcommand=x_scrollbar.set)
        frame.columnconfigure(0, weight=1)
        frame.rowconfigure(0, weight=1)
        tree.grid(row=0, column=0, sticky="nsew")
        y_scrollbar.grid(row=0, column=1, sticky="ns")
        x_scrollbar.grid(row=1, column=0, sticky="ew")
        if hierarchical:
            tree.heading("#0", text="item / category")
            tree.column("#0", width=260, minwidth=180, anchor="w")
        for name, width in columns:
            tree.heading(name, text=name)
            tree.column(name, width=width, anchor="w")
        return tree

    def _build_items(self) -> None:
        frame = self.ttk.Frame(self.notebook, padding=8)
        self.notebook.add(frame, text="Items")
        toolbar = self.ttk.Frame(frame)
        toolbar.pack(fill="x", pady=(0, 6))
        self.item_search_var = self.tk.StringVar()
        self.ttk.Label(toolbar, text="Find item or evidence").pack(side="left")
        self.ttk.Entry(toolbar, textvariable=self.item_search_var, width=30).pack(
            side="left", padx=(6, 10)
        )
        self.item_search_var.trace_add("write", lambda *_: self._refresh_item_tree())
        self.ttk.Label(toolbar, text="Review").pack(side="left")
        self.item_review_var = self.tk.StringVar(value="All")
        self.item_review_combo = self.ttk.Combobox(
            toolbar, textvariable=self.item_review_var,
            values=("All", "Review", "OK", "Error"), state="readonly", width=10,
        )
        self.item_review_combo.pack(side="left", padx=(6, 10))
        self.item_review_combo.bind("<<ComboboxSelected>>", lambda _event: self._refresh_item_tree())
        self.ttk.Button(
            toolbar, text="Collapse all", command=self._collapse_item_categories
        ).pack(side="left", padx=(4, 0))
        self.ttk.Button(
            toolbar, text="Expand Food", command=self._expand_food_category
        ).pack(side="left", padx=(4, 0))
        self.ttk.Button(
            toolbar, text="Expand all", command=self._expand_item_categories
        ).pack(side="left", padx=(4, 0))
        self.ttk.Button(
            toolbar, text="Clear search", command=self._clear_item_filters
        ).pack(side="left", padx=(4, 0))
        self.item_count_var = self.tk.StringVar(value="0 shown")
        self.ttk.Label(toolbar, textvariable=self.item_count_var).pack(side="right")
        self.ttk.Label(
            frame,
            text=(
                "Hierarchy: main category → subcategory → primary tag → item. "
                "Use Expand Food to inspect every food row; review flags are triage hints, "
                "not confirmed false positives."
            ),
        ).pack(fill="x", pady=(0, 4))
        self.item_category_nodes: dict[str, str] = {}
        self.item_row_by_iid: dict[str, dict[str, Any]] = {}
        self.item_columns = [
            ("price", 80), ("review", 90), ("reason", 320),
            ("detector", 140), ("resolver", 160), ("confidence", 90),
            ("mod", 170), ("description", 300),
        ]
        self.item_tree = self._tree(frame, [
            *self.item_columns,
        ], hierarchical=True)
        # Alternating row colors (zebra striping) keep long expanded lists
        # readable without hiding the hierarchy in repeated columns.
        self.item_tree.tag_configure("item-even", background="#ffffff")
        self.item_tree.tag_configure("item-odd", background="#f0f0f0")
        self.item_tree.bind("<<TreeviewSelect>>", lambda _event: self._show_item_details())
        self.ttk.Label(frame, text="Selected item runtime evidence").pack(anchor="w", pady=(6, 2))
        self.item_detail = self.scrolledtext.ScrolledText(
            frame, height=9, wrap="none", state="disabled"
        )
        self.item_detail.pack(fill="both", expand=False)

    def _build_review(self) -> None:
        frame = self.ttk.Frame(self.notebook, padding=8)
        self.notebook.add(frame, text="Classification review")
        self.ttk.Label(
            frame,
            text=(
                "Rows below need a human check. Inspect the reason, source, tags, and definition "
                "before changing a classifier rule."
            ),
        ).pack(fill="x", pady=(0, 6))
        self.review_count_var = self.tk.StringVar(value="0 flagged rows")
        self.ttk.Label(frame, textvariable=self.review_count_var).pack(anchor="w", pady=(0, 4))
        self.review_tree = self._tree(frame, [
            ("item", 220), ("status", 80), ("reason", 360), ("category", 110),
            ("primary", 180), ("confidence", 90), ("source", 180),
            ("mod", 150), ("tags", 300),
        ])

    def _build_low_confidence(self) -> None:
        frame = self.ttk.Frame(self.notebook, padding=8)
        self.notebook.add(frame, text="Low confidence")
        toolbar = self.ttk.Frame(frame)
        toolbar.pack(fill="x", pady=(0, 6))
        self.ttk.Label(toolbar, text="Confidence below").pack(side="left")
        self.confidence_threshold_var = self.tk.StringVar(
            value=str(getattr(self.args, "confidence_threshold", 0.5))
        )
        threshold_entry = self.ttk.Entry(
            toolbar, textvariable=self.confidence_threshold_var, width=8
        )
        threshold_entry.pack(side="left", padx=(6, 6))
        threshold_entry.bind("<Return>", lambda _event: self._refresh_low_confidence())
        threshold_entry.bind("<FocusOut>", lambda _event: self._refresh_low_confidence())
        self.ttk.Button(
            toolbar, text="Refresh", command=self._refresh_low_confidence
        ).pack(side="left")
        self.ttk.Button(
            toolbar, text="Save JSONL…", command=self.save_low_confidence_jsonl
        ).pack(side="left", padx=(12, 4))
        self.ttk.Button(
            toolbar, text="Save CSV…", command=self.save_low_confidence_csv
        ).pack(side="left")
        self.low_confidence_count_var = self.tk.StringVar(value="0 rows")
        self.ttk.Label(toolbar, textvariable=self.low_confidence_count_var).pack(
            side="right"
        )
        self.ttk.Label(
            frame,
            text=(
                "This is the complete sorted candidate list for heuristic review. "
                "Exports include the item definition, runtime context, detector evidence, "
                "and price audit so the Lua rules can be updated from evidence."
            ),
        ).pack(fill="x", pady=(0, 6))
        self.low_confidence_tree = self._tree(frame, [
            ("item", 240), ("confidence", 90), ("category", 110),
            ("subcategory", 140), ("primary", 220), ("detector", 140),
            ("resolver", 160), ("mod", 160), ("reason", 380),
        ])

    def _build_sandbox(self) -> None:
        frame = self.ttk.Frame(self.notebook, padding=8)
        self.notebook.add(frame, text="Sandbox pricing")
        self.sandbox_search_var = self.tk.StringVar()
        toolbar = self.ttk.Frame(frame)
        toolbar.pack(fill="x", pady=(0, 6))
        self.ttk.Label(toolbar, text="Find setting").pack(side="left")
        self.ttk.Entry(toolbar, textvariable=self.sandbox_search_var, width=32).pack(
            side="left", padx=(6, 10)
        )
        self.sandbox_search_var.trace_add("write", lambda *_: self._refresh_sandbox_tree())
        self.ttk.Button(toolbar, text="Save", command=self.save_sandbox).pack(side="left")
        self.ttk.Button(toolbar, text="Load…", command=self.load_sandbox).pack(
            side="left", padx=(4, 0)
        )
        self.ttk.Button(toolbar, text="Save as…", command=self.save_sandbox_as).pack(
            side="left", padx=(4, 0)
        )
        self.ttk.Button(toolbar, text="Reset all", command=self.reset_sandbox).pack(
            side="left", padx=(12, 0)
        )
        self.ttk.Button(
            toolbar, text="Apply & rescan", command=self.scan
        ).pack(side="left", padx=(12, 0))
        self.sandbox_count_var = self.tk.StringVar(value="0 overrides")
        self.ttk.Label(toolbar, textvariable=self.sandbox_count_var).pack(side="right")
        self.ttk.Label(
            frame,
            text=(
                "Overrides are applied as SandboxVars.MarketSense inside the Lua harness. "
                "Blank/inherit leaves the mod's declared sandbox default active. "
                f"Saved settings: {self.sandbox_path}"
            ),
        ).pack(fill="x", pady=(0, 6))
        self.sandbox_tree = self._tree(frame, [
            ("key", 230), ("value", 100), ("default", 110), ("type", 80),
            ("page", 150), ("description", 440),
        ])
        self.sandbox_tree.bind("<<TreeviewSelect>>", lambda _event: self._select_sandbox_setting())
        editor = self.ttk.LabelFrame(frame, text="Selected setting", padding=6)
        editor.pack(fill="x", pady=(8, 0))
        editor.columnconfigure(1, weight=1)
        self.sandbox_selected_key_var = self.tk.StringVar(value="—")
        self.sandbox_value_var = self.tk.StringVar()
        self.sandbox_description_var = self.tk.StringVar(value="Select a setting to edit it.")
        self.ttk.Label(editor, text="Key").grid(row=0, column=0, sticky="w", padx=(0, 6))
        self.ttk.Label(editor, textvariable=self.sandbox_selected_key_var).grid(
            row=0, column=1, sticky="w"
        )
        self.ttk.Label(editor, text="Value").grid(row=1, column=0, sticky="w", padx=(0, 6))
        self.sandbox_value_entry = self.ttk.Entry(
            editor, textvariable=self.sandbox_value_var, width=18
        )
        self.sandbox_value_entry.grid(row=1, column=1, sticky="w")
        self.sandbox_value_entry.bind("<Return>", lambda _event: self.apply_sandbox_value())
        self.ttk.Button(editor, text="Apply override", command=self.apply_sandbox_value).grid(
            row=1, column=2, padx=(8, 0)
        )
        self.ttk.Button(editor, text="Use default / inherit", command=self.clear_sandbox_value).grid(
            row=1, column=3, padx=(4, 0)
        )
        self.ttk.Label(editor, textvariable=self.sandbox_description_var).grid(
            row=2, column=0, columnspan=4, sticky="w", pady=(4, 0)
        )
        self._refresh_sandbox_tree()

    def _refresh_low_confidence(self) -> None:
        if not hasattr(self, "low_confidence_tree"):
            return
        try:
            threshold = self._confidence_threshold()
        except ValueError:
            self.low_confidence_count_var.set("invalid threshold")
            return
        self.low_confidence_tree.delete(*self.low_confidence_tree.get_children())
        selected = low_confidence_rows(self.rows, threshold)
        for row in selected:
            _status, reason = review_row(row)
            hierarchy = row.get("hierarchy") if isinstance(row.get("hierarchy"), dict) else {}
            self.low_confidence_tree.insert("", "end", values=(
                row.get("fullType", ""), row.get("confidence", ""),
                row.get("category") or hierarchy.get("root", ""),
                row.get("subcategory") or hierarchy.get("subcategory", ""),
                row.get("primary") or "", row.get("detector", ""),
                row.get("resolver", ""), row.get("workshopMod", ""), reason,
            ))
        self.low_confidence_count_var.set(
            f"{len(selected):,} rows below {threshold:.2f}"
        )

    def _confidence_threshold(self) -> float:
        value = float(self.confidence_threshold_var.get().strip())
        if not 0.0 <= value <= 1.0:
            raise ValueError("confidence threshold must be between 0 and 1")
        return value

    def _refresh_sandbox_tree(self) -> None:
        if not hasattr(self, "sandbox_tree"):
            return
        self.sandbox_tree.delete(*self.sandbox_tree.get_children())
        query = self.sandbox_search_var.get().strip().casefold()
        for spec in self.sandbox_specs:
            haystack = " ".join((spec.key, spec.label, spec.tooltip, spec.page)).casefold()
            if query and query not in haystack:
                continue
            current = self.sandbox_overrides.get(spec.key)
            default = "inherit" if spec.default is None else str(spec.default)
            description = spec.label
            if spec.tooltip:
                description = f"{description} — {spec.tooltip}"
            self.sandbox_tree.insert("", "end", iid=f"sandbox:{spec.key}", values=(
                spec.key,
                "inherit" if current is None else str(current),
                default,
                spec.option_type,
                spec.page,
                description,
            ))
        self.sandbox_count_var.set(
            f"{len(self.sandbox_overrides):,} overrides / {len(self.sandbox_specs):,} settings"
        )

    def _selected_sandbox_spec(self) -> SandboxOption | None:
        selection = self.sandbox_tree.selection()
        if not selection:
            return None
        key = selection[0].removeprefix("sandbox:")
        return self.sandbox_spec_by_key.get(key)

    def _select_sandbox_setting(self) -> None:
        spec = self._selected_sandbox_spec()
        if spec is None:
            return
        self.sandbox_selected_key_var.set(spec.key)
        current = self.sandbox_overrides.get(spec.key)
        self.sandbox_value_var.set("" if current is None else str(current))
        range_text = ""
        if spec.minimum is not None or spec.maximum is not None:
            range_text = f"range {spec.minimum:g}..{spec.maximum:g}"
        self.sandbox_description_var.set(
            f"{spec.label} | {spec.option_type} | {range_text or 'unbounded'} | "
            f"blank means inherit/default"
        )

    def apply_sandbox_value(self) -> None:
        spec = self._selected_sandbox_spec()
        if spec is None:
            self.messagebox.showinfo("Sandbox pricing", "Select a sandbox setting first.")
            return
        try:
            values = normalize_settings(
                {spec.key: self.sandbox_value_var.get()}, self.sandbox_specs
            )
        except SandboxSettingsError as error:
            self.messagebox.showerror("Invalid sandbox value", str(error))
            return
        if spec.key not in values:
            self.messagebox.showerror("Invalid sandbox value", "Enter a finite numeric value.")
            return
        self.sandbox_overrides[spec.key] = values[spec.key]
        self._refresh_sandbox_tree()
        self.sandbox_tree.selection_set(f"sandbox:{spec.key}")
        self.status_var.set(f"Sandbox override applied for {spec.key}; scan to recalculate prices.")

    def clear_sandbox_value(self) -> None:
        spec = self._selected_sandbox_spec()
        if spec is None:
            return
        self.sandbox_overrides.pop(spec.key, None)
        self.sandbox_value_var.set("")
        self._refresh_sandbox_tree()
        self.sandbox_tree.selection_set(f"sandbox:{spec.key}")

    def save_sandbox(self) -> None:
        try:
            path = save_sandbox_settings(self.sandbox_path, self.sandbox_overrides, self.sandbox_specs)
        except (OSError, SandboxSettingsError) as error:
            self.messagebox.showerror("Save sandbox settings", str(error))
            return
        self.sandbox_path = path
        self.status_var.set(f"Saved {len(self.sandbox_overrides)} sandbox override(s) to {path}.")

    def save_sandbox_as(self) -> None:
        path = self.filedialog.asksaveasfilename(
            title="Save MarketSense sandbox settings",
            defaultextension=".json",
            filetypes=[("JSON", "*.json"), ("All files", "*.*")],
        )
        if path:
            self.sandbox_path = Path(path).expanduser()
            self.save_sandbox()

    def load_sandbox(self) -> None:
        path = self.filedialog.askopenfilename(
            title="Load MarketSense sandbox settings",
            filetypes=[("JSON", "*.json"), ("All files", "*.*")],
        )
        if not path:
            return
        try:
            values = load_sandbox_settings(Path(path), self.sandbox_specs)
        except (OSError, SandboxSettingsError) as error:
            self.messagebox.showerror("Load sandbox settings", str(error))
            return
        self.sandbox_path = Path(path).expanduser()
        self.sandbox_overrides = values
        self._refresh_sandbox_tree()
        self.status_var.set(f"Loaded {len(values)} sandbox override(s) from {path}.")

    def reset_sandbox(self) -> None:
        if not self.messagebox.askyesno(
            "Reset sandbox settings", "Remove all local sandbox overrides?"
        ):
            return
        self.sandbox_overrides = {}
        self._refresh_sandbox_tree()
        self.status_var.set("Sandbox overrides cleared; the mod's defaults will be used.")

    def _clear_item_filters(self) -> None:
        self.item_search_var.set("")
        self.item_review_var.set("All")

    def _collapse_item_categories(self) -> None:
        for item_id in self.item_category_nodes.values():
            self._set_item_group_open(item_id, False)

    def _expand_item_categories(self) -> None:
        for item_id in self.item_category_nodes.values():
            self._set_item_group_open(item_id, True)

    def _expand_food_category(self) -> None:
        item_id = self.item_category_nodes.get("Food")
        if item_id is None:
            self.status_var.set("Food category is not present in the current filtered results.")
            return
        self._set_item_group_open(item_id, True)
        self.item_tree.see(item_id)

    def _set_item_group_open(self, item_id: str, is_open: bool) -> None:
        self.item_tree.item(item_id, open=is_open)
        for child_id in self.item_tree.get_children(item_id):
            if self.item_tree.get_children(child_id):
                self._set_item_group_open(child_id, is_open)

    def _build_mods(self) -> None:
        frame = self.ttk.Frame(self.notebook, padding=8)
        self.notebook.add(frame, text="Workshop mods")
        self.mod_tree = self._tree(frame, [
            ("id", 180), ("name", 260), ("workshop", 110), ("version", 110),
            ("items", 80), ("source", 90),
        ])

    def _browse_workshop(self) -> None:
        selected = self.filedialog.askdirectory(title="Select a Steam Workshop root")
        if selected:
            self.workshop_var.set(selected)

    def _options(self) -> ScanOptions:
        raw_roots = self.workshop_var.get().strip()
        roots = tuple(
            Path(part.strip()).expanduser()
            for part in raw_roots.split(os.pathsep)
            if part.strip()
        ) if raw_roots else tuple(default_roots())
        filters = tuple(part.strip() for part in self.filter_var.get().split(",") if part.strip())
        max_items = int(self.max_items_var.get() or 0)
        confidence_threshold = self._confidence_threshold()
        game_root = self.game_root_var.get().strip()
        return ScanOptions(
            workshop_roots=roots,
            filters=filters,
            game_version=self.version_var.get().strip() or "42.20",
            game_root=Path(game_root).expanduser() if game_root else None,
            no_base_game=self.no_base_var.get(),
            max_items=max_items,
            cache_dir=self.args.cache_dir or DEFAULT_CACHE_DIR,
            use_cache=self.use_cache_var.get(),
            refresh_cache=self.refresh_cache_var.get(),
            confidence_threshold=confidence_threshold,
            sandbox_options=dict(self.sandbox_overrides),
        )

    def scan(self) -> None:
        try:
            options = self._options()
        except ValueError as error:
            self.messagebox.showerror("Invalid settings", str(error))
            return
        self._start("scan", options)

    def self_test(self) -> None:
        self._start("self-test", None)

    def _start(self, operation: str, options: ScanOptions | None) -> None:
        if self.busy:
            return
        self.busy = True
        for button in (self.scan_button, self.test_button, self.clear_button):
            button.configure(state="disabled")
        self.progress.start(12)
        self.status_var.set("Running real MarketSense Lua evaluator…")
        threading.Thread(target=self._worker, args=(operation, options), daemon=True).start()

    def _worker(self, operation: str, options: ScanOptions | None) -> None:
        try:
            lua = find_lua(self.args.lua)
            if operation == "self-test":
                passed, checks = run_self_test(lua)
                self.root.after(0, lambda: self._show_self_test(passed, checks))
            else:
                summary, rows = evaluate(lua, options)
                self.root.after(0, lambda: self._show_results(summary, rows))
        except Exception as error:  # surface diagnostics in the GUI, not just stderr
            details = f"{type(error).__name__}: {error}\n\n{traceback.format_exc()}"
            self.root.after(0, lambda: self._show_error(details))

    def _finish(self) -> None:
        self.busy = False
        self.progress.stop()
        for button in (self.scan_button, self.test_button, self.clear_button):
            button.configure(state="normal")

    def _show_self_test(self, passed: bool, checks: list[dict[str, Any]]) -> None:
        self._finish()
        self._write_log("MarketSense self-test\n" + "\n".join(
            f"{'PASS' if check['passed'] else 'FAIL'}: {check['name']} — {check['detail']}"
            for check in checks
        ))
        self.status_var.set(f"Self-test {'passed' if passed else 'failed'} ({sum(c['passed'] for c in checks)}/{len(checks)} checks).")

    def _show_results(self, summary: dict[str, Any], rows: list[dict[str, Any]]) -> None:
        self._finish()
        self.summary, self.rows = summary, rows
        prices = summary["prices"]
        self.metric_vars["items"].set(str(summary["evaluated"]))
        self.metric_vars["prices"].set(f"{prices['min']:g} – {prices['max']:g}")
        self.metric_vars["categories"].set(str(len(summary["categories"])))
        flagged = review_count(rows)
        self.metric_vars["review"].set(str(flagged))
        self.metric_vars["errors"].set(str(summary["errors"]))
        self._fill_trees()
        self._redraw()
        self.save_button.configure(state="normal")
        self.csv_button.configure(state="normal")
        self.status_var.set(
            f"Scan complete: {summary['evaluated']} items, {summary['workshop_mods']} Workshop mods, "
            f"{summary.get('vanilla_items', 0)} vanilla items, {summary.get('workshop_items', 0)} Workshop items, "
            f"{summary['errors']} errors, {flagged} review flags. "
            f"Cache: {(summary.get('cache') or {}).get('status', 'disabled')}. "
            f"Version ceiling: {summary['workshop_script_selection']}"
        )
        self._write_log(json.dumps({"summary": summary, "items": rows}, indent=2, sort_keys=True))

    def _fill_trees(self) -> None:
        for tree in (
            self.category_tree if hasattr(self, "category_tree") else None,
            self.item_tree, self.review_tree, self.mod_tree,
        ):
            if tree:
                tree.delete(*tree.get_children())
        self.category_tree = getattr(self, "category_tree", None)
        if self.category_tree is None:
            return
        for category, data in self.summary["categories"].items():
            self.category_tree.insert("", "end", values=(
                category, data["count"], f"{data['min']:g}", f"{data['median']:g}",
                f"{data['max']:g}", data["unique"],
            ))
        self._refresh_item_tree()
        self._refresh_low_confidence()
        flagged_rows = [row for row in self.rows if review_row(row)[0] != "OK"]
        self.review_count_var.set(f"{len(flagged_rows):,} flagged rows")
        for row in sorted(flagged_rows, key=lambda item: str(item.get("fullType", ""))):
            status, reason = review_row(row)
            self.review_tree.insert("", "end", values=(
                row.get("fullType", ""), status, reason,
                row.get("category") or "Unclassified", row.get("primary") or "Unclassified",
                row.get("confidence", ""), row.get("source", ""),
                row.get("workshopMod", ""), ", ".join(row.get("expandedTags") or row.get("tags") or []),
            ))
        counts = self.summary["mods_with_items"]
        for mod in self.summary["mods"]:
            self.mod_tree.insert("", "end", values=(
                mod["id"], mod["name"], mod["workshop_id"], mod["script_version"],
                counts.get(mod["id"], 0), mod["source"],
            ))

    def _refresh_item_tree(self) -> None:
        if not hasattr(self, "item_tree"):
            return
        self.item_tree.delete(*self.item_tree.get_children())
        self.item_category_nodes.clear()
        self.item_row_by_iid.clear()
        query = self.item_search_var.get().strip().casefold()
        review_filter = self.item_review_var.get().casefold()
        grouped: dict[str, dict[str, dict[str, list[tuple[dict[str, Any], str, str]]]]] = {}
        for row in sorted(
            self.rows,
            key=lambda item: (float(item.get("price") or 0), str(item.get("fullType", ""))),
            reverse=True,
        ):
            status, reason = review_row(row)
            if review_filter != "all" and status.casefold() != review_filter:
                continue
            if query and query not in searchable_text(row):
                continue
            hierarchy = row.get("hierarchy") if isinstance(row.get("hierarchy"), dict) else {}
            category = str(row.get("category") or hierarchy.get("root") or "Unclassified")
            subcategory = str(
                row.get("subcategory") or hierarchy.get("subcategory") or "Unclassified"
            )
            primary = str(row.get("primary") or hierarchy.get("token") or "Unclassified")
            grouped.setdefault(category, {}).setdefault(subcategory, {}).setdefault(primary, []).append(
                (row, status, reason)
            )

        shown = sum(
            len(items)
            for subcategories in grouped.values()
            for primaries in subcategories.values()
            for items in primaries.values()
        )
        item_row_number = 0
        for category, subcategories in sorted(grouped.items()):
            category_count = sum(
                len(items)
                for primaries in subcategories.values()
                for items in primaries.values()
            )
            category_id = self.item_tree.insert(
                "", "end", text=f"{category} ({category_count:,})", open=False,
                values=("", "", f"{category_count:,} items", "", "", "", "", ""),
            )
            self.item_category_nodes[category] = category_id
            for subcategory, primaries in sorted(subcategories.items()):
                subcategory_count = sum(len(items) for items in primaries.values())
                subcategory_id = self.item_tree.insert(
                    category_id, "end", text=f"{subcategory} ({subcategory_count:,})", open=False,
                    values=(
                        "", "", f"{subcategory_count:,} items", "", "", "", "", "",
                    ),
                )
                for primary, primary_rows in sorted(primaries.items()):
                    primary_count = len(primary_rows)
                    primary_label = primary
                    first_hierarchy = primary_rows[0][0].get("hierarchy")
                    if isinstance(first_hierarchy, dict) and first_hierarchy.get("leaf"):
                        leaf = str(first_hierarchy["leaf"])
                        if leaf != primary:
                            primary_label = f"{leaf} [{primary}]"
                    primary_id = self.item_tree.insert(
                        subcategory_id, "end", text=f"{primary_label} ({primary_count:,})", open=False,
                        values=(
                            "", "", f"{primary_count:,} items", "", "", "", "", "",
                        ),
                    )
                    for row, status, reason in primary_rows:
                        item_id = self.item_tree.insert(
                            primary_id, "end", text=row.get("fullType") or "<unknown>", values=(
                                row.get("price", ""), status, reason,
                                row.get("detector", ""), row.get("resolver", ""),
                                row.get("confidence", ""), row.get("workshopMod", ""),
                                row.get("description", ""),
                            ), tags=("item-even" if item_row_number % 2 == 0 else "item-odd",)
                        )
                        self.item_row_by_iid[item_id] = row
                        item_row_number += 1
        self.item_count_var.set(
            f"{shown:,} items in {len(grouped):,} categories / {len(self.rows):,} total"
        )

    def _show_item_details(self) -> None:
        selection = self.item_tree.selection()
        row = self.item_row_by_iid.get(selection[0]) if selection else None
        if row is None:
            detail = "Select an item row (the deepest level) to inspect its runtime evidence."
        else:
            status, reason = review_row(row)
            detail_data = dict(row)
            detail_data["review"] = {"status": status, "reason": reason}
            detail = json.dumps(detail_data, indent=2, sort_keys=True)
        self.item_detail.configure(state="normal")
        self.item_detail.delete("1.0", "end")
        self.item_detail.insert("end", detail)
        self.item_detail.configure(state="disabled")

    def _redraw(self) -> None:
        if not self.summary:
            return
        self._bars(self.category_chart, "Categories", [
            (name, data["count"]) for name, data in self.summary["categories"].items()
        ])
        self._bars(self.price_chart, "Price distribution", [
            (data["bucket"], data["count"]) for data in self.summary["price_distribution"]
        ])

    def _bars(self, canvas: Any, title: str, values: list[tuple[str, int]]) -> None:
        canvas.delete("all")
        width, height = max(canvas.winfo_width(), 280), max(canvas.winfo_height(), 180)
        canvas.create_text(10, 12, anchor="w", text=title, font=("TkDefaultFont", 10, "bold"))
        if not values:
            canvas.create_text(width / 2, height / 2, text="No data")
            return
        left, top, right, bottom = 112, 32, width - 16, height - 18
        maximum = max(value for _, value in values) or 1
        slot = max(16, (bottom - top) / len(values))
        for index, (label, value) in enumerate(values):
            y = top + index * slot + slot / 2
            label = label if len(label) <= 16 else label[:15] + "…"
            canvas.create_text(left - 6, y, anchor="e", text=label)
            canvas.create_rectangle(left, y - slot * 0.3, left + (right - left) * value / maximum,
                                    y + slot * 0.3, fill="#4c78a8", outline="")
            canvas.create_text(right + 2, y, anchor="e", text=str(value))

    def _write_log(self, text: str) -> None:
        self.log.configure(state="normal")
        self.log.delete("1.0", "end")
        self.log.insert("end", text)
        self.log.configure(state="disabled")

    def save_json(self) -> None:
        if not self.summary:
            return
        path = self.filedialog.asksaveasfilename(
            title="Save MarketSense JSON", defaultextension=".json",
            filetypes=[("JSON", "*.json"), ("All files", "*.*")],
        )
        if path:
            Path(path).write_text(json.dumps({"summary": self.summary, "items": self.rows}, indent=2), encoding="utf-8")

    def save_csv(self) -> None:
        if not self.rows:
            return
        path = self.filedialog.asksaveasfilename(
            title="Save MarketSense CSV", defaultextension=".csv",
            filetypes=[("CSV", "*.csv"), ("All files", "*.*")],
        )
        if path:
            write_csv(Path(path), self.rows)

    def save_low_confidence_jsonl(self) -> None:
        if not self.rows:
            self.messagebox.showinfo("Low confidence", "Run a scan before exporting rows.")
            return
        try:
            threshold = self._confidence_threshold()
        except ValueError as error:
            self.messagebox.showerror("Invalid threshold", str(error))
            return
        path = self.filedialog.asksaveasfilename(
            title="Save low-confidence MarketSense rows",
            defaultextension=".jsonl",
            filetypes=[("JSON Lines", "*.jsonl"), ("JSON", "*.json"), ("All files", "*.*")],
        )
        if path:
            output = write_low_confidence_report(Path(path), self.rows, threshold)
            self.status_var.set(
                f"Saved {len(low_confidence_rows(self.rows, threshold))} low-confidence rows to {output}."
            )

    def save_low_confidence_csv(self) -> None:
        if not self.rows:
            self.messagebox.showinfo("Low confidence", "Run a scan before exporting rows.")
            return
        try:
            threshold = self._confidence_threshold()
        except ValueError as error:
            self.messagebox.showerror("Invalid threshold", str(error))
            return
        path = self.filedialog.asksaveasfilename(
            title="Save low-confidence MarketSense rows",
            defaultextension=".csv",
            filetypes=[("CSV", "*.csv"), ("All files", "*.*")],
        )
        if path:
            output = write_low_confidence_report(Path(path), self.rows, threshold)
            self.status_var.set(
                f"Saved {len(low_confidence_rows(self.rows, threshold))} low-confidence rows to {output}."
            )

    def clear_cache(self) -> None:
        if self.busy:
            return
        if not self.messagebox.askyesno("Clear cache", "Delete cached MarketSense scan results?"):
            return
        removed = clear_result_cache(self.args.cache_dir or DEFAULT_CACHE_DIR)
        self.status_var.set(f"Cleared {removed} cached result(s).")
        self._write_log(
            f"Cleared {removed} cached result(s) from "
            f"{self.args.cache_dir or DEFAULT_CACHE_DIR}"
        )

    def _show_error(self, details: str) -> None:
        self._finish()
        self.status_var.set("Operation failed — see Diagnostics for the traceback.")
        self._write_log(details)


def launch(args: Any) -> int:
    try:
        import tkinter as tk
        from tkinter import filedialog, messagebox, scrolledtext, ttk
    except ImportError as error:
        print(f"MarketSense GUI requires tkinter: {error}", file=sys.stderr)
        return 1
    try:
        root = tk.Tk()
    except tk.TclError as error:
        print(f"MarketSense GUI could not open a desktop window: {error}", file=sys.stderr)
        return 1
    MarketSenseGui(root, tk, ttk, scrolledtext, filedialog, messagebox, args)
    root.mainloop()
    return 0


if __name__ == "__main__":
    from .cli import parse_args

    gui_args = parse_args(sys.argv[1:])
    raise SystemExit(launch(gui_args))
