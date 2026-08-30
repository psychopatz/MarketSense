"""Scan-settings controls for the MarketSense GUI."""

from __future__ import annotations

from typing import Any

from .scan_scope import CATEGORY_SCOPE_CHOICES


def build_scan_controls(view: Any, root: Any) -> None:
    """Build the scan controls without owning scan or persistence behavior."""
    controls = view.ttk.LabelFrame(root, text="Scan settings", padding=8)
    controls.grid(row=0, column=0, sticky="ew", padx=8, pady=(8, 4))
    controls.columnconfigure(1, weight=1)
    controls.columnconfigure(3, weight=1)
    controls.columnconfigure(4, weight=1)

    view._entry(
        controls, 0, 0, "Workshop root(s)", view.workshop_var, 46
    )
    view.ttk.Button(
        controls, text="Browse…", command=view._browse_workshop
    ).grid(row=0, column=2, padx=(6, 12), sticky="w")
    view.ttk.Label(controls, text="Mod filter (view)").grid(
        row=0, column=3, sticky="w", padx=(0, 6), pady=2
    )
    view.mod_filter_combo = view.ttk.Combobox(
        controls,
        textvariable=view.mod_filter_var,
        state="readonly",
        width=32,
    )
    view.mod_filter_combo.grid(
        row=0, column=4, sticky="ew", pady=2
    )
    view.mod_filter_combo.bind(
        "<<ComboboxSelected>>",
        lambda _event: view._on_mod_filter_selected(),
    )
    view.ttk.Label(
        controls, textvariable=view.mod_filter_count_var
    ).grid(row=3, column=3, columnspan=2, sticky="w", pady=(0, 2))
    view._entry(
        controls, 1, 0, "Game version", view.version_var, 12
    )
    view._entry(
        controls, 1, 3, "Game root", view.game_root_var, 32
    )
    view.ttk.Button(
        controls, text="Browse…", command=view._browse_game_root
    ).grid(row=1, column=2, padx=(6, 12), sticky="w")
    view.ttk.Label(controls, text="Category (scan)").grid(
        row=2, column=0, sticky="w", padx=(0, 6), pady=2
    )
    category_choices = list(CATEGORY_SCOPE_CHOICES)
    selected_category = view.category_scope_var.get()
    if selected_category not in category_choices:
        category_choices.append(selected_category)
    view.category_scope_combo = view.ttk.Combobox(
        controls,
        textvariable=view.category_scope_var,
        values=tuple(category_choices),
        state="readonly",
        width=18,
    )
    view.category_scope_combo.grid(row=2, column=1, sticky="w", pady=2)
    view.category_scope_combo.bind(
        "<<ComboboxSelected>>",
        lambda _event: view._on_category_scope_selected(),
    )
    cache_options = view.ttk.Frame(controls)
    cache_options.grid(row=2, column=3, columnspan=2, sticky="w")
    view.ttk.Checkbutton(
        cache_options, text="Skip vanilla (view)", variable=view.no_base_var
    ).pack(side="left")
    view.ttk.Checkbutton(
        cache_options, text="Use cache", variable=view.use_cache_var
    ).pack(side="left", padx=(10, 0))
    view.ttk.Checkbutton(
        cache_options, text="Refresh", variable=view.refresh_cache_var
    ).pack(side="left", padx=(10, 0))
    view._entry(controls, 3, 0, "Max shown (view)", view.max_items_var, 12)
    view.ttk.Label(controls, text="Availability (view)").grid(
        row=4, column=0, sticky="w", padx=(0, 6), pady=2
    )
    view.availability_combo = view.ttk.Combobox(
        controls,
        textvariable=view.availability_var,
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
    view.availability_combo.grid(row=4, column=1, sticky="w", pady=2)
    view.availability_combo.bind(
        "<<ComboboxSelected>>",
        lambda _event: view._apply_view_filters(),
    )

    buttons = view.ttk.Frame(controls)
    buttons.grid(row=5, column=0, columnspan=5, sticky="w", pady=(8, 0))
    view.scan_button = view.ttk.Button(
        buttons, text="Scan selected scope / cache", command=view.scan
    )
    view.scan_button.pack(side="left")
    view.test_button = view.ttk.Button(
        buttons, text="Run self-test", command=view.self_test
    )
    view.test_button.pack(side="left", padx=6)
    view.save_button = view.ttk.Button(
        buttons,
        text="Save JSON…",
        command=view.save_json,
        state="disabled",
    )
    view.save_button.pack(side="left")
    view.csv_button = view.ttk.Button(
        buttons,
        text="Save CSV…",
        command=view.save_csv,
        state="disabled",
    )
    view.csv_button.pack(side="left", padx=6)
    view.clear_button = view.ttk.Button(
        buttons, text="Clear cache", command=view.clear_cache
    )
    view.clear_button.pack(side="left")
    view.progress = view.ttk.Progressbar(
        buttons, mode="indeterminate", length=160
    )
    view.progress.pack(side="left", padx=(16, 0))
