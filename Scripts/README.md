# MarketSense Maintenance Scripts

These scripts support MarketSense cache generation and asset sync.

## 0. Market Sense Prebuild (`market_sense_prebuild.py`)

This is an optional maintenance tool for regenerating the `DT_Items` runtime
cache used by MarketSense and consumed by DynamicTrading. Runtime Lua can now
rebuild the cache automatically when it is stale, but this script remains
useful for audits, manual refreshes, and sandbox asset sync.

### Typical Usage

Run against the active server config:

```bash
python3 market_sense_prebuild.py --server-config ~/Zomboid/Server/modv2-Colony.ini
```

Or provide an explicit active mod list:

```bash
python3 market_sense_prebuild.py --mods "DynamicTradingCommon;DynamicTradingV2;DynamicColonies;CurrencyExpanded;DynamicObjectives;MarketSense"
```

### Outputs

- Rewrites `~/Zomboid/Lua/DT_Items/*`
- Rewrites `~/Zomboid/Lua/DT_Items/DT_ItemsIndex.lua`
- Writes an audit report to `~/Zomboid/Lua/DT_Items/DT_PrebuildAudit.json`
- Refreshes MarketSense-owned taxonomy, runtime rules, and sandbox assets

### Notes

- The stored `basePrice` is a pre-sandbox variation value, not the final price.
- Runtime Lua remains the authoritative recovery path when the cache is missing.
- This script is intended for maintenance and verification, not as a gameplay requirement.
