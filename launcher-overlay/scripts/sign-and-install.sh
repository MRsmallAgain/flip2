#!/usr/bin/env bash
# Build overlay, sign with debug key (userdebug / many rooted builds), install, enable.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FLIP2_ROOT="$(cd "$ROOT/.." && pwd)"
DIST="$ROOT/dist"
# shellcheck source=/dev/null
source "$FLIP2_ROOT/lib/bootstrap.sh"
flip2_env_init

"$ROOT/scripts/build-overlay-apktool.sh"

UNSIGNED="$DIST/overlay-unsigned.apk"
ALIGNED="$DIST/overlay-aligned.apk"
SIGNED="$DIST/Flip2LauncherOverlay.apk"

flip2_sign_apk "$UNSIGNED" "$ALIGNED" "$SIGNED"

echo "Signed: $SIGNED"

if ! adb get-state >/dev/null 2>&1; then
  echo "No adb device — APK ready at $SIGNED"
  exit 0
fi

adb install -r "$SIGNED"
adb shell cmd overlay enable --user current com.tim.flip2.launcheroverlay 2>/dev/null \
  || adb shell cmd overlay enable com.tim.flip2.launcheroverlay 2>/dev/null \
  || echo "Enable manually: cmd overlay enable com.tim.flip2.launcheroverlay"

adb shell cmd overlay list | grep -i flip2 || true
echo "Restart launcher: adb shell am force-stop com.android.launcher3"
