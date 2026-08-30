"""GUI settings, scope selection, and preference behavior."""

from __future__ import annotations

import os
from pathlib import Path
from typing import Any

from .config import DEFAULT_CACHE_DIR, DEFAULT_GAME_VERSION
from .evaluation import ScanOptions, load_cached_result
from .preferences import load_preferences, normalize_preferences, save_preferences
from .scan_scope import category_scope_label, normalize_category_filter
from .workshop import discover_mods
from .workshop_paths import default_roots
from .gui_controller_support import ALL_MODS_LABEL

class SettingsControllerMixin:
    """Own one GUI controller concern behind the stable composite mixin."""

    def _build_mods(self) -> None:
        frame = self.ttk.Frame(self.notebook, padding=8)
        self.notebook.add(frame, text="Workshop mods")
        self.mod_tree = self._tree(frame, [
            ("id", 180), ("name", 260), ("workshop", 110),
            ("version", 110), ("items", 80), ("source", 90),
        ])

    def _browse_workshop(self) -> None:
        selected = self.filedialog.askdirectory(
            title="Select a Steam Workshop root"
        )
        if selected:
            self.workshop_var.set(selected)
            self._refresh_mod_filter_choices()
            self._persist_preferences()

    def _browse_game_root(self) -> None:
        selected = self.filedialog.askdirectory(
            title="Select Project Zomboid media/scripts or install root"
        )
        if selected:
            self.game_root_var.set(selected)
            self._game_root_is_auto = False
            self._persist_preferences()

    def _mark_game_root_explicit(self) -> None:
        if self._auto_game_root is None:
            return
        current = self.game_root_var.get().strip()
        self._game_root_is_auto = bool(
            current
            and Path(current).expanduser().resolve() == self._auto_game_root
        )
    def _workshop_roots(self) -> tuple[Path, ...]:
        raw_roots = self.workshop_var.get().strip()
        if not raw_roots:
            return tuple(default_roots())
        return tuple(
            Path(part.strip()).expanduser()
            for part in raw_roots.split(os.pathsep)
            if part.strip()
        )
    def _selected_mod_filters(self) -> tuple[str, ...]:
        return tuple(self.mod_filter_options.get(
            self.mod_filter_var.get(), self.initial_mod_filters
        ))

    def _configured_mod_filters(self, args: Any) -> list[str]:
        """Resolve legacy CLI filters before the metadata view is populated."""
        configured = getattr(args, "mod", None)
        if configured:
            return [
                str(value).strip()
                for value in configured
                if str(value).strip()
            ]
        return [
            value.strip()
            for value in str(self.preferences.get("modFilters") or "").split(",")
            if value.strip()
        ]

    def _category_filter(self) -> str:
        return normalize_category_filter(self.category_scope_var.get())

    def _on_category_scope_selected(self) -> None:
        """Explain that category is a scan scope, not a local view filter."""

        if not hasattr(self, "status_var"):
            return
        selected = category_scope_label(self.category_scope_var.get())
        if not self.master_summary:
            self.status_var.set(
                f"{selected} selected; choose Scan selected scope / cache to build it."
            )
            return
        current = category_scope_label(self.master_summary.get("category_filter"))
        if current == selected:
            self._set_view_status()
            return
        self.status_var.set(
            f"Scan scope changed from {current} to {selected}; choose "
            "Scan selected scope / cache to rebuild the result."
        )

    def _mod_filter_label(self, mod: Any, duplicate: bool = False) -> str:
        name = str(mod.name or mod.mod_id or mod.root.name).strip()
        mod_id = str(mod.mod_id or mod.root.name).strip()
        label = f"{name} [{mod_id}]"
        if duplicate:
            label += f" ({mod.workshop_id})"
        return label

    def _refresh_mod_filter_choices(self) -> None:
        if not hasattr(self, "mod_filter_combo"):
            return
        current_label = self.mod_filter_var.get()
        current_terms = self.mod_filter_options.get(
            current_label, self.initial_mod_filters
        )
        try:
            mods = discover_mods(self._workshop_roots())
        except OSError:
            mods = []
        sorted_mods = sorted(
            mods,
            key=lambda mod: (
                str(mod.name or mod.mod_id).casefold(),
                str(mod.mod_id).casefold(),
                str(mod.workshop_id),
            ),
        )
        labels: dict[str, tuple[str, ...]] = {ALL_MODS_LABEL: ()}
        label_counts: dict[str, int] = {}
        for mod in sorted_mods:
            base_label = self._mod_filter_label(mod)
            duplicate_number = label_counts.get(base_label, 0)
            label_counts[base_label] = duplicate_number + 1
            label = (
                base_label
                if duplicate_number == 0
                else self._mod_filter_label(mod, duplicate=True)
            )
            suffix_number = duplicate_number + 1
            while label in labels:
                label = f"{base_label} ({mod.workshop_id}) #{suffix_number}"
                suffix_number += 1
            labels[label] = (str(mod.mod_id),)
        # A legacy CLI/preference filter may be a substring or multiple terms.
        # Preserve it as a visible custom choice until the user chooses a
        # discovered mod or All.
        selected = next(
            (label for label, terms in labels.items() if terms == current_terms),
            None,
        )
        if current_terms and selected is None:
            selected = f"Custom: {', '.join(current_terms)}"
            labels[selected] = tuple(current_terms)
        selected = selected or ALL_MODS_LABEL
        self.mod_filter_options = labels
        self.mod_filter_combo.configure(values=tuple(labels))
        self.mod_filter_var.set(selected)
        self.mod_filter_count_var.set(f"{len(mods):,} mods detected")

    def _on_mod_filter_selected(self) -> None:
        if not hasattr(self, "status_var"):
            return
        selection = self.mod_filter_var.get() or ALL_MODS_LABEL
        if not self.master_summary:
            if selection == ALL_MODS_LABEL:
                self.status_var.set(
                    "All detected Workshop mods selected; choose Scan selected scope / cache once."
                )
            else:
                self.status_var.set(
                    f"{selection} selected; choose Scan selected scope / cache once to build the cache."
                )
        else:
            self._apply_view_filters()

    def _preference_payload(self) -> dict[str, Any]:
        roots = [str(path) for path in self._workshop_roots()]
        try:
            max_items = max(0, int(self.max_items_var.get().strip() or 0))
        except ValueError:
            max_items = 0
        availability = {
            "Obtainable only": "obtainable",
            "All items": "all",
            "Uncertain only": "uncertain",
            "Excluded only": "excluded",
            "Changed only": "changed",
            "Blacklisted only": "blacklisted",
            "Whitelisted only": "whitelisted",
            "Overridden only": "overridden",
        }.get(self.availability_var.get(), "obtainable")
        return {
            "workshopRoots": roots,
            "gameRoot": "" if self._game_root_is_auto else self.game_root_var.get().strip(),
            "sandboxConfig": str(self.sandbox_path),
            "modFilters": ", ".join(self._selected_mod_filters()),
            "categoryFilter": self._category_filter(),
            "gameVersion": self.version_var.get().strip(),
            "maxItems": max_items,
            "skipVanilla": self.no_base_var.get(),
            "useCache": self.use_cache_var.get(),
            "refreshCache": False,
            "availability": availability,
            "itemColumns": (
                self._item_column_preferences()
                if hasattr(self, "_item_column_preferences")
                else {}
            ),
        }

    def _persist_preferences(self) -> None:
        try:
            saved = save_preferences(
                self.preferences_path, self._preference_payload()
            )
        except OSError as error:
            self._write_log(f"Could not save inspector settings: {error}")
            return
        if saved:
            self.preferences = normalize_preferences(self._preference_payload())

    def _queue_save_preferences(self) -> None:
        if self._preferences_after_id is not None:
            try:
                self.root.after_cancel(self._preferences_after_id)
            except (RuntimeError, self.tk.TclError):
                pass
        self._preferences_after_id = self.root.after(
            350, self._persist_preferences
        )

    def _queue_mod_filter_refresh(self) -> None:
        if self._mod_filter_after_id is not None:
            try:
                self.root.after_cancel(self._mod_filter_after_id)
            except (RuntimeError, self.tk.TclError):
                pass
        self._mod_filter_after_id = self.root.after(
            350, self._refresh_mod_filter_choices
        )

    def _queue_view_filter_refresh(self) -> None:
        """Debounce max-item typing while keeping all other view changes instant."""

        if not self.master_summary:
            return
        if self._view_filter_after_id is not None:
            try:
                self.root.after_cancel(self._view_filter_after_id)
            except (RuntimeError, self.tk.TclError):
                pass
        self._view_filter_after_id = self.root.after(
            180, self._apply_view_filters
        )

    def _close(self) -> None:
        if self._preferences_after_id is not None:
            try:
                self.root.after_cancel(self._preferences_after_id)
            except (RuntimeError, self.tk.TclError):
                pass
        if self._mod_filter_after_id is not None:
            try:
                self.root.after_cancel(self._mod_filter_after_id)
            except (RuntimeError, self.tk.TclError):
                pass
        if self._view_filter_after_id is not None:
            try:
                self.root.after_cancel(self._view_filter_after_id)
            except (RuntimeError, self.tk.TclError):
                pass
        self._persist_preferences()
        self.root.destroy()

    def _restore_cached_result(self) -> None:
        if self.busy or not self.use_cache_var.get():
            if not self.use_cache_var.get():
                self.status_var.set(
                    "Cache disabled — choose Scan selected scope / cache to evaluate."
                )
            return
        try:
            options = self._options()
        except ValueError as error:
            self.status_var.set(f"Saved settings need attention: {error}")
            return
        if options.refresh_cache:
            self.status_var.set(
                "Refresh enabled — choose Scan selected scope / cache to rebuild the cache."
            )
            return
        self._start("load-cache", options)

    def _options(self) -> ScanOptions:
        confidence_threshold = self._confidence_threshold()
        game_root = self.game_root_var.get().strip()
        # Category is an evaluator scope. Availability, Workshop mod, vanilla
        # visibility, and Max items remain local view filters over that scope.
        return ScanOptions(
            workshop_roots=self._workshop_roots(),
            filters=(),
            game_version=self.version_var.get().strip() or DEFAULT_GAME_VERSION,
            game_root=(
                None
                if self._game_root_is_auto
                else Path(game_root).expanduser() if game_root else None
            ),
            no_base_game=False,
            max_items=0,
            cache_dir=self.args.cache_dir or DEFAULT_CACHE_DIR,
            use_cache=self.use_cache_var.get(),
            refresh_cache=self.refresh_cache_var.get(),
            confidence_threshold=confidence_threshold,
            sandbox_options=dict(self.sandbox_overrides),
            availability_filter="all",
            category_filter=self._category_filter(),
        )
