#!/usr/bin/env bash
set -euo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$FLIP2_ROOT/lib/bootstrap.sh"
"$FLIP2_TAGDRAWER/scripts/fetch-stock.sh"
APK="$FLIP2_TAGDRAWER/stock/PixelTagDrawer.apk"
MOD="$FLIP2_TAGDRAWER/magisk-module"
ZIP="$FLIP2_TAGDRAWER/dist/flip2_pixel_tag_drawer-magisk.zip"
[[ -f "$APK" ]] || { echo "Missing $APK" >&2; exit 1; }
mkdir -p "$MOD/system/app/PixelTagDrawer"
cp "$APK" "$MOD/system/app/PixelTagDrawer/PixelTagDrawer.apk"
rm -f "$ZIP"
(cd "$MOD" && zip -r "$ZIP" module.prop service.sh system)
echo "Magisk module: $ZIP"
