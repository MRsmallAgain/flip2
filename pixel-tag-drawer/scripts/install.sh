#!/usr/bin/env bash
set -euo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$FLIP2_ROOT/lib/bootstrap.sh"
ZIP="$FLIP2_TAGDRAWER/dist/flip2_pixel_tag_drawer-magisk.zip"
flip2_adb_require_device
[[ -f "$ZIP" ]] || { echo "Missing $ZIP — run: flip2 tagdrawer pack" >&2; exit 1; }
adb uninstall io.github.xtratter.appshelf 2>/dev/null || true
adb uninstall dev.tn3w.shelf 2>/dev/null || true
flip2_magisk_push_install "$ZIP"
echo "Installed. Reboot required. D-pad Up → Pixel Tag Drawer (flip2 home-keys)."
echo "Rollback: flip2 tagdrawer rollback"
