"""Item hierarchy, filtering, and evidence views for the inspector."""

from __future__ import annotations

import json
from typing import Any

from .lua_rules import (
    RUNTIME_RULES_PATH,
    RuntimeRuleError,
    load_rules,
    remove_all_item_rules,
    remove_item_override,
    save_rules,
    set_item_override,
    set_membership_rule,
)
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
        self.item_tree.bind("<Button-3>", self._show_item_context_menu)
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

    def _show_item_context_menu(self, event: Any) -> str:
        """Open the MarketSense rule editor for a leaf item row."""

        item_iid = self.item_tree.identify_row(event.y)
        row = self.item_row_by_iid.get(item_iid)
        if row is None:
            return "break"
        if self.busy:
            self.status_var.set("Finish the current scan before editing runtime rules.")
            return "break"

        self.item_tree.selection_set(item_iid)
        self.item_tree.focus(item_iid)
        item_id = str(row.get("fullType") or "").strip()
        if not item_id:
            return "break"

        menu = self.tk.Menu(self.root, tearoff=False)
        menu.add_command(
            label="Blacklist this item",
            command=lambda: self._edit_item_membership(item_id, "blacklist"),
        )
        menu.add_command(
            label="Whitelist this item",
            command=lambda: self._edit_item_membership(item_id, "whitelist"),
        )
        menu.add_command(
            label="Clear blacklist / whitelist status",
            command=lambda: self._edit_item_membership(item_id, None),
        )
        menu.add_separator()
        menu.add_command(
            label="Set exact price…",
            command=lambda: self._edit_item_price(item_id, row),
        )
        menu.add_command(
            label="Set exact tags…",
            command=lambda: self._edit_item_tags(item_id, row),
        )
        menu.add_command(
            label="Set stock range…",
            command=lambda: self._edit_item_stock(item_id, row),
        )
        menu.add_command(
            label="Remove item override",
            command=lambda: self._remove_item_override(item_id),
        )
        menu.add_command(
            label="Clear all MarketSense rules for item",
            command=lambda: self._clear_item_rules(item_id),
        )
        menu.add_separator()
        menu.add_command(
            label=f"Edit: {RUNTIME_RULES_PATH.name}",
            command=lambda: self._show_rule_file_location(),
        )
        menu.tk_popup(event.x_root, event.y_root)
        menu.grab_release()
        return "break"

    def _show_rule_file_location(self) -> None:
        self.status_var.set(f"MarketSense runtime rules: {RUNTIME_RULES_PATH}")
        self._append_log(
            f"Runtime-rule file: {RUNTIME_RULES_PATH}\n"
            "GUI edits are written as standalone MarketSense Lua data."
        )

    def _load_rules_for_edit(self) -> dict[str, Any] | None:
        try:
            return load_rules()
        except RuntimeError as error:
            self.messagebox.showerror("Read MarketSense runtime rules", str(error))
            return None

    def _save_rules_after_edit(
        self,
        rules: dict[str, Any],
        item_id: str,
        action: str,
    ) -> None:
        try:
            path = save_rules(rules)
        except (OSError, RuntimeRuleError) as error:
            self.messagebox.showerror("Save MarketSense runtime rules", str(error))
            return
        self.status_var.set(f"{action} saved; rescanning with the updated Lua rules…")
        self._append_log(
            json.dumps(
                {
                    "event": "runtime_rule_saved",
                    "action": action,
                    "item": item_id,
                    "path": str(path),
                    "note": "cache invalidated by the rule-file manifest; rescan started",
                },
                indent=2,
            )
        )
        self._rescan_after_rule_edit(item_id)

    def _edit_item_membership(
        self, item_id: str, membership: str | None
    ) -> None:
        rules = self._load_rules_for_edit()
        if rules is None:
            return
        set_membership_rule(rules, item_id, membership)
        action = {
            "blacklist": "Blacklist",
            "whitelist": "Whitelist",
            None: "Membership cleared",
        }[membership]
        self._save_rules_after_edit(rules, item_id, action)

    def _item_override(self, rules: dict[str, Any], item_id: str) -> dict[str, Any]:
        return next(
            (
                entry for entry in rules.get("overrides", [])
                if entry.get("id") == item_id
            ),
            {},
        )

    def _edit_item_price(self, item_id: str, row: dict[str, Any]) -> None:
        rules = self._load_rules_for_edit()
        if rules is None:
            return
        existing = self._item_override(rules, item_id)
        current = existing.get("price", row.get("price"))
        try:
            current_value = int(float(current)) if current not in (None, "") else 0
        except (TypeError, ValueError):
            current_value = 0
        value = self.simpledialog.askinteger(
            "MarketSense exact price",
            f"Exact price for {item_id}:\n(blank/cancel leaves the file unchanged)",
            initialvalue=max(0, current_value),
            minvalue=0,
            parent=self.root,
        )
        if value is None:
            return
        set_item_override(rules, item_id, price=value)
        self._save_rules_after_edit(rules, item_id, "Exact price")

    def _edit_item_tags(self, item_id: str, row: dict[str, Any]) -> None:
        rules = self._load_rules_for_edit()
        if rules is None:
            return
        existing = self._item_override(rules, item_id)
        current_tags = (
            existing.get("tags")
            or row.get("tags")
            or row.get("expandedTags")
            or []
        )
        value = self.simpledialog.askstring(
            "MarketSense exact tags",
            "Comma-separated tags (blank removes exact tags):",
            initialvalue=", ".join(str(tag) for tag in current_tags),
            parent=self.root,
        )
        if value is None:
            return
        tags = [tag.strip() for tag in value.split(",") if tag.strip()]
        set_item_override(rules, item_id, tags=tags)
        self._save_rules_after_edit(rules, item_id, "Exact tags")

    def _edit_item_stock(self, item_id: str, row: dict[str, Any]) -> None:
        rules = self._load_rules_for_edit()
        if rules is None:
            return
        existing = self._item_override(rules, item_id)
        stock = (
            existing.get("stock")
            if isinstance(existing.get("stock"), dict)
            else {}
        )
        row_stock = (
            row.get("stock") if isinstance(row.get("stock"), dict) else {}
        )
        current_min = stock.get("min", row_stock.get("min", 0))
        current_max = stock.get("max", row_stock.get("max", 1))
        try:
            current_min, current_max = int(current_min), int(current_max)
        except (TypeError, ValueError):
            current_min, current_max = 0, 1
        minimum = self.simpledialog.askinteger(
            "MarketSense stock minimum",
            f"Minimum stock for {item_id}:",
            initialvalue=max(0, current_min),
            minvalue=0,
            parent=self.root,
        )
        if minimum is None:
            return
        maximum = self.simpledialog.askinteger(
            "MarketSense stock maximum",
            f"Maximum stock for {item_id}:",
            initialvalue=max(minimum, current_max),
            minvalue=minimum,
            parent=self.root,
        )
        if maximum is None:
            return
        set_item_override(rules, item_id, stock={"min": minimum, "max": maximum})
        self._save_rules_after_edit(rules, item_id, "Stock range")

    def _remove_item_override(self, item_id: str) -> None:
        rules = self._load_rules_for_edit()
        if rules is None or not remove_item_override(rules, item_id):
            if rules is not None:
                self.status_var.set(f"No item override exists for {item_id}.")
            return
        self._save_rules_after_edit(rules, item_id, "Item override removal")

    def _clear_item_rules(self, item_id: str) -> None:
        rules = self._load_rules_for_edit()
        if rules is None or not remove_all_item_rules(rules, item_id):
            if rules is not None:
                self.status_var.set(f"No MarketSense rules exist for {item_id}.")
            return
        self._save_rules_after_edit(rules, item_id, "All item rules cleared")
