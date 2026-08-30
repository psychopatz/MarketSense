"""Public sandbox API facade.

Catalog discovery, cross-source audits, and settings persistence live in
focused modules. These imports preserve the historical marketsense_app.sandbox
contract used by the CLI and GUI.
"""

from .sandbox_catalog import (
    SANDBOX_CATALOG_PATH,
    SANDBOX_FORMAT_VERSION,
    SandboxOption,
    SandboxSettingsError,
    default_sandbox_settings,
    load_sandbox_catalog,
    load_sandbox_option_specs,
    normalize_settings,
    option_map,
    recommended_sandbox_settings,
)
from .sandbox_audit import sandbox_definition_audit
from .sandbox_settings import (
    effective_sandbox_settings,
    load_sandbox_settings,
    save_sandbox_settings,
    setting_display,
)

__all__ = [
    "SANDBOX_CATALOG_PATH", "SANDBOX_FORMAT_VERSION", "SandboxOption",
    "SandboxSettingsError", "default_sandbox_settings",
    "effective_sandbox_settings", "load_sandbox_catalog",
    "load_sandbox_option_specs", "load_sandbox_settings", "normalize_settings",
    "option_map", "recommended_sandbox_settings", "sandbox_definition_audit",
    "save_sandbox_settings", "setting_display",
]
