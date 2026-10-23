#!/usr/bin/env bash
# After root: enable overlay, fix idmap path, restart launcher.
set -euo pipefail
PKG=com.tim.flip2.launcheroverlay
TARGET=/system/priv-app/Launcher3/Launcher3.apk

adb get-state >/dev/null || { echo "No adb device"; exit 1; }

OVERLAY=$(adb shell pm path "$PKG" 2>/dev/null | head -1 | sed 's/package://')
if [[ -z "$OVERLAY" ]]; then
  echo "Install overlay first: scripts/sign-and-install.sh"
  exit 1
fi

ENCODED=$(echo "$OVERLAY" | sed 's|^/||; s|/|@|g')
IDMAP="/data/resource-cache/${ENCODED}@idmap"

echo "Overlay APK: $OVERLAY"
echo "Creating idmap at: $IDMAP"
adb shell su -c "idmap2 create --target-apk-path $TARGET --overlay-apk-path $OVERLAY --idmap-path $IDMAP --ignore-overlayable" \
  || { echo "idmap2 failed — ensure res/values/public.xml matches Launcher3 IDs"; exit 1; }

echo "Enabling overlay (requires root shell)..."
adb shell su -c "cmd overlay enable --user 0 $PKG" 2>&1 || true

echo "Overlay status:"
adb shell su -c "dumpsys overlay" 2>&1 | grep -A12 "com.tim.flip2" || adb shell cmd overlay list | grep -i flip2

adb shell su -c "am force-stop com.android.launcher3"
echo "Done. Press Home on the phone. Edit at http://127.0.0.1:8765 → Save → Build + install → run this script again."
