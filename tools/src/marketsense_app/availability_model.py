"""Evidence-based item availability detection for the offline PZ harness.

An item script block only proves that Project Zomboid knows about an item.  It
does not prove that the item can enter a normal game.  This module indexes the
authoritative acquisition tables shipped by the game and by selected Workshop
mods, then keeps the decision explainable for the GUI and JSON reports.
"""

from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass, field
import os
from pathlib import Path
import re
from typing import Any, Iterable

from .models import ItemDefinition
from .script_parser import strip_comments
from .workshop_paths import pz_version_int


AVAILABILITY_FILTERS = ("obtainable", "all", "uncertain", "excluded")
CHANNEL_LABELS = {
    "loot": "loot/distribution",
    "craft": "crafting recipe output",
    "evolved_recipe": "evolved recipe output",
    "forage": "foraging",
    "farming": "farming/harvest",
    "fishing": "fishing catch",
    "trapping": "trapping catch",
    "animal": "animal/butchering output",
    "scripted": "scripted game spawn/output",
}

FULL_TYPE_RE = re.compile(r"(?<![\w&-])[A-Za-z][\w&-]*\.[A-Za-z0-9_][\w]*")
QUOTED_STRING_RE = re.compile(r"[\"']([A-Za-z0-9_][\w]*)[\"']")
RECIPE_BLOCK_RE = re.compile(
    r"\b(?:craftRecipe|recipe|evolvedrecipe)\s+[^\s{}]+\s*\{", re.IGNORECASE
)
OUTPUT_BLOCK_RE = re.compile(r"\boutputs\s*\{", re.IGNORECASE)
MAPPER_BLOCK_RE = re.compile(r"\bitemMapper\s+[^\s{}]+\s*\{", re.IGNORECASE)
RESULT_ITEM_RE = re.compile(
    r"\bResultItem\s*=\s*([A-Za-z][\w&-]*\.[A-Za-z0-9_][\w]*)", re.IGNORECASE
)
RESULT_FIELD_RE = re.compile(
    r"\b(?:Result|result)\s*[:=]\s*([A-Za-z][\w&-]*\.[A-Za-z0-9_][\w]*)"
)


@dataclass
class AcquisitionEvidence:
    """Collected positive and negative evidence for one full item type."""

    channels: dict[str, list[str]] = field(default_factory=lambda: defaultdict(list))
    exclusions: list[str] = field(default_factory=list)
    loot_sources: set[str] = field(default_factory=set)
    loot_entry_count: int = 0
    loot_weighted_entry_count: int = 0
    loot_weight_sum: float = 0.0
    loot_relative_weighted_entry_count: int = 0
    loot_relative_weight_sum: float = 0.0

    def add(self, channel: str, reference: str) -> None:
        references = self.channels.setdefault(channel, [])
        if reference not in references and len(references) < 8:
            references.append(reference)

    def add_exclusion(self, signal: str) -> None:
        if signal not in self.exclusions:
            self.exclusions.append(signal)

    def add_loot(
        self,
        reference: str,
        weight: float | None = None,
        relative_weight: float | None = None,
    ) -> None:
        """Record one loot-table entry without treating it as global probability."""
        self.add("loot", reference)
        self.loot_entry_count += 1
        reference_text = str(reference or "")
        source = reference_text.split(":", 1)[0]
        if source:
            self.loot_sources.add(source)
        if weight is not None and weight >= 0:
            self.loot_weighted_entry_count += 1
            self.loot_weight_sum += float(weight)
        if relative_weight is not None and relative_weight >= 0:
            self.loot_relative_weighted_entry_count += 1
            self.loot_relative_weight_sum += float(relative_weight)

    def loot_rarity(self) -> tuple[str, str, float]:
        """Return a conservative rarity bucket derived from loot presence."""
        if self.loot_entry_count <= 0:
            return "Common", "fallback_default", 0.20 if self.channels else 0.05

        source_count = len(self.loot_sources)
        entries = self.loot_entry_count
        relative_count = self.loot_relative_weighted_entry_count
        average_relative = (
            self.loot_relative_weight_sum / relative_count
            if relative_count else None
        )
        # A missing chance is evidence of presence, not evidence of rarity.
        # Keep the count-based Uncommon bucket in that case.
        rare_weight = average_relative is not None and average_relative <= 0.10
        uncommon_weight = average_relative is None or average_relative <= 0.25
        if entries <= 1 and source_count <= 1 and rare_weight:
            rarity = "Rare"
        elif entries <= 4 and source_count <= 2 and uncommon_weight:
            rarity = "Uncommon"
        else:
            rarity = "Common"
        confidence = min(0.96, 0.62 + 0.06 * min(source_count, 3)
                        + 0.03 * min(entries, 4))
        return rarity, "loot_distribution", confidence

    def loot_dict(self) -> dict[str, Any]:
        rarity, source, confidence = self.loot_rarity()
        return {
            "status": "observed" if self.loot_entry_count > 0 else "not_detected",
            "rarity": rarity,
            "source": source,
            "confidence": confidence,
            "sourceCount": len(self.loot_sources),
            "entryCount": self.loot_entry_count,
            "weightedEntryCount": self.loot_weighted_entry_count,
            "weightSum": round(self.loot_weight_sum, 4),
            "relativeWeight": round(self.loot_relative_weight_sum, 6),
            "averageRelativeWeight": (
                round(self.loot_relative_weight_sum / self.loot_relative_weighted_entry_count, 6)
                if self.loot_relative_weighted_entry_count else None
            ),
            "references": list(self.channels.get("loot", [])),
        }

    def status(self) -> str:
        if self.exclusions:
            return "excluded"
        return "obtainable" if self.channels else "uncertain"

    def confidence(self) -> float:
        if self.exclusions:
            return 1.0
        if not self.channels:
            return 0.0
        # Independent acquisition channels increase confidence, but this is
        # deliberately not presented as a game-spawn probability.
        return min(0.99, 0.78 + 0.07 * len(self.channels))

    def to_dict(self) -> dict[str, Any]:
        status = self.status()
        if self.exclusions:
            reason = "hard exclusion: " + "; ".join(self.exclusions)
        elif self.channels:
            labels = [CHANNEL_LABELS.get(channel, channel) for channel in sorted(self.channels)]
            reason = "authoritative acquisition evidence: " + ", ".join(labels)
        else:
            reason = "no authoritative acquisition source found in the scanned game/mod data"
        return {
            "status": status,
            "confidence": self.confidence(),
            "channels": sorted(self.channels),
            "channelLabels": [CHANNEL_LABELS.get(channel, channel) for channel in sorted(self.channels)],
            "references": [reference for channel in sorted(self.channels) for reference in self.channels[channel]],
            "evidence": {
                channel: list(self.channels[channel])
                for channel in sorted(self.channels)
            },
            "exclusions": list(self.exclusions),
            "reason": reason,
            "rarity": self.loot_rarity()[0],
            "raritySource": self.loot_rarity()[1],
            "rarityEvidence": self.loot_dict(),
        }


@dataclass
class AvailabilityIndex:
    """Index built from selected base-game and Workshop runtime source trees."""

    evidence: dict[str, AcquisitionEvidence]
    scanned_files: int
    source_roots: list[str]

    def record(self, definition: ItemDefinition) -> dict[str, Any]:
        item_evidence = self.evidence.setdefault(definition.full_type, AcquisitionEvidence())
        for signal in _exclusion_signals(definition):
            item_evidence.add_exclusion(signal)
        result = item_evidence.to_dict()
        result["fullType"] = definition.full_type
        return result

    def records(self, definitions: Iterable[ItemDefinition]) -> dict[str, dict[str, Any]]:
        return {
            definition.full_type: self.record(definition)
            for definition in definitions
        }


def normalize_availability_filter(value: str | None) -> str:
    value = (value or "obtainable").strip().casefold()
    aliases = {
        "obtainable only": "obtainable",
        "obtainable": "obtainable",
        "all items": "all",
        "all": "all",
        "uncertain only": "uncertain",
        "uncertain": "uncertain",
        "excluded only": "excluded",
        "excluded": "excluded",
    }
    return aliases.get(value, "obtainable")


def availability_matches(record: dict[str, Any], filter_name: str | None) -> bool:
    normalized = normalize_availability_filter(filter_name)
    return normalized == "all" or record.get("status") == normalized


def availability_counts(records: Iterable[dict[str, Any]]) -> dict[str, int]:
    counts = {status: 0 for status in ("obtainable", "uncertain", "excluded")}
    for record in records:
        status = str(record.get("status") or "uncertain")
        counts[status] = counts.get(status, 0) + 1
    return counts

def _exclusion_signals(definition: ItemDefinition) -> list[str]:
    signals: list[str] = []
    category = str(definition.props.get("displayCategory") or "").casefold()
    if category in {"hidden", "zeddmg", "debug", "internal"}:
        signals.append(f"display category {definition.props.get('displayCategory')}")
    full_type = definition.full_type.casefold()
    if re.search(r"(?:^|\.)(?:zeddmg_|wound_|bandage_)", full_type):
        signals.append("internal damage/wound overlay item name")
    if re.search(r"debug|dummy|placeholder", full_type):
        signals.append("debug/dummy/placeholder item name")
    if "temporary_testing" in definition.script_path.casefold():
        signals.append("temporary testing script path")
    for key, value in definition.props.items():
        key_lower = str(key).casefold()
        if key_lower in {"hidden", "obsolete", "debug", "test", "nospawn", "noloot", "nodrop", "internal"}:
            if value is True or str(value).casefold() in {"true", "yes", "1"}:
                signals.append(f"{key}=true")
        if key_lower in {"tooltip", "description", "displayname"}:
            text = str(value).casefold()
            if "dummy item" in text or "do not spawn" in text or "do not use" in text:
                signals.append(f"{key} explicitly says not to spawn/use")
    return signals
