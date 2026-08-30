"""Explicit item view/rule composition with compatibility exports."""

from .gui_item_model import category_metadata, metadata_label
from .gui_item_rules import ItemRulesMixin
from .gui_item_tree import ItemTreeMixin


class ItemsMixin(ItemTreeMixin, ItemRulesMixin):
    """Compose item-tree presentation and runtime-rule editing components."""


__all__ = ["ItemsMixin", "category_metadata", "metadata_label"]
