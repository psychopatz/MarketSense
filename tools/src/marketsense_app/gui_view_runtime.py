"""Runtime and preference initialization for the MarketSense GUI view."""

from __future__ import annotations

import os
from pathlib import Path
from typing import Any

from .config import DEFAULT_INSPECTOR_SETTINGS_PATH, DEFAULT_SANDBOX_SETTINGS_PATH
from .gui_controller import ALL_MODS_LABEL
from .preferences import load_preferences, normalize_preferences
from .sandbox import (
    SandboxSettingsError,
    load_sandbox_option_specs,
    load_sandbox_settings,
    sandbox_definition_audit,
)
from .scan_scope import category_scope_label
from .workshop_paths import default_roots, game_scripts_root


def initialize_runtime(
    view: Any,
    root: Any,
    tk: Any,
    ttk: Any,
    scrolledtext: Any,
    filedialog: Any,
    messagebox: Any,
    simpledialog: Any,
    args: Any,
) -> None:
    """Attach runtime dependencies and initialize view-owned settings."""
    view.root, view.tk, view.ttk = root, tk, ttk
    view.filedialog, view.messagebox = filedialog, messagebox
    view.simpledialog = simpledialog
    view.args = args
    view.scrolledtext = scrolledtext
    view.busy = False
    view.summary: dict[str, Any] | None = None
    view.rows: list[dict[str, Any]] = []
    view.master_summary: dict[str, Any] | None = None
    view.master_rows: list[dict[str, Any]] = []

    view.preferences_path = Path(
        getattr(args, "settings_config", None)
        or DEFAULT_INSPECTOR_SETTINGS_PATH
    ).expanduser()
    view.preferences = normalize_preferences(
        load_preferences(view.preferences_path)
    )
    view._preferences_after_id: str | None = None
    view._mod_filter_after_id: str | None = None
    view._view_filter_after_id: str | None = None

    root.title(
        f"MarketSense Inspector — Project Zomboid "
        f"{getattr(args, 'game_version', '42.20')}"
    )
    root.geometry("1280x860")
    root.minsize(980, 680)
    root.columnconfigure(0, weight=1)
    root.rowconfigure(1, weight=1)

    configured_roots = getattr(args, "workshop_root", None) or [
        Path(value) for value in view.preferences.get("workshopRoots", [])
    ] or default_roots()
    configured_game_root = (
        getattr(args, "game_root", None)
        or view.preferences.get("gameRoot")
        or game_scripts_root(None)
    )
    auto_game_root = game_scripts_root(None)
    configured_game_root_text = str(configured_game_root or "")
    view._auto_game_root = auto_game_root
    view._game_root_is_auto = (
        not getattr(args, "game_root", None)
        and bool(auto_game_root)
        and Path(configured_game_root_text).expanduser().resolve()
        == auto_game_root
    )

    configured_filters = view._configured_mod_filters(args)
    view.initial_mod_filters = tuple(configured_filters)
    view.mod_filter_options: dict[str, tuple[str, ...]] = {
        ALL_MODS_LABEL: ()
    }
    view.workshop_var = view.tk.StringVar(
        value=os.pathsep.join(str(path) for path in configured_roots)
    )
    # Leave this blank until the metadata pass maps legacy CLI/preferences
    # terms to a discovered label (or falls back to All).
    view.mod_filter_var = view.tk.StringVar(value="")
    view.mod_filter_count_var = view.tk.StringVar(value="0 mods detected")
    configured_category = (
        getattr(args, "category", None)
        or view.preferences.get("categoryFilter")
        or ""
    )
    view.category_scope_var = view.tk.StringVar(
        value=category_scope_label(configured_category)
    )
    view.version_var = view.tk.StringVar(
        value=str(
            view.preferences.get("gameVersion")
            or getattr(args, "game_version", "42.20")
        )
    )
    view.game_root_var = view.tk.StringVar(
        value=str(configured_game_root or "")
    )
    configured_max_items = (
        getattr(args, "max_items", 0)
        or view.preferences.get("maxItems")
        or 0
    )
    view.max_items_var = view.tk.StringVar(value=str(configured_max_items))
    view.no_base_var = view.tk.BooleanVar(
        value=bool(
            getattr(args, "no_base_game", False)
            or view.preferences.get("skipVanilla", False)
        )
    )
    view.use_cache_var = view.tk.BooleanVar(
        value=(
            not getattr(args, "no_cache", False)
            and bool(view.preferences.get("useCache", True))
        )
    )
    # Refresh is a one-shot rebuild control and is intentionally not
    # restored from the preferences file.
    view.refresh_cache_var = view.tk.BooleanVar(
        value=getattr(args, "refresh_cache", False)
    )
    availability_filter = getattr(args, "availability", "obtainable")
    availability_labels = {
        "obtainable": "Obtainable only",
        "all": "All items",
        "uncertain": "Uncertain only",
        "excluded": "Excluded only",
        "changed": "Changed only",
        "blacklisted": "Blacklisted only",
        "whitelisted": "Whitelisted only",
        "overridden": "Overridden only",
    }
    view.availability_var = view.tk.StringVar(
        value=availability_labels.get(
            str(
                view.preferences.get("availability")
                or availability_filter
            ),
            "Obtainable only",
        )
    )

    configured_sandbox = getattr(args, "sandbox_config", None)
    configured_sandbox_path = (
        Path(configured_sandbox).expanduser().resolve()
        if configured_sandbox else None
    )
    default_sandbox_path = DEFAULT_SANDBOX_SETTINGS_PATH.expanduser().resolve()
    view.sandbox_path = Path(
        configured_sandbox
        if configured_sandbox_path and configured_sandbox_path != default_sandbox_path
        else view.preferences.get("sandboxConfig")
        or configured_sandbox
        or DEFAULT_SANDBOX_SETTINGS_PATH
    ).expanduser()
    view.sandbox_specs = load_sandbox_option_specs(view.version_var.get())
    view.sandbox_spec_by_key = {
        spec.key: spec for spec in view.sandbox_specs
    }
    view.sandbox_audit = sandbox_definition_audit(view.version_var.get())
    view.sandbox_overrides: dict[str, int | float] = {}
    view.sandbox_settings_error = ""
    try:
        view.sandbox_overrides = load_sandbox_settings(
            view.sandbox_path, view.sandbox_specs
        )
    except SandboxSettingsError as error:
        view.sandbox_settings_error = str(error)
