#!/usr/bin/env bash
set -euo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "$FLIP2_ROOT/lib/bootstrap.sh"
flip2_env_init
flip2_require_cmd apktool zipalign apksigner

DIST="$FLIP2_LAUNCHER4/dist"
WORK="$FLIP2_LAUNCHER4/work/decoded"
mkdir -p "$DIST"

"$FLIP2_LAUNCHER4/scripts/extract-from-stock.sh"
"$FLIP2_FORK/scripts/apply-patches-to.sh" "$WORK"
"$FLIP2_LAUNCHER4/scripts/retarget-manifest.sh" "$WORK"
"$FLIP2_LAUNCHER4/scripts/retarget-smali.sh" "$WORK"
"$FLIP2_LAUNCHER4/scripts/skip-priv-features.sh" "$WORK"
"$FLIP2_LAUNCHER4/scripts/patch-home-keys-intents.sh" "$WORK"
"$FLIP2_LAUNCHER4/scripts/patch-home-intent.sh" "$WORK"
"$FLIP2_LAUNCHER4/scripts/patch-menu-icons.sh" "$WORK"
"$FLIP2_LAUNCHER4/scripts/patch-tools-icons.sh" "$WORK"
"$FLIP2_LAUNCHER4/scripts/patch-menu-grid-3x3.sh" "$WORK"
"$FLIP2_LAUNCHER4/scripts/merge-overlay-res.sh" "$WORK"

apktool b "$WORK" -o "$DIST/launcher4-unsigned.apk"
ZIPALIGN="${ZIPALIGN:-$ANDROID_SDK_ROOT/build-tools/34.0.0/zipalign}"
"$ZIPALIGN" -p -f 4 "$DIST/launcher4-unsigned.apk" "$DIST/launcher4-aligned.apk"
KEY="${ANDROID_DEBUG_KEY:-$HOME/.android/debug.keystore}"
apksigner sign --ks "$KEY" --ks-pass pass:android --key-pass pass:android \
  --out "$DIST/launcher4.apk" "$DIST/launcher4-aligned.apk"
echo "Built: $DIST/launcher4.apk"
if [[ -x "$FLIP2_LAUNCHER4/scripts/verify-apk.sh" ]]; then
  "$FLIP2_LAUNCHER4/scripts/verify-apk.sh" "$DIST/launcher4.apk"
fi
