"""Sandbox pricing editor view for the MarketSense inspector."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from .sandbox import (
    SandboxOption,
    SandboxSettingsError,
    load_sandbox_settings,
    normalize_settings,
    save_sandbox_settings,
)


class SandboxMixin:
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
        self.sandbox_search_var.trace_add(
            "write", lambda *_: self._refresh_sandbox_tree()
        )
        self.ttk.Button(toolbar, text="Save", command=self.save_sandbox).pack(
            side="left"
        )
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
        self.ttk.Label(
            toolbar, textvariable=self.sandbox_count_var
        ).pack(side="right")
        self.ttk.Label(
            frame,
            text=(
                "Overrides are applied as SandboxVars.MarketSense inside the Lua "
                "harness. Blank/inherit leaves the mod's declared sandbox default "
                "active. Saved settings: "
                f"{self.sandbox_path}"
            ),
        ).pack(fill="x", pady=(0, 6))
        self.sandbox_tree = self._tree(frame, [
            ("key", 230), ("value", 100), ("default", 110), ("type", 80),
            ("page", 150), ("description", 440),
        ])
        self.sandbox_tree.bind(
            "<<TreeviewSelect>>", lambda _event: self._select_sandbox_setting()
        )
        editor = self.ttk.LabelFrame(frame, text="Selected setting", padding=6)
        editor.pack(fill="x", pady=(8, 0))
        editor.columnconfigure(1, weight=1)
        self.sandbox_selected_key_var = self.tk.StringVar(value="—")
        self.sandbox_value_var = self.tk.StringVar()
        self.sandbox_description_var = self.tk.StringVar(
            value="Select a setting to edit it."
        )
        self.ttk.Label(editor, text="Key").grid(
            row=0, column=0, sticky="w", padx=(0, 6)
        )
        self.ttk.Label(
            editor, textvariable=self.sandbox_selected_key_var
        ).grid(row=0, column=1, sticky="w")
        self.ttk.Label(editor, text="Value").grid(
            row=1, column=0, sticky="w", padx=(0, 6)
        )
        self.sandbox_value_entry = self.ttk.Entry(
            editor, textvariable=self.sandbox_value_var, width=18
        )
        self.sandbox_value_entry.grid(row=1, column=1, sticky="w")
        self.sandbox_value_entry.bind(
            "<Return>", lambda _event: self.apply_sandbox_value()
        )
        self.ttk.Button(
            editor, text="Apply override", command=self.apply_sandbox_value
        ).grid(row=1, column=2, padx=(8, 0))
        self.ttk.Button(
            editor, text="Use default / inherit", command=self.clear_sandbox_value
        ).grid(row=1, column=3, padx=(4, 0))
        self.ttk.Label(editor, textvariable=self.sandbox_description_var).grid(
            row=2, column=0, columnspan=4, sticky="w", pady=(4, 0)
        )
        self._refresh_sandbox_tree()

    def _refresh_sandbox_tree(self) -> None:
        if not hasattr(self, "sandbox_tree"):
            return
        self.sandbox_tree.delete(*self.sandbox_tree.get_children())
        query = self.sandbox_search_var.get().strip().casefold()
        for spec in self.sandbox_specs:
            haystack = " ".join((
                spec.key, spec.label, spec.tooltip, spec.page
            )).casefold()
            if query and query not in haystack:
                continue
            current = self.sandbox_overrides.get(spec.key)
            default = "inherit" if spec.default is None else str(spec.default)
            description = spec.label
            if spec.tooltip:
                description = f"{description} — {spec.tooltip}"
            self.sandbox_tree.insert(
                "",
                "end",
                iid=f"sandbox:{spec.key}",
                values=(
                    spec.key,
                    "inherit" if current is None else str(current),
                    default,
                    spec.option_type,
                    spec.page,
                    description,
                ),
            )
        self.sandbox_count_var.set(
            f"{len(self.sandbox_overrides):,} overrides / "
            f"{len(self.sandbox_specs):,} settings"
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
            f"{spec.label} | {spec.option_type} | "
            f"{range_text or 'unbounded'} | blank means inherit/default"
        )

    def apply_sandbox_value(self) -> None:
        spec = self._selected_sandbox_spec()
        if spec is None:
            self.messagebox.showinfo(
                "Sandbox pricing", "Select a sandbox setting first."
            )
            return
        try:
            values = normalize_settings(
                {spec.key: self.sandbox_value_var.get()}, self.sandbox_specs
            )
        except SandboxSettingsError as error:
            self.messagebox.showerror("Invalid sandbox value", str(error))
            return
        if spec.key not in values:
            self.messagebox.showerror(
                "Invalid sandbox value", "Enter a finite numeric value."
            )
            return
        self.sandbox_overrides[spec.key] = values[spec.key]
        self._refresh_sandbox_tree()
        self.sandbox_tree.selection_set(f"sandbox:{spec.key}")
        self.status_var.set(
            f"Sandbox override applied for {spec.key}; scan to recalculate prices."
        )

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
            path = save_sandbox_settings(
                self.sandbox_path,
                self.sandbox_overrides,
                self.sandbox_specs,
            )
        except (OSError, SandboxSettingsError) as error:
            self.messagebox.showerror("Save sandbox settings", str(error))
            return
        self.sandbox_path = path
        self.status_var.set(
            f"Saved {len(self.sandbox_overrides)} sandbox override(s) to {path}."
        )

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
        self.status_var.set(
            f"Loaded {len(values)} sandbox override(s) from {path}."
        )

    def reset_sandbox(self) -> None:
        if not self.messagebox.askyesno(
            "Reset sandbox settings", "Remove all local sandbox overrides?"
        ):
            return
        self.sandbox_overrides = {}
        self._refresh_sandbox_tree()
        self.status_var.set(
            "Sandbox overrides cleared; the mod's defaults will be used."
        )
