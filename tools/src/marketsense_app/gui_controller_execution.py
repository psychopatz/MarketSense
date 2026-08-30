"""GUI operation lifecycle and background execution behavior."""

from __future__ import annotations

import json
import threading
import traceback
from typing import Any

from .bridge import find_lua
from .evaluation import ScanOptions, evaluate, load_cached_result
from .testing import self_test as run_self_test

class ExecutionControllerMixin:
    """Own one GUI controller concern behind the stable composite mixin."""

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
            else "Running real MarketSense Lua evaluator for the selected scope…"
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
            "No exact cached result for this scope/settings — choose "
            "Scan selected scope / cache to create one."
        )
        self._append_log(
            "No exact cached result was found. Scan selected scope / cache will "
            "create an entry; future scans reuse it until inputs or settings change."
        )

    def _show_results(
        self, summary: dict[str, Any], rows: list[dict[str, Any]]
    ) -> None:
        self._finish()
        self.master_summary, self.master_rows = summary, rows
        self._sync_runtime_rules()
        self._clear_runtime_verification()
        self._apply_view_filters()
        self.save_button.configure(state="normal")
        self.csv_button.configure(state="normal")
        self._append_log(self._diagnostic_result_summary())
