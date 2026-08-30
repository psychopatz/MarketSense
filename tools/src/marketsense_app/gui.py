"""Tk entry point for the modular MarketSense desktop inspector."""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any

from .gui_controller import ALL_MODS_LABEL, ControllerMixin
from .gui_audits import AuditMixin
from .gui_items import ItemsMixin
from .gui_overview import OverviewMixin
from .gui_sandbox import SandboxMixin
from .gui_state import GuiState
from .gui_view import initialize_view
from .gui_widgets import WidgetMixin


class MarketSenseGui(
    WidgetMixin,
    OverviewMixin,
    ItemsMixin,
    AuditMixin,
    SandboxMixin,
    ControllerMixin,
):
    """Compose the inspector from focused view and controller components."""

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
        self.state = GuiState()
        initialize_view(
            self,
            root,
            tk,
            ttk,
            scrolledtext,
            filedialog,
            messagebox,
            simpledialog,
            args,
        )

    # Compatibility properties for existing view/controller mixins. The
    # mutable scan model remains owned by GuiState while the widget attributes
    # continue to be owned by the composed GUI view.
    @property
    def busy(self) -> bool:
        return self.state.busy

    @busy.setter
    def busy(self, value: bool) -> None:
        self.state.busy = bool(value)

    @property
    def summary(self) -> dict[str, Any] | None:
        return self.state.summary

    @summary.setter
    def summary(self, value: dict[str, Any] | None) -> None:
        self.state.summary = value

    @property
    def rows(self) -> list[dict[str, Any]]:
        return self.state.rows

    @rows.setter
    def rows(self, value: list[dict[str, Any]]) -> None:
        self.state.rows = value

    @property
    def master_summary(self) -> dict[str, Any] | None:
        return self.state.master_summary

    @master_summary.setter
    def master_summary(self, value: dict[str, Any] | None) -> None:
        self.state.master_summary = value

    @property
    def master_rows(self) -> list[dict[str, Any]]:
        return self.state.master_rows

    @master_rows.setter
    def master_rows(self, value: list[dict[str, Any]]) -> None:
        self.state.master_rows = value

    @property
    def preferences_path(self) -> Path | None:
        return self.state.preferences_path

    @preferences_path.setter
    def preferences_path(self, value: Path | None) -> None:
        self.state.preferences_path = value

    @property
    def preferences(self) -> dict[str, Any]:
        return self.state.preferences

    @preferences.setter
    def preferences(self, value: dict[str, Any]) -> None:
        self.state.preferences = value

    @property
    def _preferences_after_id(self) -> str | None:
        return self.state.preferences_after_id

    @_preferences_after_id.setter
    def _preferences_after_id(self, value: str | None) -> None:
        self.state.preferences_after_id = value

    @property
    def _mod_filter_after_id(self) -> str | None:
        return self.state.mod_filter_after_id

    @_mod_filter_after_id.setter
    def _mod_filter_after_id(self, value: str | None) -> None:
        self.state.mod_filter_after_id = value

    @property
    def _view_filter_after_id(self) -> str | None:
        return self.state.view_filter_after_id

    @_view_filter_after_id.setter
    def _view_filter_after_id(self, value: str | None) -> None:
        self.state.view_filter_after_id = value


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
