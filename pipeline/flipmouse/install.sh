#!/usr/bin/env bash
# Push + install the built FlipMouse Magisk module; start it without rebooting.
# Magisk 25.2 only stages new modules in modules_update until reboot, so the
# zip is also unpacked straight into /data/adb/modules/FlipMouse (same trick
# as the navoverlay pipeline) and the mouse daemon is started immediately.
set -euo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ZIP="$FLIP2_ROOT/pipeline/flipmouse/build/FlipMouse.zip"
[[ -f "$ZIP" ]] || { echo "Not built — run: flip2 flipmouse build" >&2; exit 1; }
adb get-state >/dev/null 2>&1 || { echo "No adb device" >&2; exit 1; }
adb push "$ZIP" /sdcard/Download/FlipMouse.zip
adb shell su -c 'magisk --install-module /sdcard/Download/FlipMouse.zip' >/dev/null 2>&1 || true
adb push "$FLIP2_ROOT/pipeline/flipmouse/scripts/ondevice-install.sh" /data/local/tmp/fm-install.sh >/dev/null
adb shell su -c 'sh /data/local/tmp/fm-install.sh' | tr -d '\r'
echo "Installed + started. Activate: hold OK + Volume-Down ~1s, release both. Exit: star tap."
echo "Rollback: flip2 flipmouse rollback"
