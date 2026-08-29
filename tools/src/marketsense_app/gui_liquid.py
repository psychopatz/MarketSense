"""Dedicated per-litre liquid pricing editor for the Market Sense inspector."""

from __future__ import annotations

import json
from typing import Any

from .liquid_pricing import (
    LiquidPriceRow,
    LiquidPricingError,
    load_liquid_catalog,
    save_liquid_overrides,
)


class LiquidPricingMixin:
    """Expose fluid content anchors without mixing them with sandbox pricing."""

    def _build_liquid_pricing(self) -> None:
        frame = self.ttk.Frame(self.notebook, padding=8)
        self.notebook.add(frame, text="Liquid pricing")
        self.liquid_catalog = None
        self.liquid_row_by_iid: dict[str, LiquidPriceRow] = {}
        self.liquid_search_var = self.tk.StringVar()
        self.liquid_selected_key_var = self.tk.StringVar(value="—")
        self.liquid_price_var = self.tk.StringVar()
        self.liquid_detail_var = self.tk.StringVar(
            value="Select a liquid row to edit its content anchor."
        )
        self.liquid_status_var = self.tk.StringVar(value="Loading liquid price data…")

        toolbar = self.ttk.Frame(frame)
        toolbar.pack(fill="x", pady=(0, 6))
        self.ttk.Label(toolbar, text="Find liquid").pack(side="left")
        self.ttk.Entry(toolbar, textvariable=self.liquid_search_var, width=28).pack(
            side="left", padx=(6, 10)
        )
        self.liquid_search_var.trace_add(
            "write", lambda *_args: self._refresh_liquid_tree()
        )
        self.ttk.Button(
            toolbar, text="Reload", command=self.reload_liquid_pricing
        ).pack(side="left")
        self.ttk.Button(
            toolbar, text="Save overrides", command=self.save_liquid_pricing
        ).pack(side="left", padx=(4, 0))
        self.ttk.Button(
            toolbar, text="Reset selected", command=self.reset_liquid_selected
        ).pack(side="left", padx=(12, 0))
        self.ttk.Button(
            toolbar, text="Reset all", command=self.reset_liquid_all
        ).pack(side="left", padx=(4, 0))
        self.ttk.Button(
            toolbar, text="Apply & rescan", command=self.apply_liquid_pricing
        ).pack(side="left", padx=(12, 0))
        self.liquid_count_var = self.tk.StringVar(value="0 rows")
        self.ttk.Label(toolbar, textvariable=self.liquid_count_var).pack(side="right")

        self.ttk.Label(
            frame,
            text=(
                "Independent fluid-content prices. Values are dollars per litre; "
                "the bottle, can, bag, or other vessel is not included. Base anchors "
                "are shipped in MS_LiquidPricing_Data.lua; edits are sparse overrides "
                "in MS_LiquidPricing_Overrides_Data.lua."
            ),
        ).pack(fill="x", pady=(0, 4))
        self.ttk.Label(frame, textvariable=self.liquid_status_var).pack(
            fill="x", pady=(0, 6)
        )
        self.liquid_tree = self._tree(frame, [
            ("kind", 105), ("fluid", 190), ("primary", 180),
            ("$/litre", 95), ("base", 95), ("source", 95),
            ("notes", 520),
        ])
        self.liquid_tree.bind(
            "<<TreeviewSelect>>", lambda _event: self._select_liquid_price()
        )

        editor = self.ttk.LabelFrame(frame, text="Selected liquid content anchor", padding=6)
        editor.pack(fill="x", pady=(8, 0))
        editor.columnconfigure(1, weight=1)
        self.ttk.Label(editor, text="Key").grid(
            row=0, column=0, sticky="w", padx=(0, 6)
        )
        self.ttk.Label(editor, textvariable=self.liquid_selected_key_var).grid(
            row=0, column=1, sticky="w"
        )
        self.ttk.Label(editor, text="$/litre").grid(
            row=1, column=0, sticky="w", padx=(0, 6)
        )
        self.liquid_price_entry = self.ttk.Entry(
            editor, textvariable=self.liquid_price_var, width=16
        )
        self.liquid_price_entry.grid(row=1, column=1, sticky="w")
        self.liquid_price_entry.bind(
            "<Return>", lambda _event: self.apply_liquid_price()
        )
        self.ttk.Button(
            editor, text="Apply override", command=self.apply_liquid_price
        ).grid(row=1, column=2, padx=(8, 0))
        self.ttk.Button(
            editor, text="Use base default", command=self.reset_liquid_selected
        ).grid(row=1, column=3, padx=(4, 0))
        self.ttk.Label(editor, textvariable=self.liquid_detail_var).grid(
            row=2, column=0, columnspan=4, sticky="w", pady=(4, 0)
        )
        self._load_liquid_catalog()

    def _load_liquid_catalog(self) -> None:
        try:
            self.liquid_catalog = load_liquid_catalog(getattr(self.args, "lua", None))
        except (LiquidPricingError, OSError) as error:
            self.liquid_catalog = None
            self.liquid_status_var.set(f"Liquid pricing unavailable: {error}")
            if hasattr(self, "log"):
                self._append_log(json.dumps({
                    "event": "liquid_pricing_load_error",
                    "error": str(error),
                }, sort_keys=True))
            return
        self._refresh_liquid_tree()
        self.liquid_status_var.set(
            f"{len(self.liquid_catalog.exact):,} exact fluids, "
            f"{len(self.liquid_catalog.families):,} family fallbacks, "
            f"1 unknown/default fallback."
        )

    def reload_liquid_pricing(self) -> None:
        self._load_liquid_catalog()
        self.status_var.set("Liquid price data reloaded from the Market Sense Lua files.")

    def _refresh_liquid_tree(self) -> None:
        if not hasattr(self, "liquid_tree"):
            return
        self.liquid_tree.delete(*self.liquid_tree.get_children())
        self.liquid_row_by_iid.clear()
        if self.liquid_catalog is None:
            self.liquid_count_var.set("0 rows")
            return
        rows = self.liquid_catalog.rows(self.liquid_search_var.get())
        for row in rows:
            self.liquid_row_by_iid[row.iid] = row
            base = "—" if row.base_price_per_liter is None else f"{row.base_price_per_liter:g}"
            self.liquid_tree.insert(
                "", "end", iid=row.iid,
                values=(
                    row.kind,
                    row.key,
                    row.primary,
                    f"{row.price_per_liter:g}",
                    base,
                    row.source,
                    row.note,
                ),
            )
        total = len(self.liquid_catalog.rows())
        self.liquid_count_var.set(f"{len(rows):,} shown / {total:,} rows")

    def _selected_liquid_row(self) -> LiquidPriceRow | None:
        selection = self.liquid_tree.selection()
        if not selection:
            return None
        return self.liquid_row_by_iid.get(selection[0])

    def _select_liquid_price(self) -> None:
        row = self._selected_liquid_row()
        if row is None:
            return
        self.liquid_selected_key_var.set(f"{row.kind}: {row.key}")
        self.liquid_price_var.set(f"{row.price_per_liter:g}")
        base = "not defined in shipped data" if row.base_price_per_liter is None else f"{row.base_price_per_liter:g}"
        self.liquid_detail_var.set(
            f"{row.note} | primary={row.primary or '—'} | "
            f"base={base} | source={row.source} | "
            "price changes are stored in the dedicated Lua override file."
        )

    def _save_liquid_catalog(self) -> bool:
        if self.liquid_catalog is None:
            self.messagebox.showerror("Liquid pricing", "Liquid price data is not loaded.")
            return False
        try:
            path = save_liquid_overrides(self.liquid_catalog)
        except (LiquidPricingError, OSError) as error:
            self.messagebox.showerror("Save liquid pricing", str(error))
            return False
        self.liquid_status_var.set(
            f"Saved {self._liquid_override_count():,} override(s) to {path}. "
            "The next scan uses this file."
        )
        if hasattr(self, "log"):
            self._append_log(json.dumps({
                "event": "liquid_pricing_saved",
                "path": str(path),
                "overrides": self._liquid_override_count(),
                "note": "dedicated per-litre fluid content layer; category sandbox unchanged",
            }, sort_keys=True))
        return True

    def _liquid_override_count(self) -> int:
        if self.liquid_catalog is None:
            return 0
        return (
            len(self.liquid_catalog.override_exact)
            + len(self.liquid_catalog.override_families)
            + int(self.liquid_catalog.default_overridden)
        )

    def save_liquid_pricing(self) -> None:
        if self._save_liquid_catalog():
            self.status_var.set(
                "Liquid content overrides saved; use Apply & rescan to recalculate the master result."
            )

    def apply_liquid_price(self) -> None:
        row = self._selected_liquid_row()
        if row is None:
            self.messagebox.showinfo("Liquid pricing", "Select a liquid row first.")
            return
        try:
            self.liquid_catalog.set_price(row, float(self.liquid_price_var.get().strip()))
        except (LiquidPricingError, ValueError) as error:
            self.messagebox.showerror("Invalid liquid price", str(error))
            return
        self._refresh_liquid_tree()
        self.liquid_tree.selection_set(row.iid)
        self._select_liquid_price()
        if self._save_liquid_catalog():
            self.status_var.set(
                f"Saved {row.key} at ${row.price_per_liter:g}/litre; use Apply & rescan to evaluate it."
            )

    def reset_liquid_selected(self) -> None:
        row = self._selected_liquid_row()
        if row is None or self.liquid_catalog is None:
            return
        self.liquid_catalog.clear_price(row)
        self._refresh_liquid_tree()
        self.liquid_tree.selection_set(row.iid)
        self._select_liquid_price()
        self._save_liquid_catalog()
        self.status_var.set(f"Reset {row.key} to the shipped liquid-price anchor.")

    def reset_liquid_all(self) -> None:
        if self.liquid_catalog is None:
            return
        if not self.messagebox.askyesno(
            "Reset liquid pricing",
            "Remove all per-litre liquid overrides and restore the shipped anchors?",
        ):
            return
        self.liquid_catalog.clear_all()
        self._refresh_liquid_tree()
        self._save_liquid_catalog()
        self.status_var.set(
            "All liquid content overrides were reset; use Apply & rescan to recalculate prices."
        )

    def apply_liquid_pricing(self) -> None:
        if not self._save_liquid_catalog():
            return
        if self.busy:
            self.status_var.set(
                "Liquid overrides saved; finish the current scan before applying them."
            )
            return
        self.status_var.set("Liquid overrides saved; rescanning with the dedicated content prices…")
        self.scan()

