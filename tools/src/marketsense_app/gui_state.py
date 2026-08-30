"""Mutable model state shared by the MarketSense GUI controller and views."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


@dataclass
class GuiState:
    """State that is not itself a Tk widget or a controller operation.

    The legacy attribute names remain exposed by ``MarketSenseGui`` as a
    compatibility facade, but the storage has one explicit owner. This keeps
    view mixins from accidentally creating a second copy of scan state.
    """

    busy: bool = False
    summary: dict[str, Any] | None = None
    rows: list[dict[str, Any]] = field(default_factory=list)
    master_summary: dict[str, Any] | None = None
    master_rows: list[dict[str, Any]] = field(default_factory=list)
    preferences_path: Path | None = None
    preferences: dict[str, Any] = field(default_factory=dict)
    preferences_after_id: str | None = None
    mod_filter_after_id: str | None = None
    view_filter_after_id: str | None = None
