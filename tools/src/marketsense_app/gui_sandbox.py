"""Sandbox pricing editor view for the MarketSense inspector."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .sandbox import (
    SandboxOption,
    SandboxSettingsError,
    load_sandbox_settings,
    normalize_settings,
    recommended_sandbox_settings,
    sandbox_definition_audit,
    save_sandbox_settings,
    setting_display,
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
        self.ttk.Button(
            toolbar, text="Audit definitions", command=self.refresh_sandbox_audit
        ).pack(side="left", padx=(12, 0))
        self.ttk.Button(
            toolbar, text="Reset recommended", command=self.reset_sandbox
        ).pack(
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
                "harness. Blank/inherit leaves the live default or Python JSON "
                "recommendation active. Saved settings: "
                f"{self.sandbox_path}"
            ),
        ).pack(fill="x", pady=(0, 6))
        self.sandbox_audit_var = self.tk.StringVar()
        self.ttk.Label(
            frame, textvariable=self.sandbox_audit_var
        ).pack(fill="x", pady=(0, 6))
        self.sandbox_tree = self._tree(frame, [
            ("key", 230), ("value", 105), ("default", 105),
            ("definition", 145), ("type", 80), ("page", 150),
            ("description", 440),
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
        self._set_sandbox_audit_label()
        self._refresh_sandbox_tree()

    def _refresh_sandbox_tree(self) -> None:
        if not hasattr(self, "sandbox_tree"):
            return
        self.sandbox_tree.delete(*self.sandbox_tree.get_children())
        query = self.sandbox_search_var.get().strip().casefold()
        for spec in self.sandbox_specs:
            haystack = " ".join((
                spec.key, spec.label, spec.tooltip, spec.page, spec.category_path,
                spec.definition_source,
            )).casefold()
            if query and query not in haystack:
                continue
            current = self.sandbox_overrides.get(spec.key)
            default = setting_display(None, spec)
            current_display = setting_display(current, spec)
            description = spec.label
            if spec.tooltip:
                description = f"{description} — {spec.tooltip}"
            definition = {
                "declared": "live",
                "declared+python-recommended": "live + Python",
                "python-recommended": "Python JSON",
            }.get(spec.definition_source, spec.definition_source)
            self.sandbox_tree.insert(
                "",
                "end",
                iid=f"sandbox:{spec.key}",
                values=(
                    spec.key,
                    current_display,
                    default,
                    definition,
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
        source_text = {
            "declared": "live sandbox-options.txt",
            "declared+python-recommended": (
                f"live declaration; Python recommended {spec.default:g}"
            ),
            "python-recommended": "Python JSON recommendation; live declaration missing",
        }.get(spec.definition_source, spec.definition_source)
        declared_text = (
            "not declared"
            if spec.declared_default is None
            else f"live default {spec.declared_default:g}"
        )
        self.sandbox_description_var.set(
            f"{spec.label} | {spec.option_type} | "
            f"{range_text or 'unbounded'} | {declared_text} | {source_text} | "
            "blank means inherit/default"
        )

    def _sandbox_audit_log(self) -> str:
        audit = self.sandbox_audit or {}
        warnings = audit.get("warnings") or []
        gaps = audit.get("recommendationGapCount", 0)
        stale = audit.get("staleGeneratedCount", 0)
        status = "WARNING" if audit.get("status") == "warning" else "OK"
        details = [
            {
                "kind": warning.get("kind"),
                "key": warning.get("key"),
                "message": warning.get("message"),
            }
            for warning in warnings[:12]
        ]
        return json.dumps({
            "event": "sandbox_definition_audit",
            "status": status,
            "declared": audit.get("declaredCount", 0),
            "pythonRecommendations": audit.get("recommendedCount", 0),
            "pythonOnlyMissingLiveDefinitions": gaps,
            "staleGeneratedOptions": stale,
            "warnings": len(warnings),
            "sample": details,
            "note": "Details are bounded; search Sandbox pricing or save JSON for full data.",
        }, sort_keys=True)

    def _set_sandbox_audit_label(self) -> None:
        audit = self.sandbox_audit or {}
        warnings = len(audit.get("warnings") or [])
        gaps = int(audit.get("recommendationGapCount", 0))
        stale = int(audit.get("staleGeneratedCount", 0))
        if warnings or gaps or stale:
            self.sandbox_audit_var.set(
                f"⚠ Sandbox definition audit: {warnings} value/source warning(s), "
                f"{gaps} Python-only category setting(s), {stale} stale generated option(s). "
                "Python-only rows are harness recommendations, not live PZ declarations."
            )
        else:
            self.sandbox_audit_var.set(
                "Sandbox definition audit: live declarations match the current pricing data."
            )

    def refresh_sandbox_audit(self) -> None:
        self.sandbox_audit = sandbox_definition_audit(self.version_var.get())
        self._set_sandbox_audit_label()
        self._append_log(self._sandbox_audit_log())
        self.status_var.set("Sandbox definition audit refreshed; see Diagnostics for a bounded summary.")

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
            self._persist_preferences()

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
        self._persist_preferences()
        self._refresh_sandbox_tree()
        self.status_var.set(
            f"Loaded {len(values)} sandbox override(s) from {path}."
        )

    def reset_sandbox(self) -> None:
        if not self.messagebox.askyesno(
            "Reset sandbox settings",
            "Replace local overrides with the Python JSON recommendations and rescan?",
        ):
            return
        self.sandbox_overrides = recommended_sandbox_settings(self.sandbox_specs)
        try:
            path = save_sandbox_settings(
                self.sandbox_path,
                self.sandbox_overrides,
                self.sandbox_specs,
            )
        except (OSError, SandboxSettingsError) as error:
            self.messagebox.showerror("Reset sandbox settings", str(error))
            return
        self.sandbox_path = path
        self._refresh_sandbox_tree()
        self.status_var.set(
            f"Recommended sandbox defaults saved ({len(self.sandbox_overrides)} values); applying with a rescan."
        )
        if self.busy:
            self.status_var.set(
                "Recommended sandbox defaults saved; finish the current scan before applying them."
            )
            return
        self.scan()
