"""Parser for the item-script subset needed by MarketSense."""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any, Iterator

from .models import ItemDefinition, WorkshopMod
from .script_fields import FIELD_ALIASES, NUMBER_FIELDS


def strip_comments(source: str) -> str:
    """Mask comments while preserving line and character offsets."""
    output: list[str] = []
    index = 0
    quote = ""
    block_comment = False
    while index < len(source):
        char = source[index]
        next_char = source[index + 1] if index + 1 < len(source) else ""
        if block_comment:
            if char == "*" and next_char == "/":
                output.extend("  ")
                index += 2
                block_comment = False
            else:
                output.append("\n" if char == "\n" else " ")
                index += 1
            continue
        if quote:
            output.append(char)
            if char == "\\" and index + 1 < len(source):
                output.append(source[index + 1])
                index += 2
                continue
            if char == quote:
                quote = ""
            index += 1
            continue
        if char in "\"'":
            quote = char
            output.append(char)
            index += 1
        elif char == "/" and next_char == "*":
            output.extend("  ")
            index += 2
            block_comment = True
        elif char == "/" and next_char == "/":
            output.extend("  ")
            index += 2
            while index < len(source) and source[index] != "\n":
                output.append(" ")
                index += 1
        else:
            output.append(char)
            index += 1
    return "".join(output)


def matching_brace(source: str, opening: int) -> int | None:
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


def named_blocks(source: str, keyword: str) -> Iterator[tuple[str, str]]:
    pattern = re.compile(rf"\b{re.escape(keyword)}\s+([^\s{{}}]+)\s*\{{", re.IGNORECASE)
    for match in pattern.finditer(source):
        closing = matching_brace(source, match.end() - 1)
        if closing is not None:
            yield match.group(1).strip(), source[match.end():closing]


def clean_value(value: str) -> str:
    value = value.strip()
    while value.endswith(","):
        value = value[:-1].rstrip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        value = value[1:-1]
    return value.strip()


def parse_properties(body: str) -> dict[str, str]:
    result: dict[str, str] = {}
    depth = 0
    for line in body.splitlines():
        if depth == 0:
            match = re.match(r"\s*([A-Za-z_][\w]*)\s*=\s*(.*?)\s*$", line)
            if match:
                result[match.group(1)] = clean_value(match.group(2))
        depth += line.count("{") - line.count("}")
        depth = max(depth, 0)
    return result


def parse_bool(value: str) -> bool | None:
    lowered = value.casefold()
    if lowered in {"true", "yes", "1"}:
        return True
    if lowered in {"false", "no", "0"}:
        return False
    return None


def normalize_properties(raw: dict[str, str]) -> dict[str, Any]:
    props: dict[str, Any] = {}
    for raw_key, raw_value in raw.items():
        key = FIELD_ALIASES.get(raw_key.casefold(), raw_key)
        value: Any = raw_value
        if key in NUMBER_FIELDS:
            try:
                value = float(raw_value)
                if value.is_integer():
                    value = int(value)
            except ValueError:
                pass
        elif key not in {"displayName", "tooltip", "description", "tags"}:
            boolean = parse_bool(raw_value)
            if boolean is not None:
                value = boolean
        if key == "tags":
            value = [part.strip() for part in re.split(r"[;,]", raw_value) if part.strip()]
        props[key] = value
    return props


def parse_script(path: Path, mod: WorkshopMod) -> list[ItemDefinition]:
    try:
        source = strip_comments(path.read_text(encoding="utf-8", errors="replace"))
    except OSError:
        return []
    definitions: list[ItemDefinition] = []
    for module, module_body in named_blocks(source, "module"):
        for item_name, item_body in named_blocks(module_body, "item"):
            if not item_name or "." in item_name:
                continue
            definitions.append(ItemDefinition(
                full_type=f"{module}.{item_name}",
                module=module,
                props=normalize_properties(parse_properties(item_body)),
                mod=mod,
                script_path=str(path),
            ))
    return definitions


def parse_info(path: Path) -> dict[str, str]:
    info: dict[str, str] = {}
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return info
    for line in lines:
        if "=" not in line or line.lstrip().startswith("#"):
            continue
        key, value = line.split("=", 1)
        info[key.strip().casefold()] = clean_value(value)
    return info


def mod_from_root(root: Path, workshop_id: str, source_kind: str) -> WorkshopMod:
    info_paths = sorted(root.rglob("mod.info"), key=lambda path: (len(path.parts), str(path)))
    info = parse_info(info_paths[0]) if info_paths else {}
    return WorkshopMod(
        root=root,
        workshop_id=workshop_id,
        mod_id=info.get("id") or root.name,
        name=info.get("name") or root.name,
        source_kind=source_kind,
    )
