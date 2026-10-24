#!/usr/bin/env bash
set -euo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "$FLIP2_ROOT/lib/bootstrap.sh"
flip2_env_init
flip2_require_cmd apktool zipalign apksigner

DIST="$FLIP2_FORK/dist"
WORK="$FLIP2_FORK/work/decoded"
mkdir -p "$DIST"

"$FLIP2_FORK/scripts/extract-from-stock.sh"
"$FLIP2_FORK/scripts/apply-patches.sh"
"$FLIP2_FORK/scripts/inject-slots.sh"
"$FLIP2_LAUNCHER4/scripts/patch-menu-icons.sh" "$WORK"

apktool b "$WORK" -o "$DIST/Launcher3-fork-unsigned.apk"
ZIPALIGN="${ZIPALIGN:-$ANDROID_SDK_ROOT/build-tools/34.0.0/zipalign}"
"$ZIPALIGN" -p -f 4 "$DIST/Launcher3-fork-unsigned.apk" "$DIST/Launcher3-fork-aligned.apk"
KEY="${ANDROID_DEBUG_KEY:-$HOME/.android/debug.keystore}"
apksigner sign --ks "$KEY" --ks-pass pass:android --key-pass pass:android \
  --out "$DIST/Launcher3-fork.apk" "$DIST/Launcher3-fork-aligned.apk"
echo "Built: $DIST/Launcher3-fork.apk"
"$FLIP2_FORK/scripts/verify-apk.sh" "$DIST/Launcher3-fork.apk"
