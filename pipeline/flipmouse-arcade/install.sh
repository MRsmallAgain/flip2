#!/usr/bin/env bash
# Push + install FlipMouse Arcade Magisk module; start without rebooting.
set -euo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ZIP="$FLIP2_ROOT/pipeline/flipmouse-arcade/build/FlipMouseArcade.zip"
[[ -f "$ZIP" ]] || { echo "Not built — run: flip2 flipmouse-arcade build" >&2; exit 1; }
adb get-state >/dev/null 2>&1 || { echo "No adb device" >&2; exit 1; }
adb push "$ZIP" /sdcard/Download/FlipMouseArcade.zip
adb shell su -c 'magisk --install-module /sdcard/Download/FlipMouseArcade.zip' >/dev/null 2>&1 || true
adb push "$FLIP2_ROOT/pipeline/flipmouse-arcade/scripts/ondevice-install.sh" /data/local/tmp/fma-install.sh >/dev/null
adb shell su -c 'sh /data/local/tmp/fma-install.sh' | tr -d '\r'
echo "Installed + started. Gestures: docs/FLIPMOUSE-ARCADE.md — left-soft 1s = mode; right-soft = R1/Shortcuts only."
echo "Rollback: flip2 flipmouse-arcade rollback"
