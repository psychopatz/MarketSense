"""Application orchestration, settings, and output actions for the GUI."""

from __future__ import annotations

import json
import os
import threading
import time
import traceback
from pathlib import Path
from typing import Any

from .bridge import find_lua
from .cache import clear_cache as clear_result_cache
from .config import (
    DEFAULT_CACHE_DIR,
    DEFAULT_GAME_VERSION,
)
from .evaluation import ScanOptions, evaluate, load_cached_result
from .fixtures import self_test as run_self_test
from .heuristics import heuristic_gap_rows
from .preferences import load_preferences, normalize_preferences, save_preferences
from .reporting import write_csv, write_heuristic_gap_report, write_low_confidence_report
from .review import low_confidence_rows, review_count, review_row
from .gui_filters import filter_rows, view_summary
from .workshop import discover_mods
from .workshop_paths import default_roots, game_scripts_root


ALL_MODS_LABEL = "All"
MAX_DIAGNOSTIC_CHARS = 120_000


class ControllerMixin:
    """Own non-view GUI behavior while keeping the public GUI class stable."""

    def _build_mods(self) -> None:
        frame = self.ttk.Frame(self.notebook, padding=8)
        self.notebook.add(frame, text="Workshop mods")
        self.mod_tree = self._tree(frame, [
            ("id", 180), ("name", 260), ("workshop", 110),
            ("version", 110), ("items", 80), ("source", 90),
        ])

    def _browse_workshop(self) -> None:
        selected = self.filedialog.askdirectory(
            title="Select a Steam Workshop root"
        )
        if selected:
            self.workshop_var.set(selected)
            self._refresh_mod_filter_choices()
            self._persist_preferences()

    def _browse_game_root(self) -> None:
        selected = self.filedialog.askdirectory(
            title="Select Project Zomboid media/scripts or install root"
        )
        if selected:
            self.game_root_var.set(selected)
            self._game_root_is_auto = False
            self._persist_preferences()

    def _mark_game_root_explicit(self) -> None:
        if self._auto_game_root is None:
            return
        current = self.game_root_var.get().strip()
        self._game_root_is_auto = bool(
            current
            and Path(current).expanduser().resolve() == self._auto_game_root
        )

    def _workshop_roots(self) -> tuple[Path, ...]:
        raw_roots = self.workshop_var.get().strip()
        if not raw_roots:
            return tuple(default_roots())
        return tuple(
            Path(part.strip()).expanduser()
            for part in raw_roots.split(os.pathsep)
            if part.strip()
        )

    def _selected_mod_filters(self) -> tuple[str, ...]:
        return tuple(self.mod_filter_options.get(
            self.mod_filter_var.get(), self.initial_mod_filters
        ))

    def _mod_filter_label(self, mod: Any, duplicate: bool = False) -> str:
        name = str(mod.name or mod.mod_id or mod.root.name).strip()
        mod_id = str(mod.mod_id or mod.root.name).strip()
        label = f"{name} [{mod_id}]"
        if duplicate:
            label += f" ({mod.workshop_id})"
        return label

    def _refresh_mod_filter_choices(self) -> None:
        if not hasattr(self, "mod_filter_combo"):
            return
        current_label = self.mod_filter_var.get()
        current_terms = self.mod_filter_options.get(
            current_label, self.initial_mod_filters
        )
        try:
            mods = discover_mods(self._workshop_roots())
        except OSError:
            mods = []
        sorted_mods = sorted(
            mods,
            key=lambda mod: (
                str(mod.name or mod.mod_id).casefold(),
                str(mod.mod_id).casefold(),
                str(mod.workshop_id),
            ),
        )
        labels: dict[str, tuple[str, ...]] = {ALL_MODS_LABEL: ()}
        label_counts: dict[str, int] = {}
        for mod in sorted_mods:
            base_label = self._mod_filter_label(mod)
            duplicate_number = label_counts.get(base_label, 0)
            label_counts[base_label] = duplicate_number + 1
            label = (
                base_label
                if duplicate_number == 0
                else self._mod_filter_label(mod, duplicate=True)
            )
            suffix_number = duplicate_number + 1
            while label in labels:
                label = f"{base_label} ({mod.workshop_id}) #{suffix_number}"
                suffix_number += 1
            labels[label] = (str(mod.mod_id),)
        # A legacy CLI/preference filter may be a substring or multiple terms.
        # Preserve it as a visible custom choice until the user chooses a
        # discovered mod or All.
        selected = next(
            (label for label, terms in labels.items() if terms == current_terms),
            None,
        )
        if current_terms and selected is None:
            selected = f"Custom: {', '.join(current_terms)}"
            labels[selected] = tuple(current_terms)
        selected = selected or ALL_MODS_LABEL
        self.mod_filter_options = labels
        self.mod_filter_combo.configure(values=tuple(labels))
        self.mod_filter_var.set(selected)
        self.mod_filter_count_var.set(f"{len(mods):,} mods detected")

    def _on_mod_filter_selected(self) -> None:
        if not hasattr(self, "status_var"):
            return
        selection = self.mod_filter_var.get() or ALL_MODS_LABEL
        if not self.master_summary:
            if selection == ALL_MODS_LABEL:
                self.status_var.set(
                    "All detected Workshop mods selected; choose Scan all / cache once."
                )
            else:
                self.status_var.set(
                    f"{selection} selected; choose Scan all / cache once to build the cache."
                )
        else:
            self._apply_view_filters()

    def _preference_payload(self) -> dict[str, Any]:
        roots = [str(path) for path in self._workshop_roots()]
        try:
            max_items = max(0, int(self.max_items_var.get().strip() or 0))
        except ValueError:
            max_items = 0
        availability = {
            "Obtainable only": "obtainable",
            "All items": "all",
            "Uncertain only": "uncertain",
            "Excluded only": "excluded",
        }.get(self.availability_var.get(), "obtainable")
        return {
            "workshopRoots": roots,
            "gameRoot": "" if self._game_root_is_auto else self.game_root_var.get().strip(),
            "modFilters": ", ".join(self._selected_mod_filters()),
            "gameVersion": self.version_var.get().strip(),
            "maxItems": max_items,
            "skipVanilla": self.no_base_var.get(),
            "useCache": self.use_cache_var.get(),
            "refreshCache": False,
            "availability": availability,
        }

    def _persist_preferences(self) -> None:
        try:
            saved = save_preferences(
                self.preferences_path, self._preference_payload()
            )
        except OSError as error:
            self._write_log(f"Could not save inspector settings: {error}")
            return
        if saved:
            self.preferences = normalize_preferences(self._preference_payload())

    def _queue_save_preferences(self) -> None:
        if self._preferences_after_id is not None:
            try:
                self.root.after_cancel(self._preferences_after_id)
            except (RuntimeError, self.tk.TclError):
                pass
        self._preferences_after_id = self.root.after(
            350, self._persist_preferences
        )

    def _queue_mod_filter_refresh(self) -> None:
        if self._mod_filter_after_id is not None:
            try:
                self.root.after_cancel(self._mod_filter_after_id)
            except (RuntimeError, self.tk.TclError):
                pass
        self._mod_filter_after_id = self.root.after(
            350, self._refresh_mod_filter_choices
        )

    def _queue_view_filter_refresh(self) -> None:
        """Debounce max-item typing while keeping all other view changes instant."""

        if not self.master_summary:
            return
        if self._view_filter_after_id is not None:
            try:
                self.root.after_cancel(self._view_filter_after_id)
            except (RuntimeError, self.tk.TclError):
                pass
        self._view_filter_after_id = self.root.after(
            180, self._apply_view_filters
        )

    def _close(self) -> None:
        if self._preferences_after_id is not None:
            try:
                self.root.after_cancel(self._preferences_after_id)
            except (RuntimeError, self.tk.TclError):
                pass
        if self._mod_filter_after_id is not None:
            try:
                self.root.after_cancel(self._mod_filter_after_id)
            except (RuntimeError, self.tk.TclError):
                pass
        if self._view_filter_after_id is not None:
            try:
                self.root.after_cancel(self._view_filter_after_id)
            except (RuntimeError, self.tk.TclError):
                pass
        self._persist_preferences()
        self.root.destroy()

    def _restore_cached_result(self) -> None:
        if self.busy or not self.use_cache_var.get():
            if not self.use_cache_var.get():
                self.status_var.set(
                    "Cache disabled — choose Scan all / cache to evaluate."
                )
            return
        try:
            options = self._options()
        except ValueError as error:
            self.status_var.set(f"Saved settings need attention: {error}")
            return
        if options.refresh_cache:
            self.status_var.set(
                "Refresh enabled — choose Scan all / cache to rebuild the cache."
            )
            return
        self._start("load-cache", options)

    def _options(self) -> ScanOptions:
        confidence_threshold = self._confidence_threshold()
        game_root = self.game_root_var.get().strip()
        # The GUI owns one expensive master scan.  Its controls below are
        # deliberately unfiltered so changing Availability, Workshop mod,
        # vanilla visibility, or Max items only rebuilds the local view.
        return ScanOptions(
            workshop_roots=self._workshop_roots(),
            filters=(),
            game_version=self.version_var.get().strip() or DEFAULT_GAME_VERSION,
            game_root=(
                None
                if self._game_root_is_auto
                else Path(game_root).expanduser() if game_root else None
            ),
            no_base_game=False,
            max_items=0,
            cache_dir=self.args.cache_dir or DEFAULT_CACHE_DIR,
            use_cache=self.use_cache_var.get(),
            refresh_cache=self.refresh_cache_var.get(),
            confidence_threshold=confidence_threshold,
            sandbox_options=dict(self.sandbox_overrides),
            availability_filter="all",
        )

    def scan(self) -> None:
        try:
            self._refresh_mod_filter_choices()
            options = self._options()
        except ValueError as error:
            self.messagebox.showerror("Invalid settings", str(error))
            return
        self._persist_preferences()
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
        self._write_log(
            f"MarketSense {operation} started.\n"
            "Progress messages will appear here; large item data is only written "
            "through Save JSON/CSV."
        )
        self.status_var.set(
            "Loading exact cached result…"
            if operation == "load-cache"
            else "Running real MarketSense Lua evaluator…"
        )
        threading.Thread(
            target=self._worker,
            args=(operation, options),
            daemon=True,
        ).start()

    def _worker_progress(self, message: str) -> None:
        """Forward worker-thread phase messages to Tk's main thread."""

        self.root.after(
            0,
            lambda message=message: self._append_log(message),
        )

    def _worker(self, operation: str, options: ScanOptions | None) -> None:
        try:
            self._worker_progress("runtime: locating Lua interpreter")
            lua = find_lua(self.args.lua)
            self._worker_progress(f"runtime: using {lua}")
            if operation == "self-test":
                passed, checks = run_self_test(lua)
                self.root.after(
                    0, lambda: self._show_self_test(passed, checks)
                )
            elif operation == "load-cache":
                cached = (
                    load_cached_result(lua, options, self._worker_progress)
                    if options else None
                )
                if cached is None:
                    self.root.after(0, self._show_no_cached_result)
                else:
                    summary, rows = cached
                    self.root.after(
                        0, lambda: self._show_results(summary, rows)
                    )
            else:
                summary, rows = evaluate(lua, options, self._worker_progress)
                self.root.after(
                    0, lambda: self._show_results(summary, rows)
                )
        except Exception as error:  # surface diagnostics in the GUI, not stderr only
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
            f"{'PASS' if check['passed'] else 'FAIL'}: "
            f"{check['name']} — {check['detail']}"
            for check in checks
        ))
        self.status_var.set(
            f"Self-test {'passed' if passed else 'failed'} "
            f"({sum(c['passed'] for c in checks)}/{len(checks)} checks)."
        )

    def _show_no_cached_result(self) -> None:
        self._finish()
        self.status_var.set(
            "No exact cached result for these settings/paths — choose "
            "Scan all / cache to create one."
        )
        self._append_log(
            "No exact cached result was found. Scan all / cache will create a cache "
            "entry; future scans reuse it until inputs or settings change."
        )

    def _show_results(
        self, summary: dict[str, Any], rows: list[dict[str, Any]]
    ) -> None:
        self._finish()
        self.master_summary, self.master_rows = summary, rows
        self._apply_view_filters()
        self.save_button.configure(state="normal")
        self.csv_button.configure(state="normal")
        self._append_log(self._diagnostic_result_summary())

    def _diagnostic_result_summary(self) -> str:
        """Return a compact completion record instead of dumping every row."""

        master = self.master_summary or {}
        view = self.summary or {}
        cache = master.get("cache") or {}
        sample_fields = (
            "fullType", "workshopMod", "category", "primary", "price",
            "confidence", "detector", "resolver",
        )
        sample = [
            {field: row.get(field, "") for field in sample_fields}
            for row in self.rows[:12]
        ]
        return json.dumps({
            "event": "scan_complete",
            "masterRows": len(self.master_rows),
            "visibleRows": len(self.rows),
            "cache": cache,
            "view": {
                "mod": self.mod_filter_var.get() or ALL_MODS_LABEL,
                "availability": view.get("availability_filter", "obtainable"),
                "skipVanilla": self.no_base_var.get(),
                "maxShown": self.max_items_var.get().strip() or "0",
            },
            "summary": {
                "categories": len(view.get("categories") or {}),
                "errors": view.get("errors", 0),
                "reviewFlags": review_count(self.rows),
                "heuristicGapCandidates": (
                    (view.get("heuristic_coverage") or {}).get("candidate_count", 0)
                ),
                "priceRange": view.get("prices") or {},
            },
            "sampleRows": sample,
            "note": "Full rows are available through Save JSON/CSV.",
        }, indent=2, sort_keys=True)

    def _apply_view_filters(self) -> None:
        """Rebuild every GUI view from the in-memory master result."""

        self._view_filter_after_id = None
        if not self.master_summary:
            return
        try:
            max_items = max(0, int(self.max_items_var.get().strip() or 0))
        except ValueError:
            self.status_var.set("Max items must be a non-negative integer.")
            return
        self.rows = filter_rows(
            self.master_rows,
            availability=self.availability_var.get(),
            mod_filters=self._selected_mod_filters(),
            skip_vanilla=self.no_base_var.get(),
            max_items=max_items,
        )
        self.summary = view_summary(
            self.master_summary,
            self.rows,
            self.master_rows,
            self.availability_var.get(),
        )
        prices = self.summary["prices"]
        self.metric_vars["items"].set(str(self.summary["evaluated"]))
        self.metric_vars["prices"].set(
            f"{prices['min']:g} – {prices['max']:g}"
        )
        self.metric_vars["categories"].set(str(len(self.summary["categories"])))
        self.metric_vars["review"].set(str(review_count(self.rows)))
        self.metric_vars["errors"].set(str(self.summary["errors"]))
        self.metric_vars["heuristic"].set(str(
            (self.summary.get("heuristic_coverage") or {}).get("candidate_count", 0)
        ))
        self._fill_trees()
        self._redraw()
        self._set_view_status()

    def _set_view_status(self) -> None:
        summary = self.summary or {}
        master = self.master_summary or {}
        cache = master.get("cache") or {}
        cache_status = cache.get("status", "disabled")
        cache_path = cache.get("path", "not configured")
        master_count = len(self.master_rows)
        view_count = len(self.rows)
        selected_mod = self.mod_filter_var.get() or ALL_MODS_LABEL
        view_filter = summary.get("availability_filter", "obtainable")
        view_note = (
            f"View: {selected_mod}, {view_filter}, "
            f"{'no vanilla' if self.no_base_var.get() else 'vanilla included'}"
        )
        self.status_var.set(
            f"{'Cached master loaded' if cache_status == 'hit' else 'Master scan complete'}: "
            f"{view_count:,} shown / {master_count:,} scanned, "
            f"{master.get('workshop_mods', 0)} Workshop mods, "
            f"{summary.get('vanilla_items', 0):,} vanilla items, "
            f"{summary.get('workshop_items', 0):,} Workshop items, "
            f"{summary.get('errors', 0):,} errors, "
            f"{review_count(self.rows):,} review flags. "
            f"Heuristic-gap candidates: "
            f"{(summary.get('heuristic_coverage') or {}).get('candidate_count', 0):,}. "
            f"{view_note} ({summary.get('view_filtered_out', 0):,} hidden; "
            f"{(summary.get('availability_counts') or {}).get('uncertain', 0):,} "
            f"uncertain, "
            f"{(summary.get('availability_counts') or {}).get('excluded', 0):,} "
            f"excluded). Cache: {cache_status} ({cache_path}). "
            f"Version ceiling: {master.get('workshop_script_selection', '-')}. "
            "View filters are local; Scan all / cache is only needed after source/settings changes."
        )

    def _fill_trees(self) -> None:
        for tree in (
            self.category_tree if hasattr(self, "category_tree") else None,
            self.item_tree,
            self.review_tree,
            self.mod_tree,
        ):
            if tree:
                tree.delete(*tree.get_children())
        self.category_tree = getattr(self, "category_tree", None)
        if self.category_tree is None:
            return
        for category, data in self.summary["categories"].items():
            self.category_tree.insert("", "end", values=(
                category,
                data["count"],
                f"{data['min']:g}",
                f"{data['median']:g}",
                f"{data['max']:g}",
                data["unique"],
            ))
        self._refresh_item_tree()
        self._refresh_low_confidence()
        self._refresh_heuristic_gaps()
        flagged_rows = [
            row for row in self.rows if review_row(row)[0] != "OK"
        ]
        self.review_count_var.set(f"{len(flagged_rows):,} flagged rows")
        for row in sorted(
            flagged_rows, key=lambda item: str(item.get("fullType", ""))
        ):
            status, reason = review_row(row)
            self.review_tree.insert("", "end", values=(
                row.get("fullType", ""),
                status,
                reason,
                row.get("category") or "Unclassified",
                row.get("primary") or "Unclassified",
                row.get("confidence", ""),
                row.get("source", ""),
                row.get("workshopMod", ""),
                ", ".join(row.get("expandedTags") or row.get("tags") or []),
            ))
        counts = self.summary["mods_with_items"]
        for mod in self.summary["mods"]:
            self.mod_tree.insert("", "end", values=(
                mod["id"],
                mod["name"],
                mod["workshop_id"],
                mod["script_version"],
                counts.get(mod["id"], 0),
                mod["source"],
            ))

    def _write_log(self, text: str) -> None:
        if len(text) > MAX_DIAGNOSTIC_CHARS:
            text = (
                "[diagnostic output truncated; use Save JSON/CSV for complete data]\n"
                + text[-MAX_DIAGNOSTIC_CHARS:]
            )
        self.log.configure(state="normal")
        self.log.delete("1.0", "end")
        self.log.insert("end", text)
        self.log.configure(state="disabled")

    def _append_log(self, text: str) -> None:
        """Append bounded, timestamped diagnostic text on the Tk thread."""

        timestamp = time.strftime("%H:%M:%S")
        self.log.configure(state="normal")
        self.log.insert("end", f"[{timestamp}] {text.rstrip()}\n")
        content = self.log.get("1.0", "end-1c")
        if len(content) > MAX_DIAGNOSTIC_CHARS:
            self.log.delete("1.0", "end")
            self.log.insert(
                "end",
                "[older diagnostics truncated; use Save JSON/CSV for complete data]\n"
                + content[-MAX_DIAGNOSTIC_CHARS:],
            )
        self.log.see("end")
        self.log.configure(state="disabled")

    def save_json(self) -> None:
        if not self.summary:
            return
        path = self.filedialog.asksaveasfilename(
            title="Save MarketSense JSON",
            defaultextension=".json",
            filetypes=[("JSON", "*.json"), ("All files", "*.*")],
        )
        if path:
            Path(path).write_text(
                json.dumps(
                    {"summary": self.summary, "items": self.rows},
                    indent=2,
                ),
                encoding="utf-8",
            )

    def save_csv(self) -> None:
        if not self.rows:
            return
        path = self.filedialog.asksaveasfilename(
            title="Save MarketSense CSV",
            defaultextension=".csv",
            filetypes=[("CSV", "*.csv"), ("All files", "*.*")],
        )
        if path:
            write_csv(Path(path), self.rows)

    def save_low_confidence_jsonl(self) -> None:
        if not self.rows:
            self.messagebox.showinfo(
                "Low confidence", "Run a scan before exporting rows."
            )
            return
        try:
            threshold = self._confidence_threshold()
        except ValueError as error:
            self.messagebox.showerror("Invalid threshold", str(error))
            return
        path = self.filedialog.asksaveasfilename(
            title="Save low-confidence MarketSense rows",
            defaultextension=".jsonl",
            filetypes=[
                ("JSON Lines", "*.jsonl"),
                ("JSON", "*.json"),
                ("All files", "*.*"),
            ],
        )
        if path:
            output = write_low_confidence_report(
                Path(path), self.rows, threshold
            )
            self.status_var.set(
                f"Saved {len(low_confidence_rows(self.rows, threshold))} "
                f"low-confidence rows to {output}."
            )

    def save_low_confidence_csv(self) -> None:
        if not self.rows:
            self.messagebox.showinfo(
                "Low confidence", "Run a scan before exporting rows."
            )
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
            output = write_low_confidence_report(
                Path(path), self.rows, threshold
            )
            self.status_var.set(
                f"Saved {len(low_confidence_rows(self.rows, threshold))} "
                f"low-confidence rows to {output}."
            )

    def save_heuristic_gaps_json(self) -> None:
        if not self.rows:
            self.messagebox.showinfo(
                "Heuristic gaps", "Run a scan before exporting candidates."
            )
            return
        path = self.filedialog.asksaveasfilename(
            title="Save MarketSense heuristic-gap candidates",
            defaultextension=".json",
            filetypes=[
                ("JSON", "*.json"),
                ("JSON Lines", "*.jsonl"),
                ("All files", "*.*"),
            ],
        )
        if path:
            output = write_heuristic_gap_report(Path(path), self.rows)
            count = len(heuristic_gap_rows(self.rows))
            self.status_var.set(
                f"Saved {count:,} heuristic-gap candidates to {output}."
            )

    def save_heuristic_gaps_csv(self) -> None:
        if not self.rows:
            self.messagebox.showinfo(
                "Heuristic gaps", "Run a scan before exporting candidates."
            )
            return
        path = self.filedialog.asksaveasfilename(
            title="Save MarketSense heuristic-gap candidates",
            defaultextension=".csv",
            filetypes=[("CSV", "*.csv"), ("All files", "*.*")],
        )
        if path:
            output = write_heuristic_gap_report(Path(path), self.rows)
            count = len(heuristic_gap_rows(self.rows))
            self.status_var.set(
                f"Saved {count:,} heuristic-gap candidates to {output}."
            )

    def clear_cache(self) -> None:
        if self.busy:
            return
        if not self.messagebox.askyesno(
            "Clear cache", "Delete cached MarketSense scan results?"
        ):
            return
        removed = clear_result_cache(self.args.cache_dir or DEFAULT_CACHE_DIR)
        self.status_var.set(f"Cleared {removed} cached result(s).")
        self._write_log(
            f"Cleared {removed} cached result(s) from "
            f"{self.args.cache_dir or DEFAULT_CACHE_DIR}"
        )

    def _show_error(self, details: str) -> None:
        self._finish()
        self.status_var.set(
            "Operation failed — see Diagnostics for the traceback."
        )
        self._append_log("ERROR\n" + details)
