#!/usr/bin/env bash
set -euo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$FLIP2_ROOT/lib/bootstrap.sh"
STOCK="$FLIP2_TAGDRAWER/stock"
APK="$STOCK/PixelTagDrawer.apk"
URL="${FLIP2_TAGDRAWER_APK_URL:-https://f-droid.org/repo/com.iwadjp.pixeltagdrawer_7.apk}"
mkdir -p "$STOCK"
if [[ -f "$APK" ]] && [[ "${FLIP2_TAGDRAWER_FORCE_FETCH:-0}" != "1" ]]; then
  echo "Stock APK present: $APK"
  exit 0
fi
curl -sL -o "$APK" "$URL"
file "$APK"
echo "Fetched: $APK"
