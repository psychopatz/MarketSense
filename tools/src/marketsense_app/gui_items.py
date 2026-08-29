"""Item hierarchy, filtering, and evidence views for the inspector."""

from __future__ import annotations

import json
from typing import Any

from .review import review_row, searchable_text


class ItemsMixin:
    def _build_items(self) -> None:
        frame = self.ttk.Frame(self.notebook, padding=8)
        self.notebook.add(frame, text="Items")
        toolbar = self.ttk.Frame(frame)
        toolbar.pack(fill="x", pady=(0, 6))
        self.item_search_var = self.tk.StringVar()
        self.ttk.Label(toolbar, text="Find item or evidence").pack(side="left")
        self.ttk.Entry(toolbar, textvariable=self.item_search_var, width=30).pack(
            side="left", padx=(6, 10)
        )
        self.item_search_var.trace_add(
            "write", lambda *_: self._refresh_item_tree()
        )
        self.ttk.Label(toolbar, text="Review").pack(side="left")
        self.item_review_var = self.tk.StringVar(value="All")
        self.item_review_combo = self.ttk.Combobox(
            toolbar,
            textvariable=self.item_review_var,
            values=("All", "Review", "OK", "Error"),
            state="readonly",
            width=10,
        )
        self.item_review_combo.pack(side="left", padx=(6, 10))
        self.item_review_combo.bind(
            "<<ComboboxSelected>>",
            lambda _event: self._refresh_item_tree(),
        )
        self.ttk.Button(
            toolbar, text="Collapse all", command=self._collapse_item_categories
        ).pack(side="left", padx=(4, 0))
        self.ttk.Button(
            toolbar, text="Expand Food", command=self._expand_food_category
        ).pack(side="left", padx=(4, 0))
        self.ttk.Button(
            toolbar, text="Expand all", command=self._expand_item_categories
        ).pack(side="left", padx=(4, 0))
        self.ttk.Button(
            toolbar, text="Clear search", command=self._clear_item_filters
        ).pack(side="left", padx=(4, 0))
        self.item_count_var = self.tk.StringVar(value="0 shown")
        self.ttk.Label(toolbar, textvariable=self.item_count_var).pack(side="right")
        self.ttk.Label(
            frame,
            text=(
                "Hierarchy: main category → subcategory → primary tag → item. "
                "Use Expand Food to inspect every food row; review flags are triage hints, "
                "not confirmed false positives. The default list requires authoritative "
                "loot/crafting/foraging/farming/fishing/animal evidence; change Availability "
                "to inspect uncertain or excluded definitions."
            ),
        ).pack(fill="x", pady=(0, 4))
        self.item_category_nodes: dict[str, str] = {}
        self.item_row_by_iid: dict[str, dict[str, Any]] = {}
        self.item_columns = [
            ("price", 80),
            ("availability", 110),
            ("review", 90),
            ("reason", 320),
            ("detector", 140),
            ("resolver", 160),
            ("confidence", 90),
            ("mod", 170),
            ("description", 300),
        ]
        self.item_tree = self._tree(
            frame, self.item_columns, hierarchical=True
        )
        # Alternating row colors (zebra striping) keep long expanded lists
        # readable without hiding the hierarchy in repeated columns.
        self.item_tree.tag_configure("item-even", background="#ffffff")
        self.item_tree.tag_configure("item-odd", background="#f0f0f0")
        self.item_tree.bind(
            "<<TreeviewSelect>>", lambda _event: self._show_item_details()
        )
        self.ttk.Label(
            frame, text="Selected item runtime evidence"
        ).pack(anchor="w", pady=(6, 2))
        self.item_detail = self.scrolledtext.ScrolledText(
            frame, height=9, wrap="none", state="disabled"
        )
        self.item_detail.pack(fill="both", expand=False)

    def _clear_item_filters(self) -> None:
        self.item_search_var.set("")
        self.item_review_var.set("All")

    def _collapse_item_categories(self) -> None:
        for item_id in self.item_category_nodes.values():
            self._set_item_group_open(item_id, False)

    def _expand_item_categories(self) -> None:
        for item_id in self.item_category_nodes.values():
            self._set_item_group_open(item_id, True)

    def _expand_food_category(self) -> None:
        item_id = self.item_category_nodes.get("Food")
        if item_id is None:
            self.status_var.set(
                "Food category is not present in the current filtered results."
            )
            return
        self._set_item_group_open(item_id, True)
        self.item_tree.see(item_id)

    def _set_item_group_open(self, item_id: str, is_open: bool) -> None:
        self.item_tree.item(item_id, open=is_open)
        for child_id in self.item_tree.get_children(item_id):
            if self.item_tree.get_children(child_id):
                self._set_item_group_open(child_id, is_open)

    def _refresh_item_tree(self) -> None:
        if not hasattr(self, "item_tree"):
            return
        self.item_tree.delete(*self.item_tree.get_children())
        self.item_category_nodes.clear()
        self.item_row_by_iid.clear()
        query = self.item_search_var.get().strip().casefold()
        review_filter = self.item_review_var.get().casefold()
        grouped: dict[
            str, dict[str, dict[str, list[tuple[dict[str, Any], str, str]]]]
        ] = {}
        for row in sorted(
            self.rows,
            key=lambda item: (
                float(item.get("price") or 0),
                str(item.get("fullType", "")),
            ),
            reverse=True,
        ):
            status, reason = review_row(row)
            if review_filter != "all" and status.casefold() != review_filter:
                continue
            if query and query not in searchable_text(row):
                continue
            hierarchy = (
                row.get("hierarchy")
                if isinstance(row.get("hierarchy"), dict)
                else {}
            )
            category = str(
                row.get("category") or hierarchy.get("root") or "Unclassified"
            )
            subcategory = str(
                row.get("subcategory")
                or hierarchy.get("subcategory")
                or "Unclassified"
            )
            primary = str(
                row.get("primary") or hierarchy.get("token") or "Unclassified"
            )
            grouped.setdefault(category, {}).setdefault(
                subcategory, {}
            ).setdefault(primary, []).append((row, status, reason))

        shown = sum(
            len(items)
            for subcategories in grouped.values()
            for primaries in subcategories.values()
            for items in primaries.values()
        )
        item_row_number = 0
        for category, subcategories in sorted(grouped.items()):
            category_count = sum(
                len(items)
                for primaries in subcategories.values()
                for items in primaries.values()
            )
            category_id = self.item_tree.insert(
                "",
                "end",
                text=f"{category} ({category_count:,})",
                open=False,
                values=("", "", "", f"{category_count:,} items", "", "", "", "", ""),
            )
            self.item_category_nodes[category] = category_id
            for subcategory, primaries in sorted(subcategories.items()):
                subcategory_count = sum(
                    len(items) for items in primaries.values()
                )
                subcategory_id = self.item_tree.insert(
                    category_id,
                    "end",
                    text=f"{subcategory} ({subcategory_count:,})",
                    open=False,
                    values=(
                        "", "", "", f"{subcategory_count:,} items",
                        "", "", "", "", "",
                    ),
                )
                for primary, primary_rows in sorted(primaries.items()):
                    primary_count = len(primary_rows)
                    primary_label = primary
                    first_hierarchy = primary_rows[0][0].get("hierarchy")
                    if (
                        isinstance(first_hierarchy, dict)
                        and first_hierarchy.get("leaf")
                    ):
                        leaf = str(first_hierarchy["leaf"])
                        if leaf != primary:
                            primary_label = f"{leaf} [{primary}]"
                    primary_id = self.item_tree.insert(
                        subcategory_id,
                        "end",
                        text=f"{primary_label} ({primary_count:,})",
                        open=False,
                        values=(
                            "", "", "", f"{primary_count:,} items",
                            "", "", "", "", "",
                        ),
                    )
                    for row, status, reason in primary_rows:
                        item_id = self.item_tree.insert(
                            primary_id,
                            "end",
                            text=row.get("fullType") or "<unknown>",
                            values=(
                                row.get("price", ""),
                                str(
                                    (row.get("availability") or {}).get("status")
                                    or "uncertain"
                                ),
                                status,
                                reason,
                                row.get("detector", ""),
                                row.get("resolver", ""),
                                row.get("confidence", ""),
                                row.get("workshopMod", ""),
                                row.get("description", ""),
                            ),
                            tags=(
                                "item-even"
                                if item_row_number % 2 == 0
                                else "item-odd",
                            ),
                        )
                        self.item_row_by_iid[item_id] = row
                        item_row_number += 1
        self.item_count_var.set(
            f"{shown:,} items in {len(grouped):,} categories / "
            f"{len(self.rows):,} listed"
        )

    def _show_item_details(self) -> None:
        selection = self.item_tree.selection()
        row = self.item_row_by_iid.get(selection[0]) if selection else None
        if row is None:
            detail = (
                "Select an item row (the deepest level) to inspect its runtime "
                "evidence."
            )
        else:
            status, reason = review_row(row)
            detail_data = dict(row)
            detail_data["review"] = {"status": status, "reason": reason}
            detail = json.dumps(detail_data, indent=2, sort_keys=True)
        self.item_detail.configure(state="normal")
        self.item_detail.delete("1.0", "end")
        self.item_detail.insert("end", detail)
        self.item_detail.configure(state="disabled")
