"""Application paths and stable defaults."""

from pathlib import Path


TOOLS_ROOT = Path(__file__).resolve().parents[2]
REPO_ROOT = TOOLS_ROOT.parent
MOD_ROOT = REPO_ROOT / "Contents" / "mods" / "MarketSense"
DEFAULT_GAME_VERSION = "42.20"
DEFAULT_CACHE_DIR = TOOLS_ROOT / ".cache" / "results"
DEFAULT_SANDBOX_SETTINGS_PATH = TOOLS_ROOT / ".config" / "sandbox-settings.json"
DEFAULT_INSPECTOR_SETTINGS_PATH = TOOLS_ROOT / ".config" / "inspector-settings.json"
DEFAULT_RUNTIME_ITEMS_DIR = Path.home() / "Zomboid" / "Lua" / "MS_Items"
