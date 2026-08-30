"""Parse deterministic item-yield relationships from PZ craft recipes."""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any, Iterable

from .script_parser import matching_brace, named_blocks, strip_comments
from .workshop_paths import item_script_paths


ITEM_LINE_RE = re.compile(
    r"^\s*item\s+((?:[0-9]+(?:\.[0-9]+)?)|variable\[[^\]]+\])\s+"
    r"(\[[^\]]+\]|[^\s,]+)(.*)$",
    re.IGNORECASE,
)
CHANCE_RE = re.compile(r"(?:^|\s)chance:([0-9]+(?:\.[0-9]+)?)", re.IGNORECASE)
MAPPER_ENTRY_RE = re.compile(
    r"^\s*([^\s=,]+)\s*=\s*([^\s,]+)", re.IGNORECASE
)
YIELD_NAME_MARKERS = (
    "open", "unpack", "unbundle", "unstack", "unbox",
    "slice", "halve", "split", "separate", "smash",
)
RESOLUTION_PRIORITY = {
    "exact": 0,
    "probabilistic": 1,
    "ambiguous": 2,
    "unresolved": 3,
}


def _merge_resolution(current: str, candidate: str) -> str:
    if RESOLUTION_PRIORITY.get(candidate, 3) > RESOLUTION_PRIORITY.get(current, 0):
        return candidate
    return current


def _qualify(value: str, module: str) -> str:
    value = value.strip()
    if not value or value.startswith("mapper:") or "." in value:
        return value
    return f"{module}.{value}"


def _types(token: str, module: str) -> list[str]:
    token = token.strip()
    if token.startswith("[") and token.endswith("]"):
        token = token[1:-1]
    return [
        qualified for part in token.split(";")
        if (qualified := _qualify(part, module))
    ]


def _flags(tail: str) -> list[str]:
    match = re.search(r"flags\[([^\]]+)\]", tail, re.IGNORECASE)
    if match is None:
        return []
    return [part.strip() for part in match.group(1).split(";") if part.strip()]


def _item_lines(block: str, module: str) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for line in block.splitlines():
        match = ITEM_LINE_RE.match(line)
        if match is None:
            continue
        amount_token = match.group(1)
        variable = re.fullmatch(
            r"variable\[([^:]+):([^\]]+)\]", amount_token, re.IGNORECASE
        )
        amount: float | None
        maximum: float | None = None
        if variable is not None:
            try:
                amount = float(variable.group(1))
                maximum = float(variable.group(2))
            except ValueError:
                amount = None
        else:
            amount = float(amount_token)
        chance_match = CHANCE_RE.search(match.group(3))
        chance = float(chance_match.group(1)) if chance_match else 1.0
        chance = max(0.0, min(1.0, chance))
        result.append({
            "amount": amount,
            "maxAmount": maximum if maximum is not None else amount,
            "variableAmount": variable is not None and (
                maximum is None or maximum != amount
            ),
            "chance": chance,
            "types": _types(match.group(2), module),
            "flags": _flags(match.group(3)),
        })
    return result


def _nested_block(body: str, keyword: str) -> str:
    match = re.search(rf"\b{re.escape(keyword)}\s*\{{", body, re.IGNORECASE)
    if match is None:
        return ""
    closing = matching_brace(body, match.end() - 1)
    return body[match.end():closing] if closing is not None else ""


def _mapper_entries(body: str, module: str) -> dict[str, list[str]]:
    entries: dict[str, list[str]] = {}
    for _mapper_name, mapper_body in named_blocks(body, "itemMapper"):
        for line in mapper_body.splitlines():
            match = MAPPER_ENTRY_RE.match(line)
            if match is None:
                continue
            result_type = _qualify(match.group(1), module)
            input_types = _types(match.group(2), module)
            entries.setdefault(result_type, []).extend(input_types)
    return entries


def _name_hint(name: str) -> bool:
    lowered = name.casefold()
    return any(marker in lowered for marker in YIELD_NAME_MARKERS)


def _recipe_blocks(source: str) -> Iterable[tuple[str, str, str]]:
    """Yield ``(module, recipe name, body)`` for module and direct layouts."""
    found_module = False
    for module, module_body in named_blocks(source, "module"):
        found_module = True
        for name, body in named_blocks(module_body, "craftRecipe"):
            yield module, name, body
    if not found_module:
        for name, body in named_blocks(source, "craftRecipe"):
            yield "Base", name, body


def parse_recipe_script(path: Path) -> list[dict[str, Any]]:
    """Parse craftRecipe blocks without trying to emulate PZ crafting."""
    try:
        source = strip_comments(path.read_text(encoding="utf-8", errors="replace"))
    except OSError:
        return []

    result: list[dict[str, Any]] = []
    for module, name, body in _recipe_blocks(source):
        inputs = _item_lines(_nested_block(body, "inputs"), module)
        outputs = _item_lines(_nested_block(body, "outputs"), module)
        if not inputs or not outputs:
            continue
        mapper = _mapper_entries(body, module)
        result.append({
            "recipe": name,
            "module": module,
            "sourceFile": str(path),
            "inputs": inputs,
            "outputs": outputs,
            "mapper": mapper,
            "nameHint": _name_hint(name),
        })
    return result


def _resolve_outputs(
    recipe: dict[str, Any], source_full_type: str,
) -> tuple[list[dict[str, Any]], str]:
    mapper: dict[str, list[str]] = recipe.get("mapper") or {}
    resolved: list[dict[str, Any]] = []
    overall = "exact"
    for output in recipe.get("outputs") or []:
        output_types: list[str] = []
        flags = list(output.get("flags") or [])
        for output_type in output.get("types") or []:
            if output_type.startswith("mapper:"):
                matches = [
                    result_type for result_type, patterns in mapper.items()
                    if source_full_type.casefold() in {
                        value.casefold() for value in patterns
                    }
                ]
                output_types.extend(matches)
            else:
                output_types.append(output_type)
        unique = sorted({value for value in output_types if value})
        record: dict[str, Any] = {
            "quantity": output.get("amount", 0),
            "maxQuantity": output.get("maxAmount", output.get("amount", 0)),
            "chance": 1.0,
            "outputFlags": flags,
            "inheritFoodAge": any(
                flag.casefold() == "inheritfoodage" for flag in flags
            ),
        }
        record["chance"] = output.get("chance", 1.0)
        if len(unique) == 1:
            record["fullType"] = unique[0]
            if output.get("variableAmount"):
                record["resolution"] = "unresolved"
                overall = _merge_resolution(overall, "unresolved")
            elif record["chance"] < 1.0:
                record["resolution"] = "probabilistic"
                overall = _merge_resolution(overall, "probabilistic")
            else:
                record["resolution"] = "exact"
        elif len(unique) > 1:
            record["possibleOutputs"] = unique
            overall = _merge_resolution(overall, "ambiguous")
        else:
            overall = _merge_resolution(overall, "unresolved")
        resolved.append(record)
    return resolved, overall


def _pointer_matches(props: dict[str, Any], recipe_name: str) -> bool:
    wanted = recipe_name.casefold()
    return any(
        str(props.get(key) or "").casefold() == wanted
        for key in ("doubleClickRecipe", "openingRecipe")
    )


def discover_yield_recipes(
    base_scripts_root: Path | None,
    mod_roots: Iterable[Path],
    game_version: str | None,
    definitions: dict[str, Any],
) -> tuple[dict[str, list[dict[str, Any]]], dict[str, int]]:
    """Build the same source-indexed yield records used by the Lua bridge."""
    paths: list[Path] = []
    seen: set[Path] = set()
    if base_scripts_root and base_scripts_root.is_dir():
        paths.extend(sorted(base_scripts_root.rglob("*.txt")))
    for mod_root in mod_roots:
        selected, _version = item_script_paths(mod_root, game_version)
        paths.extend(selected)
    unique_paths = []
    for path in paths:
        path = path.resolve()
        if path not in seen:
            seen.add(path)
            unique_paths.append(path)

    index: dict[str, list[dict[str, Any]]] = {}
    recipe_count = 0
    source_count = 0
    for path in sorted(unique_paths):
        for recipe in parse_recipe_script(path):
            recipe_count += 1
            inputs = recipe.get("inputs") or []
            if len(inputs) != 1:
                continue
            input_spec = inputs[0]
            for source_full_type in input_spec.get("types") or []:
                props = (definitions.get(source_full_type).props
                         if definitions.get(source_full_type) is not None else {})
                outputs, resolution = _resolve_outputs(recipe, source_full_type)
                input_flags = list(input_spec.get("flags") or [])
                inherits_food_age = any(
                    flag.casefold() == "inheritfoodage" for flag in input_flags
                )
                for output in outputs:
                    output["inputFlags"] = input_flags
                    output["inheritFoodAge"] = (
                        output.get("inheritFoodAge") is True or inherits_food_age
                    )
                record = {
                    "recipe": recipe["recipe"],
                    "source": "offline_recipe_graph",
                    "sourceFile": recipe["sourceFile"],
                    "sourceFullType": source_full_type,
                    "inputAmount": input_spec.get("amount", 1),
                    "inputMaxAmount": input_spec.get(
                        "maxAmount", input_spec.get("amount", 1)
                    ),
                    "inputVariable": bool(input_spec.get("variableAmount")),
                    "inputCount": len(inputs),
                    "outputs": outputs,
                    "resolution": resolution,
                    "nameHeuristic": bool(recipe.get("nameHint")),
                    "candidateMethod": (
                        "explicit_property"
                        if _pointer_matches(props, str(recipe["recipe"]))
                        else "recipe_graph"
                    ),
                }
                index.setdefault(source_full_type, []).append(record)
                source_count += 1
    return index, {
        "recipeCount": recipe_count,
        "sourceCount": source_count,
        "sourceFileCount": len(unique_paths),
    }
