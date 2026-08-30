"""Runtime-rule state and item rule-editing behavior for the GUI."""

from __future__ import annotations

import json
from typing import Any

from .gui_filters import normalize_view_availability
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
from .review import review_row


class ItemRulesMixin:
    def _sync_runtime_rules(self, rules: dict[str, Any] | None = None) -> None:
        """Load exact rule state once so markers do not invoke the evaluator."""

        if rules is None:
            try:
                rules = load_rules()
            except RuntimeError as error:
                rules = {}
                if hasattr(self, "log"):
                    self._append_log(
                        f"Could not load runtime-rule markers: {error}"
                    )
        self.runtime_rules = rules
        indexed: dict[str, dict[str, Any]] = {}
        for item_id in rules.get("blacklist", []):
            indexed.setdefault(
                str(item_id), {"membership": "blacklist", "override": {}}
            )["membership"] = "blacklist"
        for item_id in rules.get("whitelist", []):
            state = indexed.setdefault(
                str(item_id), {"membership": None, "override": {}}
            )
            if state.get("membership") != "blacklist":
                state["membership"] = "whitelist"
        for entry in rules.get("overrides", []):
            if not isinstance(entry, dict) or not entry.get("id"):
                continue
            item_id = str(entry["id"])
            state = indexed.setdefault(
                item_id, {"membership": None, "override": {}}
            )
            state["override"] = {
                key: value for key, value in entry.items() if key != "id"
            }
        self.item_rule_state_by_id = indexed

    def _refresh_item_tree_row(self, item_id: str) -> None:
        """Update one visible leaf row after a rule edit."""

        iid = self.item_iid_by_full_type.get(item_id)
        if iid is None:
            return
        row = self.item_row_by_iid.get(iid)
        if row is None:
            return
        status, reason = review_row(row)
        state = self._item_rule_state(item_id)
        prefix = self._item_rule_prefix(state)
        label = f"{prefix} {item_id}" if prefix else item_id
        row_number = self.item_row_number_by_full_type.get(item_id, 0)
        self.item_tree.item(
            iid,
            text=label or "<unknown>",
            values=self._item_display_values(row, status, reason),
            tags=self._item_tree_tags(row, row_number),
        )
        if iid in self.item_tree.selection():
            self._show_item_details()

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
            item_id = str(row.get("fullType") or "")
            state = self._item_rule_state(item_id)
            override = state.get("override") or {}
            detail_data["runtimeRules"] = {
                "membership": state.get("membership"),
                "override": override,
            }
            detail_data["guiDisplay"] = {
                "price": override.get("price", row.get("price", "")),
                "tags": override.get("tags", row.get("tags", [])),
                "stock": override.get(
                    "stock", row.get("stock") if isinstance(row.get("stock"), dict) else {}
                ),
            }
            detail = json.dumps(detail_data, indent=2, sort_keys=True)
        self.item_detail.configure(state="normal")
        self.item_detail.delete("1.0", "end")
        self.item_detail.insert("end", detail)
        self.item_detail.configure(state="disabled")

    def _show_item_context_menu(self, event: Any) -> str:
        """Open the MarketSense rule editor for a leaf item row."""

        if self.item_tree.identify_region(event.x, event.y) == "heading":
            return self._show_item_column_menu(event)

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
        self._sync_runtime_rules(rules)
        selected_view = normalize_view_availability(
            self.availability_var.get()
            if hasattr(self, "availability_var") else "all"
        )
        if (
            selected_view in {"changed", "blacklisted", "whitelisted", "overridden"}
            and hasattr(self, "_apply_view_filters")
        ):
            # A rule-state view may need to add/remove the edited row.  This
            # is still only an in-memory GUI rebuild; it never invokes Lua or
            # Workshop discovery.
            self._apply_view_filters()
        else:
            self._refresh_item_tree_row(item_id)
            self._refresh_availability_overview()
        self.status_var.set(
            f"{action} saved; GUI updated locally. "
            "The game will consume the rule on its next runtime load."
        )
        self._append_log(
            json.dumps(
                {
                    "event": "runtime_rule_saved",
                    "action": action,
                    "item": item_id,
                    "path": str(path),
                    "note": "local row updated; no catalog rescan was started",
                },
                indent=2,
            )
        )

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
