"""Overview charts and summary widgets for the MarketSense inspector."""

from __future__ import annotations

import json
from typing import Any

from .gui_filters import is_vanilla_row, row_mod_id
from .review import searchable_text


_AVAILABILITY_OVERVIEW_FILTERS = (
    "All", "Obtainable", "Uncertain", "Excluded",
    "Changed", "Blacklisted", "Whitelisted", "Overridden",
)


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

    def _build_availability_overview(self) -> None:
        frame = self.ttk.Frame(self.notebook, padding=8)
        frame.columnconfigure(0, weight=1)
        frame.rowconfigure(2, weight=1)
        self.notebook.add(frame, text="Availability overview")

        toolbar = self.ttk.Frame(frame)
        toolbar.grid(row=0, column=0, sticky="ew", pady=(0, 6))
        self.ttk.Label(toolbar, text="Find item or evidence").pack(side="left")
        self.availability_overview_search_var = self.tk.StringVar()
        self.ttk.Entry(
            toolbar,
            textvariable=self.availability_overview_search_var,
            width=32,
        ).pack(side="left", padx=(6, 12))
        self.availability_overview_search_var.trace_add(
            "write", lambda *_: self._refresh_availability_overview()
        )
        self.ttk.Label(toolbar, text="Status").pack(side="left")
        self.availability_overview_filter_var = self.tk.StringVar(value="All")
        self.availability_overview_filter = self.ttk.Combobox(
            toolbar,
            textvariable=self.availability_overview_filter_var,
            values=_AVAILABILITY_OVERVIEW_FILTERS,
            state="readonly",
            width=14,
        )
        self.availability_overview_filter.pack(side="left", padx=(6, 12))
        self.availability_overview_filter.bind(
            "<<ComboboxSelected>>",
            lambda _event: self._refresh_availability_overview(),
        )
        self.availability_overview_count_var = self.tk.StringVar(value="0 items")
        self.ttk.Label(
            toolbar, textvariable=self.availability_overview_count_var
        ).pack(side="right")

        self.availability_overview_metric_vars = {
            status: self.tk.StringVar(value="0")
            for status in ("obtainable", "uncertain", "excluded", "changed")
        }
        metrics = self.ttk.Frame(frame)
        metrics.grid(row=1, column=0, sticky="ew", pady=(0, 6))
        for column, status in enumerate(
            ("obtainable", "uncertain", "excluded", "changed")
        ):
            metrics.columnconfigure(column, weight=1)
            box = self.ttk.LabelFrame(
                metrics, text=status.title(), padding=(8, 3)
            )
            box.grid(row=0, column=column, sticky="ew", padx=3)
            self.ttk.Label(
                box,
                textvariable=self.availability_overview_metric_vars[status],
                font=("TkDefaultFont", 12, "bold"),
            ).pack()

        self.availability_overview_row_by_iid: dict[str, dict[str, Any]] = {}
        tree_frame = self.ttk.Frame(frame)
        tree_frame.grid(row=2, column=0, sticky="nsew")
        self.availability_overview_tree = self._tree(tree_frame, [
            ("item", 280),
            ("status", 110),
            ("rules", 180),
            ("category", 130),
            ("primary", 190),
            ("channels", 240),
            ("reason", 360),
            ("mod", 180),
        ])
        self.availability_overview_tree.tag_configure(
            "availability-obtainable", foreground="#087f5b"
        )
        self.availability_overview_tree.tag_configure(
            "availability-uncertain", foreground="#8a5a00"
        )
        self.availability_overview_tree.tag_configure(
            "availability-excluded", foreground="#b42318"
        )
        self.availability_overview_tree.tag_configure(
            "availability-blacklisted", foreground="#b42318"
        )
        self.availability_overview_tree.tag_configure(
            "availability-whitelisted", foreground="#087f5b"
        )
        self.availability_overview_tree.tag_configure(
            "availability-overridden", foreground="#8a5a00"
        )
        self.availability_overview_tree.bind(
            "<<TreeviewSelect>>", lambda _event: self._show_availability_detail()
        )
        self.ttk.Label(
            frame, text="Selected availability evidence"
        ).grid(row=3, column=0, sticky="w", pady=(6, 2))
        self.availability_overview_detail = self.scrolledtext.ScrolledText(
            frame, height=8, wrap="none", state="disabled"
        )
        self.availability_overview_detail.grid(row=4, column=0, sticky="ew")

    def _availability_overview_source_rows(self) -> list[dict[str, Any]]:
        terms = tuple(
            self._selected_mod_filters()
            if hasattr(self, "_selected_mod_filters")
            else ()
        )
        visible: list[dict[str, Any]] = []
        for row in getattr(self, "master_rows", []):
            if terms:
                mod_id = row_mod_id(row).casefold()
                mod_name = str(row.get("workshopName") or "").casefold()
                if not any(
                    str(term).casefold() == mod_id
                    or str(term).casefold() in mod_id
                    or str(term).casefold() in mod_name
                    for term in terms
                    if str(term).strip()
                ):
                    continue
            elif getattr(self, "no_base_var", None) is not None and self.no_base_var.get():
                if is_vanilla_row(row):
                    continue
            visible.append(row)
        return visible

    def _availability_rule_state(self, row: dict[str, Any]) -> dict[str, Any]:
        state = getattr(self, "item_rule_state_by_id", {}).get(
            str(row.get("fullType") or "")
        )
        if not isinstance(state, dict):
            return {"membership": None, "override": {}}
        return {
            "membership": state.get("membership"),
            "override": dict(state.get("override") or {}),
        }

    @staticmethod
    def _availability_rule_label(state: dict[str, Any]) -> str:
        labels = []
        membership = state.get("membership")
        if membership:
            labels.append({
                "blacklist": "Blacklisted",
                "whitelist": "Whitelisted",
            }.get(membership, str(membership).title()))
        if state.get("override"):
            labels.append("Overridden")
        return ", ".join(labels)

    @staticmethod
    def _availability_filter_matches(
        selected: str, status: str, state: dict[str, Any]
    ) -> bool:
        membership = state.get("membership")
        overridden = bool(state.get("override"))
        if selected == "all":
            return True
        if selected in {"obtainable", "uncertain", "excluded"}:
            return status == selected
        if selected == "changed":
            return bool(membership or overridden)
        if selected == "blacklisted":
            return membership == "blacklist"
        if selected == "whitelisted":
            return membership == "whitelist"
        if selected == "overridden":
            return overridden
        return True

    def _show_availability_detail(self) -> None:
        selection = self.availability_overview_tree.selection()
        row = (
            self.availability_overview_row_by_iid.get(selection[0])
            if selection else None
        )
        detail = (
            json.dumps(row, indent=2, sort_keys=True)
            if row is not None
            else "Select an item to inspect its availability evidence."
        )
        self.availability_overview_detail.configure(state="normal")
        self.availability_overview_detail.delete("1.0", "end")
        self.availability_overview_detail.insert("end", detail)
        self.availability_overview_detail.configure(state="disabled")

    def _refresh_availability_overview(self) -> None:
        if not hasattr(self, "availability_overview_tree"):
            return
        source_rows = self._availability_overview_source_rows()
        counts = {
            status: 0
            for status in ("obtainable", "uncertain", "excluded", "changed")
        }
        for row in source_rows:
            availability = row.get("availability")
            status = (
                str(availability.get("status") or "uncertain").casefold()
                if isinstance(availability, dict)
                else "uncertain"
            )
            counts[status] = counts.get(status, 0) + 1
            state = self._availability_rule_state(row)
            if state.get("membership") or state.get("override"):
                counts["changed"] += 1
        for status, variable in self.availability_overview_metric_vars.items():
            variable.set(f"{counts.get(status, 0):,}")

        selected = str(
            self.availability_overview_filter_var.get() or "All"
        ).strip().casefold()
        query = self.availability_overview_search_var.get().strip().casefold()
        rows = []
        for row in source_rows:
            availability = row.get("availability")
            status = (
                str(availability.get("status") or "uncertain").casefold()
                if isinstance(availability, dict)
                else "uncertain"
            )
            state = self._availability_rule_state(row)
            if not self._availability_filter_matches(selected, status, state):
                continue
            if query:
                rule_label = self._availability_rule_label(state).casefold()
                if query not in searchable_text(row) and query not in rule_label:
                    continue
            rows.append((status, row))

        self.availability_overview_tree.delete(
            *self.availability_overview_tree.get_children()
        )
        self.availability_overview_row_by_iid.clear()
        for status, row in sorted(
            rows,
            key=lambda entry: (entry[0], str(entry[1].get("fullType") or "")),
        ):
            state = self._availability_rule_state(row)
            availability = row.get("availability")
            availability = availability if isinstance(availability, dict) else {}
            channels = availability.get("channelLabels") or availability.get("channels") or []
            if isinstance(channels, (list, tuple)):
                channels = ", ".join(str(channel) for channel in channels)
            rule_label = self._availability_rule_label(state)
            membership = state.get("membership")
            prefix = ""
            if membership == "blacklist":
                prefix = "(Blacklisted) "
            elif membership == "whitelist":
                prefix = "(Whitelisted) "
            if state.get("override"):
                prefix += "(Overridden) "
            rule_tags = [f"availability-{status}"]
            if membership == "blacklist":
                rule_tags.append("availability-blacklisted")
            elif membership == "whitelist":
                rule_tags.append("availability-whitelisted")
            elif state.get("override"):
                rule_tags.append("availability-overridden")
            iid = self.availability_overview_tree.insert("", "end", values=(
                f"{prefix}{row.get('fullType') or '<unknown>'}",
                status,
                rule_label,
                row.get("category") or "Unclassified",
                row.get("primary") or "Unclassified",
                channels,
                availability.get("reason") or "",
                row.get("workshopMod") or "",
            ), tags=tuple(rule_tags))
            self.availability_overview_row_by_iid[iid] = row
        self.availability_overview_count_var.set(
            f"{len(rows):,} items shown / {len(source_rows):,} in scope"
        )

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
