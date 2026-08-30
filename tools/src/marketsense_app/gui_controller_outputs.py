"""GUI diagnostics, export, and cache actions."""

from __future__ import annotations

import json
import time
from pathlib import Path
from typing import Any

from .cache import clear_cache as clear_result_cache
from .config import DEFAULT_CACHE_DIR
from .heuristics import heuristic_gap_rows
from .reporting import write_csv, write_heuristic_gap_report, write_low_confidence_report
from .review import low_confidence_rows, review_count, review_row
from .gui_controller_support import MAX_DIAGNOSTIC_CHARS

class OutputControllerMixin:
    """Own one GUI controller concern behind the stable composite mixin."""

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
