# Flip2 shared modules (`lib/`)

Source **`lib/bootstrap.sh`** from any pipeline stage or script.

| Module | Exports | Purpose |
|--------|---------|---------|
| `paths.sh` | `FLIP2_ROOT`, `FLIP2_OVERLAY`, `FLIP2_PATCH`, `FLIP2_PIPELINE`, `FLIP2_LIB`, `FLIP2_BIN` | Repo layout |
| `constants.sh` | `FLIP2_OVERLAY_PKG`, `FLIP2_LAUNCHER_*`, `FLIP2_MAGISK_BAD_LAUNCHER_MOD`, APK byte sizes, `FLIP2_EDITOR_PORT` | Device/package ids |
| `env.sh` | `flip2_env_init`, `flip2_require_cmd` | JDK, SDK PATH, tool checks |
| `adb.sh` | `flip2_adb_require_device`, `flip2_adb_wait_boot`, `flip2_launcher_restart` | USB workflows |
| `magisk.sh` | `flip2_magisk_push_install`, `flip2_magisk_module_installed` | push → `magisk --install-module` (in-place unpack fallback) |
| `sign.sh` | `flip2_sign_apk` | zipalign + apksigner with the debug keystore |
| `slot5-policy.sh` | slot-5 crash-guard helpers | policy shared by stock + L4 paths |

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

## Deploy pipeline (`pipeline/deploy/`)

All tiers consume **`manifest.json`** (components, artifact types, root needs, tiers, install order) so they can never disagree:

| Script | Tier | Command |
|--------|------|---------|
| `pack-installer.sh` | B | `flip2 installer pack [--flavor clean\|full] [--vosk-url name=url]` → self-removing Magisk installer zip |
| `setup.sh` | C | `flip2 setup full` → runs per-component installs over adb with a PASS/FAIL summary |
| `pack-all.sh` | D | `flip2 pack-all` → `dist/flip2-packages-<version>/` bundle |
| `deroot.sh` | — | `flip2 deroot` → pushes + runs the on-device de-root helper (also embedded in the installer zip) |
| `../image/build-tree.sh` | A | `flip2 image build-tree` → `dist/flip2-system-tree/` for base-image merges ([docs/IMAGE-BUILD.md](IMAGE-BUILD.md)) |

The installer template lives in `installer/` (`update-binary` stub, one-shot `service.sh`, `customize.sh`, `module.prop.tmpl`, and the device-side `deroot.sh`). Host-side `jq` bakes all device data into plain files at pack time — the device script needs no `jq`.
