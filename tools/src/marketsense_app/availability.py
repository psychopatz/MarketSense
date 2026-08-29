"""Evidence-based item availability detection for the offline PZ harness.

An item script block only proves that Project Zomboid knows about an item.  It
does not prove that the item can enter a normal game.  This module indexes the
authoritative acquisition tables shipped by the game and by selected Workshop
mods, then keeps the decision explainable for the GUI and JSON reports.
"""

from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass, field
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

    def add(self, channel: str, reference: str) -> None:
        references = self.channels.setdefault(channel, [])
        if reference not in references and len(references) < 8:
            references.append(reference)

    def add_exclusion(self, signal: str) -> None:
        if signal not in self.exclusions:
            self.exclusions.append(signal)

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


def build_acquisition_index(
    definitions: Iterable[ItemDefinition],
    base_scripts_root: Path | None,
    mod_roots: Iterable[Path],
    game_version: str | None,
) -> AvailabilityIndex:
    """Scan acquisition definitions for all known item types.

    The candidate name map is created from the complete merged item universe,
    while the selected ``max_items`` subset is only applied later.  This keeps
    an item from being misclassified merely because another item was outside a
    small test batch.
    """

    definitions = list(definitions)
    known_types = {definition.full_type for definition in definitions}
    names: dict[str, set[str]] = defaultdict(set)
    for full_type in known_types:
        if "." in full_type:
            names[full_type.split(".", 1)[1]].add(full_type)

    evidence: dict[str, AcquisitionEvidence] = {
        full_type: AcquisitionEvidence() for full_type in known_types
    }
    source_specs: list[tuple[str, Path, str | None]] = []
    seen_media: set[Path] = set()
    if base_scripts_root and base_scripts_root.is_dir():
        media_root = base_scripts_root.resolve().parent
        source_specs.append(("base", media_root, "Base"))
        seen_media.add(media_root)
    for root in mod_roots:
        for media_root in _selected_media_roots(root, game_version):
            media_root = media_root.resolve()
            if media_root in seen_media:
                continue
            seen_media.add(media_root)
            source_specs.append((root.name, media_root, None))

    scanned_files = 0
    for source_label, media_root, preferred_module in source_specs:
        for path in _runtime_source_files(media_root):
            scanned_files += 1
            _scan_source_file(
                path,
                media_root,
                source_label,
                preferred_module,
                known_types,
                names,
                evidence,
            )
    return AvailabilityIndex(
        evidence=evidence,
        scanned_files=scanned_files,
        source_roots=[str(media_root) for _, media_root, _ in source_specs],
    )


def _selected_media_roots(mod_root: Path, game_version: str | None) -> list[Path]:
    """Mirror the Workshop common + highest-compatible media selection."""

    mod_root = mod_root.expanduser().resolve()
    direct = mod_root / "media"
    if direct.is_dir():
        return [direct]
    selected: list[Path] = []
    common = mod_root / "common" / "media"
    if common.is_dir():
        selected.append(common)
    target = pz_version_int(game_version) if game_version else None
    compatible = [
        path for path in mod_root.iterdir() if path.is_dir()
        and pz_version_int(path.name) > 0
        and (path / "media").is_dir()
        and (target is None or pz_version_int(path.name) <= target)
    ] if mod_root.is_dir() else []
    if compatible:
        chosen = max(compatible, key=lambda path: (pz_version_int(path.name), path.name))
        selected.append(chosen / "media")
    return selected


def _runtime_source_files(media_root: Path) -> list[Path]:
    paths: list[Path] = []
    seen: set[Path] = set()
    for source_root in (media_root / "scripts", media_root / "lua"):
        if not source_root.is_dir():
            continue
        for path in source_root.rglob("*"):
            if path.suffix.casefold() not in {".lua", ".txt"}:
                continue
            if source_root.name.casefold() == "lua":
                relative_parts = {
                    part.casefold() for part in path.relative_to(source_root).parts[:-1]
                }
                if "client" in relative_parts:
                    continue
            resolved = path.resolve()
            if resolved not in seen:
                seen.add(resolved)
                paths.append(resolved)
    return sorted(paths)


def _scan_source_file(
    path: Path,
    media_root: Path,
    source_label: str,
    preferred_module: str | None,
    known_types: set[str],
    names: dict[str, set[str]],
    evidence: dict[str, AcquisitionEvidence],
) -> None:
    try:
        source = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return
    relative = str(path.relative_to(media_root)).replace("\\", "/")
    masked = _mask_comments(source) if path.suffix.casefold() == ".lua" else strip_comments(source)
    kind = _source_kind(relative, masked)
    if kind == "loot":
        _scan_loot(masked, path, media_root, source_label, known_types, names, evidence)
    elif kind == "recipe":
        _scan_recipes(masked, path, media_root, source_label, known_types, evidence)
    elif kind in {"forage", "farming", "fishing", "trapping", "animal"}:
        _scan_specialized(
            masked, path, media_root, source_label, kind,
            known_types, names, preferred_module, evidence,
        )
    elif kind == "scripted":
        _scan_scripted(
            masked, path, media_root, source_label, preferred_module,
            known_types, names, evidence,
        )


def _source_kind(relative: str, source: str) -> str | None:
    low = relative.casefold()
    name = Path(relative).name.casefold()
    if (
        name in {"proceduraldistributions.lua", "suburbsdistributions.lua", "vehicledistributions.lua"}
        or name.startswith("distribution_")
        or name.startswith("vehicledistribution_")
    ):
        return "loot"
    if "/recipes/" in low or name == "evolvedrecipes.txt" or "craftrecipe" in source.casefold():
        return "recipe"
    if "/foraging/" in low:
        return "forage"
    if "/fishing/" in low:
        return "fishing"
    if "/traps/" in low:
        return "trapping"
    if "/farming/" in low:
        return "farming"
    if "/definitions/animal/" in low or "/animal/" in low or "butcher" in low:
        return "animal"
    is_lua_path = low.startswith("lua/") or "/lua/" in low
    if low.startswith("lua/client/") or "/lua/client/" in low:
        return None
    if is_lua_path and re.search(
        r"\b(?:addItem|createItem|instanceItem|spawnItem|harvest|result|output|drop)\b",
        source,
        re.IGNORECASE,
    ):
        return "scripted"
    return None


def _scan_loot(
    source: str,
    path: Path,
    media_root: Path,
    source_label: str,
    known_types: set[str],
    names: dict[str, set[str]],
    evidence: dict[str, AcquisitionEvidence],
) -> None:
    for match in FULL_TYPE_RE.finditer(source):
        full_type = match.group(0)
        if full_type in known_types:
            _add(evidence, full_type, "loot", _reference(path, media_root, source_label, source, match.start()))
    # PZ's distribution tables use module-less strings such as "CannedLeek".
    # Only quoted strings are accepted here; table keys and prose are not loot.
    for match in QUOTED_STRING_RE.finditer(source):
        token = match.group(1)
        for full_type in _candidate_names(token, names, "base" if source_label == "base" else None):
            _add(evidence, full_type, "loot", _reference(path, media_root, source_label, source, match.start()))


def _scan_recipes(
    source: str,
    path: Path,
    media_root: Path,
    source_label: str,
    known_types: set[str],
    evidence: dict[str, AcquisitionEvidence],
) -> None:
    for block_match in RECIPE_BLOCK_RE.finditer(source):
        body_start = block_match.end()
        body_end = _matching_brace(source, body_start - 1)
        if body_end is None:
            continue
        body = source[body_start:body_end]
        for output_match in OUTPUT_BLOCK_RE.finditer(body):
            output_start = body_start + output_match.end()
            output_end = _matching_brace(source, output_start - 1)
            if output_end is None:
                continue
            for item_match in FULL_TYPE_RE.finditer(source[output_start:output_end]):
                full_type = item_match.group(0)
                if full_type in known_types:
                    absolute = output_start + item_match.start()
                    _add(evidence, full_type, "craft", _reference(path, media_root, source_label, source, absolute))
        for mapper_match in MAPPER_BLOCK_RE.finditer(body):
            mapper_start = body_start + mapper_match.end()
            mapper_end = _matching_brace(source, mapper_start - 1)
            if mapper_end is None:
                continue
            mapper = source[mapper_start:mapper_end]
            for output_match in FULL_TYPE_RE.finditer(mapper):
                # Mapper keys are on the left side of an equals sign.  The
                # right side is an input and must not make an item craftable.
                tail = mapper[output_match.end():]
                if re.match(r"\s*=", tail):
                    full_type = output_match.group(0)
                    if full_type in known_types:
                        absolute = mapper_start + output_match.start()
                        _add(evidence, full_type, "craft", _reference(path, media_root, source_label, source, absolute))
        for result_match in RESULT_ITEM_RE.finditer(body):
            full_type = result_match.group(1)
            if full_type in known_types:
                absolute = body_start + result_match.start(1)
                _add(evidence, full_type, "evolved_recipe", _reference(path, media_root, source_label, source, absolute))
        for result_match in RESULT_FIELD_RE.finditer(body):
            full_type = result_match.group(1)
            if full_type in known_types:
                absolute = body_start + result_match.start(1)
                _add(evidence, full_type, "craft", _reference(path, media_root, source_label, source, absolute))


def _scan_specialized(
    source: str,
    path: Path,
    media_root: Path,
    source_label: str,
    kind: str,
    known_types: set[str],
    names: dict[str, set[str]],
    preferred_module: str | None,
    evidence: dict[str, AcquisitionEvidence],
) -> None:
    for line_start, line in _lines_with_offsets(source):
        if kind == "forage":
            relevant = True
        elif kind == "fishing":
            relevant = bool(re.search(r"FishConfig:new|trashItems|fishNet", line, re.IGNORECASE))
        elif kind == "farming":
            relevant = bool(re.search(
                r"vegetableName|seedName|seedTypes|produceExtra|harvest|produce|output",
                line,
                re.IGNORECASE,
            ))
        else:
            relevant = bool(re.search(
                r"parts|bones|feather|head|skull|leather|carcass|dung|egg|milk|wool|"
                r"luredPossibleItems|\bitem\s*=",
                line,
                re.IGNORECASE,
            ))
        if not relevant:
            continue
        for match in FULL_TYPE_RE.finditer(line):
            full_type = match.group(0)
            if full_type in known_types:
                _add(evidence, full_type, kind, _reference(path, media_root, source_label, source, line_start + match.start()))
        if kind in {"farming", "trapping", "animal"}:
            for match in QUOTED_STRING_RE.finditer(line):
                for full_type in _candidate_names(match.group(1), names, preferred_module):
                    _add(evidence, full_type, kind, _reference(path, media_root, source_label, source, line_start + match.start()))


def _scan_scripted(
    source: str,
    path: Path,
    media_root: Path,
    source_label: str,
    preferred_module: str | None,
    known_types: set[str],
    names: dict[str, set[str]],
    evidence: dict[str, AcquisitionEvidence],
) -> None:
    for line_start, line in _lines_with_offsets(source):
        if not re.search(
            r"\b(?:addItem|createItem|instanceItem|spawnItem|harvest|result|output|drop|itemType)\b",
            line,
            re.IGNORECASE,
        ):
            continue
        for match in FULL_TYPE_RE.finditer(line):
            full_type = match.group(0)
            if full_type in known_types:
                _add(evidence, full_type, "scripted", _reference(path, media_root, source_label, source, line_start + match.start()))
        # A number of PZ Lua APIs accept a module-less item name.  Restrict
        # this fallback to output-like lines so ordinary prose/identifiers do
        # not become false acquisition evidence.
        for match in QUOTED_STRING_RE.finditer(line):
            for full_type in _candidate_names(match.group(1), names, preferred_module):
                _add(evidence, full_type, "scripted", _reference(path, media_root, source_label, source, line_start + match.start()))


def _candidate_names(
    token: str,
    names: dict[str, set[str]],
    preferred_module: str | None,
) -> list[str]:
    candidates = sorted(names.get(token, ()))
    if preferred_module:
        preferred = [full_type for full_type in candidates if full_type.startswith(preferred_module + ".")]
        if preferred:
            return preferred
    # An unqualified Workshop reference is only safe when it resolves to one
    # item.  Base loot is special: PZ's built-in distribution tables resolve
    # module-less names in Base.
    if len(candidates) == 1:
        return candidates
    base_candidates = [full_type for full_type in candidates if full_type.startswith("Base.")]
    return base_candidates if len(base_candidates) == 1 else []


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


def _add(evidence: dict[str, AcquisitionEvidence], full_type: str, channel: str, reference: str) -> None:
    evidence.setdefault(full_type, AcquisitionEvidence()).add(channel, reference)


def _reference(path: Path, media_root: Path, source_label: str, source: str, offset: int) -> str:
    relative = str(path.relative_to(media_root)).replace("\\", "/")
    return f"{source_label}/{relative}:{source.count(chr(10), 0, offset) + 1}"


def _lines_with_offsets(source: str) -> Iterable[tuple[int, str]]:
    offset = 0
    for line in source.splitlines(keepends=True):
        yield offset, line
        offset += len(line)


def _matching_brace(source: str, opening: int) -> int | None:
    depth = 0
    quote = ""
    index = opening
    while index < len(source):
        char = source[index]
        if quote:
            if char == "\\":
                index += 2
                continue
            if char == quote:
                quote = ""
        elif char in "\"'":
            quote = char
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return index
        index += 1
    return None


def _mask_comments(source: str) -> str:
    """Mask Lua line/block comments while preserving offsets and newlines."""
    chars = list(source)
    index = 0
    quote = ""
    while index < len(chars):
        char = chars[index]
        next_char = chars[index + 1] if index + 1 < len(chars) else ""
        if quote:
            if char == "\\":
                index += 2
                continue
            if char == quote:
                quote = ""
            index += 1
            continue
        if char in "\"'":
            quote = char
            index += 1
            continue
        if char == "-" and next_char == "-":
            block = index + 2 < len(chars) and chars[index + 2] == "["
            chars[index] = chars[index + 1] = " "
            index += 2
            if block:
                while index < len(chars):
                    if chars[index] == "]" and index + 1 < len(chars) and chars[index + 1] == "]":
                        chars[index] = chars[index + 1] = " "
                        index += 2
                        break
                    if chars[index] != "\n":
                        chars[index] = " "
                    index += 1
            else:
                while index < len(chars) and chars[index] != "\n":
                    chars[index] = " "
                    index += 1
            continue
        index += 1
    return "".join(chars)
