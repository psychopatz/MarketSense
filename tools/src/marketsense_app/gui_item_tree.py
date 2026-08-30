"""Item-tree construction, layout, filtering, and rendering behavior."""

from __future__ import annotations

import json
from typing import Any

from .gui_item_model import (
    _ITEM_COLUMN_NAMES,
    _ITEM_COLUMN_SPECS,
    metadata_label,
)
from .review import review_row, searchable_text


class ItemTreeMixin:
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
        self.ttk.Label(
            toolbar,
            text="Red=blacklist · Green=whitelist · Amber=override",
        ).pack(side="left", padx=(12, 0))
        self.item_count_var = self.tk.StringVar(value="0 shown")
        self.ttk.Label(toolbar, textvariable=self.item_count_var).pack(side="right")
        self.ttk.Label(
            frame,
            text=(
                "Hierarchy: main category → subcategory → primary tag → item. "
                "Use Expand Food to inspect every food row; review flags are triage hints, "
                "not confirmed false positives. The yield column shows bundle/recipe "
                "resolution and name-based candidates are flagged for review. The "
                "default list requires authoritative "
                "loot/crafting/foraging/farming/fishing/animal evidence; change Availability "
                "to inspect uncertain or excluded definitions."
            ),
        ).pack(fill="x", pady=(0, 4))
        self.item_category_nodes: dict[str, str] = {}
        self.item_row_by_iid: dict[str, dict[str, Any]] = {}
        self.item_iid_by_full_type: dict[str, str] = {}
        self.item_row_number_by_full_type: dict[str, int] = {}
        self.item_columns = list(_ITEM_COLUMN_SPECS)
        self.item_column_order, visible_columns = self._load_item_column_layout()
        self.item_column_vars = {
            name: self.tk.BooleanVar(value=name in visible_columns)
            for name in _ITEM_COLUMN_NAMES
        }
        self.item_tree = self._tree(
            frame, self.item_columns, hierarchical=True
        )
        self._apply_item_column_layout(save=False)
        # Alternating row colors (zebra striping) keep long expanded lists
        # readable without hiding the hierarchy in repeated columns.
        self.item_tree.tag_configure("item-even", background="#ffffff")
        self.item_tree.tag_configure("item-odd", background="#f0f0f0")
        self.item_tree.tag_configure("item-blacklisted", foreground="#b42318")
        self.item_tree.tag_configure("item-whitelisted", foreground="#087f5b")
        self.item_tree.tag_configure("item-overridden", foreground="#8a5a00")
        self.item_tree.bind(
            "<<TreeviewSelect>>", lambda _event: self._show_item_details()
        )
        self.item_tree.bind("<Button-3>", self._show_item_context_menu)
        self.item_tree.bind(
            "<ButtonPress-1>", self._begin_item_column_drag, add="+"
        )
        self.item_tree.bind(
            "<B1-Motion>", self._track_item_column_drag, add="+"
        )
        self.item_tree.bind(
            "<ButtonRelease-1>", self._finish_item_column_drag, add="+"
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

    def _load_item_column_layout(self) -> tuple[list[str], set[str]]:
        """Load a validated order/visibility pair, retaining safe defaults."""

        preferences = getattr(self, "preferences", {})
        saved = (
            preferences.get("itemColumns")
            if isinstance(preferences, dict) else {}
        )
        saved = saved if isinstance(saved, dict) else {}
        order = [
            name for name in saved.get("order", [])
            if name in _ITEM_COLUMN_NAMES
        ]
        order.extend(name for name in _ITEM_COLUMN_NAMES if name not in order)
        visible = {
            name for name in saved.get("visible", [])
            if name in _ITEM_COLUMN_NAMES
        }
        if not visible:
            visible = set(_ITEM_COLUMN_NAMES)
        return order, visible

    def _item_column_preferences(self) -> dict[str, list[str]]:
        visible = [
            name for name in self.item_column_order
            if self.item_column_vars[name].get()
        ]
        return {"order": list(self.item_column_order), "visible": visible}

    def _apply_item_column_layout(self, save: bool = True) -> None:
        if not hasattr(self, "item_tree"):
            return
        visible = [
            name for name in self.item_column_order
            if self.item_column_vars[name].get()
        ]
        # Keep at least one data column available so the tree never collapses
        # into a hierarchy with no useful detail columns.
        if not visible:
            first = self.item_column_order[0]
            self.item_column_vars[first].set(True)
            visible = [first]
        self.item_tree.configure(displaycolumns=tuple(visible))
        if save and hasattr(self, "_queue_save_preferences"):
            self._queue_save_preferences()

    def _toggle_item_column(self, name: str) -> None:
        if name not in self.item_column_vars:
            return
        self._apply_item_column_layout()
        visible = [
            key for key in self.item_column_order
            if self.item_column_vars[key].get()
        ]
        self.status_var.set(
            f"Item columns: {len(visible)} shown / {len(_ITEM_COLUMN_NAMES)} available."
        )
    def _item_column_at_event(self, event: Any) -> str | None:
        identifier = self.item_tree.identify_column(event.x)
        if identifier == "#0":
            return None
        if identifier in _ITEM_COLUMN_NAMES:
            return identifier
        if not str(identifier).startswith("#"):
            return None
        try:
            displayed_index = int(str(identifier)[1:]) - 1
        except ValueError:
            return None
        displayed = tuple(self.item_tree["displaycolumns"])
        if 0 <= displayed_index < len(displayed):
            return str(displayed[displayed_index])
        return None

    def _show_item_column_menu(self, event: Any) -> str:
        menu = self.tk.Menu(self.root, tearoff=False)
        menu.add_command(
            label="item / category (always visible)", state="disabled"
        )
        menu.add_separator()
        for name in self.item_column_order:
            menu.add_checkbutton(
                label=name,
                variable=self.item_column_vars[name],
                command=lambda column=name: self._toggle_item_column(column),
            )
        menu.add_separator()
        menu.add_command(
            label="Reset item columns",
            command=self._reset_item_column_layout,
        )
        menu.add_command(
            label="Drag headings to reorder",
            state="disabled",
        )
        menu.tk_popup(event.x_root, event.y_root)
        menu.grab_release()
        return "break"

    def _reset_item_column_layout(self) -> None:
        self.item_column_order = list(_ITEM_COLUMN_NAMES)
        for name in _ITEM_COLUMN_NAMES:
            self.item_column_vars[name].set(True)
        self._apply_item_column_layout()
        self.status_var.set("Item columns reset to the default layout.")

    def _begin_item_column_drag(self, event: Any) -> str | None:
        if self.item_tree.identify_region(event.x, event.y) != "heading":
            self._item_drag_source = None
            return None
        self._item_drag_source = self._item_column_at_event(event)
        self._item_drag_start_x = event.x
        return "break"

    def _track_item_column_drag(self, event: Any) -> None:
        source = getattr(self, "_item_drag_source", None)
        if source and abs(
            event.x - getattr(self, "_item_drag_start_x", event.x)
        ) > 4:
            self.status_var.set(
                f"Move {source} before the column under the pointer…"
            )

    def _finish_item_column_drag(self, event: Any) -> str | None:
        source = getattr(self, "_item_drag_source", None)
        self._item_drag_source = None
        if (
            not source
            or self.item_tree.identify_region(event.x, event.y) != "heading"
        ):
            return None
        target = self._item_column_at_event(event)
        if target and target != source:
            order = [name for name in self.item_column_order if name != source]
            order.insert(order.index(target), source)
            self.item_column_order = order
            self._apply_item_column_layout()
            self.status_var.set(
                f"Item columns reordered: {source} is before {target}."
            )
        return "break"

    def _item_rule_state(self, item_id: str) -> dict[str, Any]:
        indexed = getattr(self, "item_rule_state_by_id", {})
        state = indexed.get(item_id)
        if not isinstance(state, dict):
            return {"membership": None, "override": {}}
        return {
            "membership": state.get("membership"),
            "override": dict(state.get("override") or {}),
        }

    @staticmethod
    def _has_item_override(state: dict[str, Any]) -> bool:
        return bool(state.get("override"))

    @staticmethod
    def _item_rule_label(state: dict[str, Any]) -> str:
        labels = []
        membership = state.get("membership")
        if membership:
            labels.append({
                "blacklist": "Blacklisted",
                "whitelist": "Whitelisted",
            }.get(membership, membership.title()))
        override = state.get("override") or {}
        field_labels = {
            "price": "price",
            "tags": "tags",
            "addTags": "+tags",
            "removeTags": "-tags",
            "stock": "stock",
            "stockMin": "stock min",
            "stockMax": "stock max",
            "add": "+price",
            "mult": "price mult",
            "minPrice": "price floor",
            "min": "price floor",
        }
        labels.extend(
            field_labels.get(key, key)
            for key in sorted(override)
        )
        return ", ".join(labels)

    @staticmethod
    def _item_rule_prefix(state: dict[str, Any]) -> str:
        labels = []
        membership = state.get("membership")
        if membership:
            membership_label = {
                "blacklist": "Blacklisted",
                "whitelist": "Whitelisted",
            }.get(membership, membership.title())
            labels.append(f"({membership_label})")
        if state.get("override"):
            labels.append("(Overridden)")
        return " ".join(labels)

    def _item_display_values(
        self, row: dict[str, Any], status: str, reason: str,
    ) -> tuple[Any, ...]:
        item_id = str(row.get("fullType") or "")
        state = self._item_rule_state(item_id)
        override = state.get("override") or {}
        price = override.get("price", row.get("price", ""))
        stock = override.get("stock")
        if not isinstance(stock, dict):
            stock = row.get("stock") if isinstance(row.get("stock"), dict) else {}
        else:
            stock = dict(stock)
        if "stockMin" in override:
            stock["min"] = override["stockMin"]
        if "stockMax" in override:
            stock["max"] = override["stockMax"]
        stock_min = stock.get("min", "")
        stock_max = stock.get("max", "")
        stock_label = (
            f"{stock_min}–{stock_max}"
            if stock_min != "" or stock_max != ""
            else ""
        )
        item_metadata = metadata_label(row)
        exact_tags = override.get("tags")
        if isinstance(exact_tags, list):
            override_tags = ", ".join(str(tag) for tag in exact_tags)
            item_metadata = (
                f"{item_metadata} · " if item_metadata else ""
            ) + f"Tags={override_tags}"
        return (
            price,
            str((row.get("availability") or {}).get("status") or "uncertain"),
            status,
            self._item_rule_label(state),
            item_metadata,
            stock_label,
            reason,
            row.get("detector", ""),
            row.get("resolver", ""),
            row.get("yieldResolver", ""),
            row.get("confidence", ""),
            row.get("workshopMod", ""),
            row.get("description", ""),
        )

    def _item_tree_tags(self, row: dict[str, Any], row_number: int) -> tuple[str, ...]:
        state = self._item_rule_state(str(row.get("fullType") or ""))
        tags = ["item-even" if row_number % 2 == 0 else "item-odd"]
        if state.get("membership") == "blacklist":
            tags.append("item-blacklisted")
        elif state.get("membership") == "whitelist":
            tags.append("item-whitelisted")
        elif self._has_item_override(state):
            tags.append("item-overridden")
        return tuple(tags)

    def _refresh_item_tree(self) -> None:
        if not hasattr(self, "item_tree"):
            return
        self.item_tree.delete(*self.item_tree.get_children())
        self.item_category_nodes.clear()
        self.item_row_by_iid.clear()
        self.item_iid_by_full_type.clear()
        self.item_row_number_by_full_type.clear()
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
            if query:
                rule_label = self._item_rule_label(
                    self._item_rule_state(str(row.get("fullType") or ""))
                ).casefold()
                if query not in searchable_text(row) and query not in rule_label:
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
                values=(
                    "", "", "", f"{category_count:,} items",
                    "", "", "", "", "", "", "", "", "",
                ),
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
                        "", "", "", "", "", "", "", "", "",
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
                            "", "", "", "", "", "", "", "", "",
                        ),
                    )
                    for row, status, reason in primary_rows:
                        full_type = str(row.get("fullType") or "")
                        prefix = self._item_rule_prefix(
                            self._item_rule_state(full_type)
                        )
                        display_name = (
                            f"{prefix} {full_type}" if prefix else full_type
                        )
                        item_id = self.item_tree.insert(
                            primary_id,
                            "end",
                            text=display_name or "<unknown>",
                            values=self._item_display_values(row, status, reason),
                            tags=self._item_tree_tags(row, item_row_number),
                        )
                        self.item_row_by_iid[item_id] = row
                        self.item_iid_by_full_type[full_type] = item_id
                        self.item_row_number_by_full_type[full_type] = item_row_number
                        item_row_number += 1
        self.item_count_var.set(
            f"{shown:,} items in {len(grouped):,} categories / "
            f"{len(self.rows):,} listed"
        )
