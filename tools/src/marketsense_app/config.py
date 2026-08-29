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

# Liquid content prices deliberately have their own data contract.  The
# shipped table is read-only from the inspector's point of view; user edits
# go to the separate Lua override file so mod updates do not erase them.
LIQUID_PRICING_DATA_PATH = (
    MOD_ROOT / "common" / "media" / "lua" / "shared" / "MarketSense"
    / "Pricing" / "MS_LiquidPricing_Data.lua"
)
LIQUID_PRICING_OVERRIDE_PATH = (
    MOD_ROOT / "common" / "media" / "lua" / "shared" / "MarketSense"
    / "Pricing" / "MS_LiquidPricing_Overrides_Data.lua"
)
