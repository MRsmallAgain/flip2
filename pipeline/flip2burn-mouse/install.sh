#!/usr/bin/env bash
# Push + install flip2burnMouse Magisk module; start without rebooting.
set -euo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ZIP="$FLIP2_ROOT/pipeline/flip2burn-mouse/build/flip2burnMouse.zip"
[[ -f "$ZIP" ]] || { echo "Not built — run: flip2 flip2burn-mouse build" >&2; exit 1; }
adb get-state >/dev/null 2>&1 || { echo "No adb device" >&2; exit 1; }
adb push "$ZIP" /sdcard/Download/flip2burnMouse.zip
adb shell su -c 'magisk --install-module /sdcard/Download/flip2burnMouse.zip' >/dev/null 2>&1 || true
adb push "$FLIP2_ROOT/pipeline/flip2burn-mouse/scripts/ondevice-install.sh" /data/local/tmp/fbm-install.sh >/dev/null
adb shell su -c 'sh /data/local/tmp/fbm-install.sh' | tr -d '\r'
echo "Installed + started. Gestures: docs/FLIPMOUSE-ARCADE.md"
echo "Rollback: flip2 flip2burn-mouse rollback"
