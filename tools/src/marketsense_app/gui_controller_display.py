"""GUI result filtering, status, and tree population behavior."""

from __future__ import annotations

import json
from typing import Any

from .gui_filters import filter_rows, view_summary
from .review import review_count, review_row
from .scan_scope import category_scope_label
from .gui_controller_support import ALL_MODS_LABEL

class DisplayControllerMixin:
    """Own one GUI controller concern behind the stable composite mixin."""

    def _diagnostic_result_summary(self) -> str:
        """Return a compact completion record instead of dumping every row."""

        master = self.master_summary or {}
        view = self.summary or {}
        cache = master.get("cache") or {}
        sample_fields = (
            "fullType", "workshopMod", "category", "primary", "price",
            "confidence", "detector", "resolver",
        )
        sample = [
            {field: row.get(field, "") for field in sample_fields}
            for row in self.rows[:12]
        ]
        return json.dumps({
            "event": "scan_complete",
            "masterRows": len(self.master_rows),
            "visibleRows": len(self.rows),
            "cache": cache,
            "view": {
                "mod": self.mod_filter_var.get() or ALL_MODS_LABEL,
                "category": view.get("category_filter", "all"),
                "availability": view.get("availability_filter", "obtainable"),
                "skipVanilla": self.no_base_var.get(),
                "maxShown": self.max_items_var.get().strip() or "0",
            },
            "summary": {
                "categories": len(view.get("categories") or {}),
                "errors": view.get("errors", 0),
                "reviewFlags": review_count(self.rows),
                "heuristicGapCandidates": (
                    (view.get("heuristic_coverage") or {}).get("candidate_count", 0)
                ),
                "priceRange": view.get("prices") or {},
            },
            "sampleRows": sample,
            "note": "Full rows are available through Save JSON/CSV.",
        }, indent=2, sort_keys=True)

    def _apply_view_filters(self) -> None:
        """Rebuild every GUI view from the in-memory master result."""

        self._view_filter_after_id = None
        if not self.master_summary:
            return
        try:
            max_items = max(0, int(self.max_items_var.get().strip() or 0))
        except ValueError:
            self.status_var.set("Max items must be a non-negative integer.")
            return
        self.rows = filter_rows(
            self.master_rows,
            availability=self.availability_var.get(),
            mod_filters=self._selected_mod_filters(),
            skip_vanilla=self.no_base_var.get(),
            max_items=max_items,
            rule_state_by_id=getattr(self, "item_rule_state_by_id", {}),
        )
        self.summary = view_summary(
            self.master_summary,
            self.rows,
            self.master_rows,
            self.availability_var.get(),
        )
        prices = self.summary["prices"]
        self.metric_vars["items"].set(str(self.summary["evaluated"]))
        self.metric_vars["prices"].set(
            f"{prices['min']:g} – {prices['max']:g}"
        )
        self.metric_vars["categories"].set(str(len(self.summary["categories"])))
        self.metric_vars["review"].set(str(review_count(self.rows)))
        self.metric_vars["errors"].set(str(self.summary["errors"]))
        self.metric_vars["heuristic"].set(str(
            (self.summary.get("heuristic_coverage") or {}).get("candidate_count", 0)
        ))
        self._fill_trees()
        self._redraw()
        self._set_view_status()

    def _set_view_status(self) -> None:
        summary = self.summary or {}
        master = self.master_summary or {}
        cache = master.get("cache") or {}
        cache_status = cache.get("status", "disabled")
        cache_path = cache.get("path", "not configured")
        master_count = len(self.master_rows)
        view_count = len(self.rows)
        selected_mod = self.mod_filter_var.get() or ALL_MODS_LABEL
        selected_category = category_scope_label(
            master.get("category_filter") or self.category_scope_var.get()
        )
        view_filter = summary.get("availability_filter", "obtainable")
        view_note = (
            f"Scope: {selected_category}; view: {selected_mod}, {view_filter}, "
            f"{'no vanilla' if self.no_base_var.get() else 'vanilla included'}"
        )
        self.status_var.set(
            f"{'Cached master loaded' if cache_status == 'hit' else 'Master scan complete'}: "
            f"{view_count:,} shown / {master_count:,} scanned, "
            f"{master.get('workshop_mods', 0)} Workshop mods, "
            f"{summary.get('vanilla_items', 0):,} vanilla items, "
            f"{summary.get('workshop_items', 0):,} Workshop items, "
            f"{summary.get('errors', 0):,} errors, "
            f"{review_count(self.rows):,} review flags. "
            f"Heuristic-gap candidates: "
            f"{(summary.get('heuristic_coverage') or {}).get('candidate_count', 0):,}. "
            f"{view_note} ({summary.get('view_filtered_out', 0):,} hidden; "
            f"{(summary.get('availability_counts') or {}).get('uncertain', 0):,} "
            f"uncertain, "
            f"{(summary.get('availability_counts') or {}).get('excluded', 0):,} "
            f"excluded). Cache: {cache_status} ({cache_path}). "
            f"Version ceiling: {master.get('workshop_script_selection', '-')}. "
            "View filters are local; change the scan scope and run Scan selected scope / cache to rebuild."
        )

    def _fill_trees(self) -> None:
        for tree in (
            self.category_tree if hasattr(self, "category_tree") else None,
            self.item_tree,
            self.review_tree,
            self.mod_tree,
        ):
            if tree:
                tree.delete(*tree.get_children())
        self.category_tree = getattr(self, "category_tree", None)
        if self.category_tree is None:
            return
        for category, data in self.summary["categories"].items():
            self.category_tree.insert("", "end", values=(
                category,
                data["count"],
                f"{data['min']:g}",
                f"{data['median']:g}",
                f"{data['max']:g}",
                data["unique"],
            ))
        self._refresh_item_tree()
        self._refresh_availability_overview()
        self._refresh_low_confidence()
        self._refresh_heuristic_gaps()
        flagged_rows = [
            row for row in self.rows if review_row(row)[0] != "OK"
        ]
        self.review_count_var.set(f"{len(flagged_rows):,} flagged rows")
        for row in sorted(
            flagged_rows, key=lambda item: str(item.get("fullType", ""))
        ):
            status, reason = review_row(row)
            self.review_tree.insert("", "end", values=(
                row.get("fullType", ""),
                status,
                reason,
                row.get("category") or "Unclassified",
                row.get("primary") or "Unclassified",
                row.get("confidence", ""),
                row.get("source", ""),
                row.get("workshopMod", ""),
                ", ".join(row.get("expandedTags") or row.get("tags") or []),
            ))
        counts = self.summary["mods_with_items"]
        for mod in self.summary["mods"]:
            self.mod_tree.insert("", "end", values=(
                mod["id"],
                mod["name"],
                mod["workshop_id"],
                mod["script_version"],
                counts.get(mod["id"], 0),
                mod["source"],
            ))
