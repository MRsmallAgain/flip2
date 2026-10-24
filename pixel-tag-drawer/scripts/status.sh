#!/usr/bin/env bash
set -euo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$FLIP2_ROOT/lib/bootstrap.sh"
PKG=com.iwadjp.pixeltagdrawer
ZIP="$FLIP2_TAGDRAWER/dist/flip2_pixel_tag_drawer-magisk.zip"
[[ -f "$ZIP" ]] && echo "Packed: $ZIP ($(wc -c <"$ZIP" | tr -d ' ') bytes)" || echo "Not packed — flip2 tagdrawer pack"
if adb get-state >/dev/null 2>&1; then
  adb shell pm path "$PKG" 2>/dev/null || echo "Not installed (user or system)"
  adb shell "su -c 'test -d /data/adb/modules/flip2_pixel_tag_drawer && echo Magisk: flip2_pixel_tag_drawer enabled || echo Magisk: module not installed'" 2>/dev/null || echo "Magisk: (no root)"
  adb shell settings get global keyshortcut_upkey 2>/dev/null | sed 's/^/Up key: /'
fi
