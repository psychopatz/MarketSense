"""Stable composite facade for GUI application orchestration."""

from .gui_controller_display import DisplayControllerMixin
from .gui_controller_execution import ExecutionControllerMixin
from .gui_controller_outputs import OutputControllerMixin
from .gui_controller_settings import SettingsControllerMixin
from .gui_controller_support import ALL_MODS_LABEL, MAX_DIAGNOSTIC_CHARS


class ControllerMixin(
    SettingsControllerMixin,
    ExecutionControllerMixin,
    DisplayControllerMixin,
    OutputControllerMixin,
):
    """Compose GUI controller concerns while preserving the public class name."""


__all__ = ["ALL_MODS_LABEL", "MAX_DIAGNOSTIC_CHARS", "ControllerMixin"]
