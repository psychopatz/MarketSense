"""Data contracts shared by discovery, evaluation, and reporting."""

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


@dataclass
class WorkshopMod:
    root: Path
    workshop_id: str
    mod_id: str
    name: str
    source_kind: str
    script_version: str = "direct"


@dataclass
class ItemDefinition:
    full_type: str
    module: str
    props: dict[str, Any]
    mod: WorkshopMod
    script_path: str
    sources: list[str] = field(default_factory=list)
