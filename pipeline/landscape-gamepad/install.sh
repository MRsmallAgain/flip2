#!/usr/bin/env bash
set -euo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ZIP="$FLIP2_ROOT/pipeline/landscape-gamepad/build/Flip2Gamepad.zip"
[[ -f "$ZIP" ]] || { echo "Not built — run: flip2 gamepad build" >&2; exit 1; }
adb get-state >/dev/null 2>&1 || { echo "No adb device" >&2; exit 1; }
adb push "$ZIP" /sdcard/Download/Flip2Gamepad.zip
adb shell su -c 'magisk --install-module /sdcard/Download/Flip2Gamepad.zip' >/dev/null 2>&1 || true
adb push "$FLIP2_ROOT/pipeline/landscape-gamepad/scripts/ondevice-install.sh" /data/local/tmp/gp-install.sh >/dev/null
adb shell su -c 'sh /data/local/tmp/gp-install.sh' | tr -d '\r'
echo "Installed. Auto-activates in landscape when landscape_auto=1 in /data/local/flip2/gamepad.conf"
echo "Mutual exclusion: disable FlipMouse grab or gamepad when both installed."