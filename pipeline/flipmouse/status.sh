#!/usr/bin/env bash
set -uo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$FLIP2_ROOT/pipeline/flipmouse/build/mouse"
ZIP="$FLIP2_ROOT/pipeline/flipmouse/build/FlipMouse.zip"
[[ -f "$ZIP" ]] && echo "Built: $ZIP ($(wc -c <"$ZIP" | tr -d ' ') bytes)" || echo "Not built — run: flip2 flipmouse build"
adb get-state >/dev/null 2>&1 || exit 0
adb shell "su -c 'ls /data/adb/modules/FlipMouse/module.prop 2>/dev/null'" | tr -d '\r'
adb shell "su -c 'pgrep -a mouse 2>/dev/null'" | tr -d '\r'
adb shell "su -c 'tail -3 /cache/FlipMouse.log 2>/dev/null'" | tr -d '\r'
