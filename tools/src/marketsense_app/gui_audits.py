"""Classification review and heuristic-gap views for the inspector."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .heuristics import (
    compact_heuristic_gap,
    heuristic_gap,
    heuristic_gap_rows,
    heuristic_kind_label,
)
from .config import DEFAULT_RUNTIME_ITEMS_DIR
from .review import low_confidence_rows, review_count, review_row, searchable_text
from .runtime_comparison import compare_harness_to_runtime


class AuditMixin:
    def _build_review(self) -> None:
        frame = self.ttk.Frame(self.notebook, padding=8)
        self.notebook.add(frame, text="Classification review")
        self.ttk.Label(
            frame,
            text=(
                "Rows below need a human check. Inspect the reason, source, tags, and "
                "definition before changing a classifier rule."
            ),
        ).pack(fill="x", pady=(0, 6))
        self.review_count_var = self.tk.StringVar(value="0 flagged rows")
        self.ttk.Label(
            frame, textvariable=self.review_count_var
        ).pack(anchor="w", pady=(0, 4))
        self.review_tree = self._tree(frame, [
            ("item", 220), ("status", 80), ("reason", 360),
            ("category", 110), ("primary", 180), ("confidence", 90),
            ("source", 180), ("mod", 150), ("tags", 300),
        ])

    def _build_runtime_verification(self) -> None:
        frame = self.ttk.Frame(self.notebook, padding=8)
        self.notebook.add(frame, text="Verify")
        toolbar = self.ttk.Frame(frame)
        toolbar.pack(fill="x", pady=(0, 6))
        self.ttk.Label(toolbar, text="Runtime DT_Items").pack(side="left")
        self.runtime_items_dir_var = self.tk.StringVar(
            value=str(DEFAULT_RUNTIME_ITEMS_DIR)
        )
        self.ttk.Entry(
            toolbar, textvariable=self.runtime_items_dir_var, width=64
        ).pack(side="left", padx=(6, 4), fill="x", expand=True)
        self.ttk.Button(
            toolbar, text="Browse…", command=self._browse_runtime_items
        ).pack(side="left", padx=(0, 4))
        self.ttk.Button(
            toolbar, text="Compare", command=self._compare_runtime_items
        ).pack(side="left", padx=(0, 4))
        self.ttk.Button(
            toolbar, text="Save JSON…", command=self._save_runtime_comparison_json
        ).pack(side="left")
        self.runtime_verify_status_var = self.tk.StringVar(
            value="Run a complete harness scan, then compare it with the PZ DT_Items output."
        )
        self.ttk.Label(
            frame, textvariable=self.runtime_verify_status_var
        ).pack(anchor="w", pady=(0, 4))
        self.ttk.Label(
            frame,
            text=(
                "This compares the runtime cache consumed by DynamicTrading with "
                "the offline harness at the cache stage: item membership, tags, "
                "taxonomy, generated base price, and generated stock."
            ),
        ).pack(fill="x", pady=(0, 6))
        self.runtime_verify_difference_by_iid: dict[str, dict[str, Any]] = {}
        self.runtime_verify_tree = self._tree(frame, [
            ("status", 140), ("item", 280), ("fields", 260), ("location", 420),
        ])
        self.runtime_verify_tree.bind(
            "<<TreeviewSelect>>", lambda _event: self._show_runtime_difference()
        )
        self.ttk.Label(
            frame, text="Selected comparison detail"
        ).pack(anchor="w", pady=(6, 2))
        self.runtime_verify_detail = self.scrolledtext.ScrolledText(
            frame, height=9, wrap="none", state="disabled"
        )
        self.runtime_verify_detail.pack(fill="both", expand=False)
        self.runtime_verification: dict[str, Any] | None = None

    def _browse_runtime_items(self) -> None:
        selected = self.filedialog.askdirectory(
            title="Select the PZ DT_Items directory",
            initialdir=str(Path(self.runtime_items_dir_var.get()).expanduser().parent),
        )
        if selected:
            self.runtime_items_dir_var.set(selected)

    def _compare_runtime_items(self) -> None:
        if not self.master_rows:
            self.messagebox.showinfo(
                "Runtime verification",
                "Run Scan all / cache before comparing runtime DT_Items output.",
            )
            return
        try:
            result = compare_harness_to_runtime(
                self.master_rows,
                Path(self.runtime_items_dir_var.get().strip()),
            )
        except (OSError, ValueError) as error:
            self.messagebox.showerror("Runtime verification", str(error))
            return

        self.runtime_verification = result
        self.runtime_verify_tree.delete(
            *self.runtime_verify_tree.get_children()
        )
        self.runtime_verify_difference_by_iid.clear()
        for difference in result.get("differences") or []:
            status = str(difference.get("status") or "difference")
            fields = ", ".join(difference.get("fields") or [])
            location = ""
            actual = difference.get("actual")
            if isinstance(actual, dict):
                location = str(actual.get("path") or "")
            item_id = self.runtime_verify_tree.insert(
                "", "end", values=(
                    status,
                    difference.get("fullType", ""),
                    fields,
                    location,
                )
            )
            self.runtime_verify_difference_by_iid[item_id] = difference

        parse_errors = int(
            (result.get("runtime") or {}).get("parseErrorCount", 0)
        )
        unindexed_files = int(
            ((result.get("runtime") or {}).get("index") or {}).get(
                "unindexedFileCount", 0
            )
        )
        unavailable = ", ".join(
            f"{field} ({count:,})"
            for field, count in (result.get("unavailableFields") or {}).items()
        )
        status = str(result.get("status") or "unknown").upper()
        message = (
            f"{status}: {result.get('matches', 0):,}/{result.get('compared', 0):,} "
            f"compared items match; {result.get('differenceCount', 0):,} differences; "
            f"runtime {result.get('runtimeItems', 0):,} items"
        )
        if parse_errors:
            message += f"; {parse_errors:,} parse errors"
        if unindexed_files:
            message += f"; {unindexed_files:,} unindexed runtime files"
        if unavailable:
            message += f"; unavailable harness fields: {unavailable}"
        self.runtime_verify_status_var.set(message)
        self._show_runtime_difference()

    def _show_runtime_difference(self) -> None:
        selection = self.runtime_verify_tree.selection()
        difference = (
            self.runtime_verify_difference_by_iid.get(selection[0])
            if selection else None
        )
        detail = (
            json.dumps(difference, indent=2, sort_keys=True)
            if difference else
            "Select a comparison difference to inspect expected and runtime values."
        )
        self.runtime_verify_detail.configure(state="normal")
        self.runtime_verify_detail.delete("1.0", "end")
        self.runtime_verify_detail.insert("end", detail)
        self.runtime_verify_detail.configure(state="disabled")

    def _save_runtime_comparison_json(self) -> None:
        if not self.runtime_verification:
            self.messagebox.showinfo(
                "Runtime verification", "Run Compare before saving its report."
            )
            return
        path = self.filedialog.asksaveasfilename(
            title="Save MarketSense runtime comparison",
            defaultextension=".json",
            filetypes=[("JSON", "*.json"), ("All files", "*.*")],
        )
        if path:
            Path(path).write_text(
                json.dumps(self.runtime_verification, indent=2, sort_keys=True),
                encoding="utf-8",
            )
            self.runtime_verify_status_var.set(
                f"Saved runtime comparison to {Path(path).resolve()}"
            )

    def _clear_runtime_verification(self) -> None:
        self.runtime_verification = None
        if not hasattr(self, "runtime_verify_tree"):
            return
        self.runtime_verify_tree.delete(*self.runtime_verify_tree.get_children())
        self.runtime_verify_difference_by_iid.clear()
        self.runtime_verify_status_var.set(
            "Scan changed; run Compare again against the current DT_Items output."
        )
        self._show_runtime_difference()

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
        threshold_entry.bind(
            "<Return>", lambda _event: self._refresh_low_confidence()
        )
        threshold_entry.bind(
            "<FocusOut>", lambda _event: self._refresh_low_confidence()
        )
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
        self.ttk.Label(
            toolbar, textvariable=self.low_confidence_count_var
        ).pack(side="right")
        self.ttk.Label(
            frame,
            text=(
                "This is the complete sorted candidate list for heuristic review. "
                "Exports include the item definition, runtime context, detector "
                "evidence, and price audit so the Lua rules can be updated from "
                "evidence."
            ),
        ).pack(fill="x", pady=(0, 6))
        self.low_confidence_tree = self._tree(frame, [
            ("item", 240), ("confidence", 90), ("category", 110),
            ("subcategory", 140), ("primary", 220), ("detector", 140),
            ("resolver", 160), ("mod", 160), ("reason", 380),
        ])

    def _build_heuristic_gaps(self) -> None:
        frame = self.ttk.Frame(self.notebook, padding=8)
        self.notebook.add(frame, text="Heuristic gaps")
        toolbar = self.ttk.Frame(frame)
        toolbar.pack(fill="x", pady=(0, 6))
        self.heuristic_search_var = self.tk.StringVar()
        self.ttk.Label(toolbar, text="Find item or evidence").pack(side="left")
        self.ttk.Entry(toolbar, textvariable=self.heuristic_search_var, width=32).pack(
            side="left", padx=(6, 10)
        )
        self.heuristic_search_var.trace_add(
            "write", lambda *_: self._refresh_heuristic_gaps()
        )
        self.ttk.Label(toolbar, text="Signal").pack(side="left")
        self.heuristic_kind_var = self.tk.StringVar(value="All")
        self.heuristic_kind_combo = self.ttk.Combobox(
            toolbar,
            textvariable=self.heuristic_kind_var,
            values=("All", "Missing", "Fallback", "Generic", "Root-only"),
            state="readonly",
            width=12,
        )
        self.heuristic_kind_combo.pack(side="left", padx=(6, 10))
        self.heuristic_kind_combo.bind(
            "<<ComboboxSelected>>",
            lambda _event: self._refresh_heuristic_gaps(),
        )
        self.ttk.Button(
            toolbar, text="Save JSON…", command=self.save_heuristic_gaps_json
        ).pack(side="left")
        self.ttk.Button(
            toolbar, text="Save CSV…", command=self.save_heuristic_gaps_csv
        ).pack(side="left", padx=(4, 0))
        self.heuristic_count_var = self.tk.StringVar(value="0 candidates")
        self.ttk.Label(
            toolbar, textvariable=self.heuristic_count_var
        ).pack(side="right")
        self.ttk.Label(
            frame,
            text=(
                "These are compact triage candidates: missing, broad, or root-only "
                "classification evidence. They are not confirmed false positives. "
                "Select a row to inspect the complete runtime evidence."
            ),
        ).pack(fill="x", pady=(0, 6))
        self.heuristic_gap_row_by_iid: dict[str, dict[str, Any]] = {}
        self.heuristic_gap_tree = self._tree(frame, [
            ("bucket", 150), ("signal", 100), ("category path", 270),
            ("confidence", 90), ("detector", 140), ("resolver", 160),
            ("mod", 160), ("reason", 460),
        ], hierarchical=True)
        self.heuristic_gap_tree.bind(
            "<<TreeviewSelect>>", lambda _event: self._show_heuristic_details()
        )
        self.ttk.Label(
            frame, text="Selected item runtime evidence"
        ).pack(anchor="w", pady=(6, 2))
        self.heuristic_detail = self.scrolledtext.ScrolledText(
            frame, height=9, wrap="none", state="disabled"
        )
        self.heuristic_detail.pack(fill="both", expand=False)

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
            hierarchy = (
                row.get("hierarchy")
                if isinstance(row.get("hierarchy"), dict)
                else {}
            )
            self.low_confidence_tree.insert("", "end", values=(
                row.get("fullType", ""),
                row.get("confidence", ""),
                row.get("category") or hierarchy.get("root", ""),
                row.get("subcategory") or hierarchy.get("subcategory", ""),
                row.get("primary") or "",
                row.get("detector", ""),
                row.get("resolver", ""),
                row.get("workshopMod", ""),
                reason,
            ))
        self.low_confidence_count_var.set(
            f"{len(selected):,} rows below {threshold:.2f}"
        )

    def _refresh_heuristic_gaps(self) -> None:
        if not hasattr(self, "heuristic_gap_tree"):
            return
        self.heuristic_gap_tree.delete(*self.heuristic_gap_tree.get_children())
        self.heuristic_gap_row_by_iid.clear()
        query = self.heuristic_search_var.get().strip().casefold()
        kind_filter = self.heuristic_kind_var.get().replace("-", "_").casefold()
        selected = []
        for row in heuristic_gap_rows(self.rows):
            gap = heuristic_gap(row)
            if gap is None:
                continue
            if kind_filter != "all" and gap.get("kind") != kind_filter:
                continue
            if query and query not in searchable_text(row):
                continue
            selected.append((row, gap))
        for row, gap in selected:
            item_id = self.heuristic_gap_tree.insert(
                "",
                "end",
                text=row.get("fullType") or "<unknown>",
                values=(
                    gap.get("bucket", ""),
                    heuristic_kind_label(gap.get("kind")),
                    gap.get("categoryPath", ""),
                    row.get("confidence", ""),
                    row.get("detector", ""),
                    row.get("resolver", ""),
                    row.get("workshopMod", ""),
                    gap.get("reason", ""),
                ),
            )
            self.heuristic_gap_row_by_iid[item_id] = row
        total = len(heuristic_gap_rows(self.rows))
        self.heuristic_count_var.set(
            f"{len(selected):,} shown / {total:,} candidates"
        )

    def _show_heuristic_details(self) -> None:
        selection = self.heuristic_gap_tree.selection()
        row = (
            self.heuristic_gap_row_by_iid.get(selection[0])
            if selection
            else None
        )
        if row is None:
            detail = "Select a heuristic-gap row to inspect its runtime evidence."
        else:
            detail_data = dict(row)
            detail_data["heuristicGap"] = compact_heuristic_gap(row)
            status, reason = review_row(row)
            detail_data["review"] = {"status": status, "reason": reason}
            detail = json.dumps(detail_data, indent=2, sort_keys=True)
        self.heuristic_detail.configure(state="normal")
        self.heuristic_detail.delete("1.0", "end")
        self.heuristic_detail.insert("end", detail)
        self.heuristic_detail.configure(state="disabled")

    def _confidence_threshold(self) -> float:
        value = float(self.confidence_threshold_var.get().strip())
        if not 0.0 <= value <= 1.0:
            raise ValueError("confidence threshold must be between 0 and 1")
        return value
