"""Reusable Tk widget construction helpers for the MarketSense inspector."""

from __future__ import annotations

from typing import Any


class WidgetMixin:
    """Shared layout primitives used by the inspector view mixins."""

    def _entry(
        self,
        parent: Any,
        row: int,
        label_column: int,
        label: str,
        variable: Any,
        width: int,
    ) -> None:
        self.ttk.Label(parent, text=label).grid(
            row=row, column=label_column, sticky="w", padx=(0, 6), pady=2
        )
        self.ttk.Entry(parent, textvariable=variable, width=width).grid(
            row=row, column=label_column + 1, sticky="ew", pady=2
        )

    def _tree(
        self,
        parent: Any,
        columns: list[tuple[str, int]],
        hierarchical: bool = False,
    ) -> Any:
        frame = self.ttk.Frame(parent)
        frame.pack(fill="both", expand=True)
        tree = self.ttk.Treeview(
            frame,
            columns=[name for name, _ in columns],
            show="tree headings" if hierarchical else "headings",
        )
        y_scrollbar = self.ttk.Scrollbar(
            frame, orient="vertical", command=tree.yview
        )
        x_scrollbar = self.ttk.Scrollbar(
            frame, orient="horizontal", command=tree.xview
        )
        tree.configure(
            yscrollcommand=y_scrollbar.set,
            xscrollcommand=x_scrollbar.set,
        )
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
