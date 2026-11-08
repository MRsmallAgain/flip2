#!/usr/bin/env bash
set -uo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ZIP="$FLIP2_ROOT/pipeline/landscape-gamepad/build/Flip2Gamepad.zip"
[[ -f "$ZIP" ]] && echo "Built: $ZIP ($(wc -c <"$ZIP" | tr -d ' ') bytes)" || echo "Not built — run: flip2 gamepad build"
adb get-state >/dev/null 2>&1 || exit 0
adb shell "su -c 'ls /data/adb/modules/Flip2Gamepad/module.prop 2>/dev/null'" | tr -d '\r'
adb shell "su -c 'pgrep -a gamepad 2>/dev/null'" | tr -d '\r'
adb shell "su -c 'cat /data/local/flip2/gamepad.conf 2>/dev/null'" | tr -d '\r'
adb shell "su -c 'tail -5 /cache/Flip2Gamepad.log 2>/dev/null'" | tr -d '\r'
