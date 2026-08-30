"""Pure item metadata helpers used by the GUI tree and details view."""

from __future__ import annotations

from typing import Any

_DESCRIPTOR_FIELDS = ("quality", "rarity", "theme", "origin")
_ITEM_COLUMN_SPECS = (
    ("price", 80),
    ("availability", 110),
    ("review", 90),
    ("rules", 180),
    ("metadata", 280),
    ("stock", 90),
    ("reason", 320),
    ("detector", 140),
    ("resolver", 160),
    ("yield", 240),
    ("confidence", 90),
    ("mod", 170),
    ("description", 300),
)
_ITEM_COLUMN_NAMES = tuple(name for name, _width in _ITEM_COLUMN_SPECS)

def category_metadata(row: dict[str, Any]) -> dict[str, str]:
    """Return descriptor metadata with a fallback for older cached rows."""

    metadata = row.get("metadata")
    tags: list[Any] = []
    for key in ("expandedTags", "tags"):
        value = row.get(key)
        if isinstance(value, (list, tuple)):
            tags.extend(value)
    result: dict[str, str] = {}
    for field in _DESCRIPTOR_FIELDS:
        value = row.get(field)
        if not value and isinstance(metadata, dict):
            value = metadata.get(field)
        if value:
            text = str(value)
            marker = f"{field.title()}."
            if text.startswith(marker):
                text = text[len(marker):]
            result[field] = text
            continue
        marker = f"{field.title()}."
        values = []
        for tag in tags:
            text = str(tag or "")
            if text.startswith(marker):
                descriptor = text[len(marker):]
                if descriptor and descriptor not in values:
                    values.append(descriptor)
        result[field] = ", ".join(values)
    return result


def metadata_label(row: dict[str, Any]) -> str:
    """Compact descriptor string suitable for the item tree."""

    metadata = category_metadata(row)
    return " · ".join(
        f"{field.title()}={metadata[field]}"
        for field in _DESCRIPTOR_FIELDS
        if metadata[field]
    )
