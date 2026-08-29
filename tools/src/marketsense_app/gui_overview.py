"""Overview charts and summary widgets for the MarketSense inspector."""

from __future__ import annotations

from typing import Any


class OverviewMixin:
    def _build_overview(self) -> None:
        frame = self.ttk.Frame(self.notebook, padding=8)
        frame.columnconfigure(0, weight=1)
        frame.columnconfigure(1, weight=1)
        frame.rowconfigure(1, weight=1)
        frame.rowconfigure(2, weight=1)
        self.notebook.add(frame, text="Overview")
        metrics = self.ttk.Frame(frame)
        metrics.grid(row=0, column=0, columnspan=2, sticky="ew", pady=(0, 8))
        self.metric_vars = {}
        for column, (name, label) in enumerate((
            ("items", "Evaluated items"),
            ("prices", "Price range"),
            ("categories", "Categories"),
            ("review", "Review flags"),
            ("errors", "Errors"),
            ("heuristic", "Heuristic gaps"),
        )):
            metrics.columnconfigure(column, weight=1)
            box = self.ttk.LabelFrame(metrics, text=label, padding=6)
            box.grid(row=0, column=column, sticky="ew", padx=3)
            variable = self.tk.StringVar(value="—")
            self.metric_vars[name] = variable
            self.ttk.Label(
                box, textvariable=variable,
                font=("TkDefaultFont", 14, "bold"),
            ).pack()
        self.category_chart = self.tk.Canvas(
            frame, height=250, background="white", highlightthickness=1
        )
        self.category_chart.grid(row=1, column=0, sticky="nsew", padx=(0, 4))
        self.price_chart = self.tk.Canvas(
            frame, height=250, background="white", highlightthickness=1
        )
        self.price_chart.grid(row=1, column=1, sticky="nsew", padx=(4, 0))
        self.category_chart.bind("<Configure>", lambda _event: self._redraw())
        self.price_chart.bind("<Configure>", lambda _event: self._redraw())
        categories = self.ttk.LabelFrame(
            frame, text="Category price summary", padding=4
        )
        categories.grid(
            row=2, column=0, columnspan=2, sticky="nsew", pady=(8, 0)
        )
        self.category_tree = self._tree(categories, [
            ("category", 170), ("count", 80), ("min", 80),
            ("median", 90), ("max", 80), ("unique", 80),
        ])

    def _redraw(self) -> None:
        if not self.summary:
            return
        self._bars(self.category_chart, "Categories", [
            (name, data["count"])
            for name, data in self.summary["categories"].items()
        ])
        self._bars(self.price_chart, "Price distribution", [
            (data["bucket"], data["count"])
            for data in self.summary["price_distribution"]
        ])

    def _bars(
        self,
        canvas: Any,
        title: str,
        values: list[tuple[str, int]],
    ) -> None:
        canvas.delete("all")
        width, height = max(canvas.winfo_width(), 280), max(canvas.winfo_height(), 180)
        canvas.create_text(
            10, 12, anchor="w", text=title,
            font=("TkDefaultFont", 10, "bold"),
        )
        if not values:
            canvas.create_text(width / 2, height / 2, text="No data")
            return
        left, top, right, bottom = 112, 32, width - 16, height - 18
        maximum = max(value for _, value in values) or 1
        slot = max(16, (bottom - top) / len(values))
        for index, (label, value) in enumerate(values):
            y = top + index * slot + slot / 2
            label = label if len(label) <= 16 else label[:15] + "…"
            canvas.create_text(left - 6, y, anchor="e", text=label)
            canvas.create_rectangle(
                left,
                y - slot * 0.3,
                left + (right - left) * value / maximum,
                y + slot * 0.3,
                fill="#4c78a8",
                outline="",
            )
            canvas.create_text(right + 2, y, anchor="e", text=str(value))
