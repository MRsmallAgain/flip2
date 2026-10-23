# Flip2 shared modules (`lib/`)

Source **`lib/bootstrap.sh`** from any pipeline stage or script.

| Module | Exports | Purpose |
|--------|---------|---------|
| `paths.sh` | `FLIP2_ROOT`, `FLIP2_OVERLAY`, `FLIP2_PATCH`, `FLIP2_PIPELINE`, `FLIP2_LIB`, `FLIP2_BIN` | Repo layout |
| `constants.sh` | `FLIP2_OVERLAY_PKG`, `FLIP2_LAUNCHER_*`, `FLIP2_MAGISK_BAD_LAUNCHER_MOD`, APK byte sizes, `FLIP2_EDITOR_PORT` | Device/package ids |
| `env.sh` | `flip2_env_init`, `flip2_require_cmd` | JDK, SDK PATH, tool checks |
| `adb.sh` | `flip2_adb_require_device`, `flip2_adb_wait_boot`, `flip2_launcher_restart` | USB workflows |

## Example stage script

```bash
#!/usr/bin/env bash
set -euo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$FLIP2_ROOT/lib/bootstrap.sh"
flip2_env_init
flip2_adb_require_device
```

## Overlay build stages (`launcher-overlay/scripts/`)

| Script | Stage |
|--------|--------|
| `build-overlay-apktool.sh` | apktool build |
| `sign-and-install.sh` | zipalign, apksigner, adb install |
| `after-root-enable.sh` | idmap2 + overlay enable |
| `pack-magisk-module.sh` | Magisk zip for RRO only |

**`pipeline/overlay/apply.sh`:** `sync-slots` → sign-and-install → after-root-enable.
