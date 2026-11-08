#!/usr/bin/env bash
set -uo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ZIP="$FLIP2_ROOT/pipeline/flipmouse-arcade/build/FlipMouseArcade.zip"
[[ -f "$ZIP" ]] && echo "Built: $ZIP ($(wc -c <"$ZIP" | tr -d ' ') bytes)" || echo "Not built — run: flip2 flipmouse-arcade build"
adb get-state >/dev/null 2>&1 || exit 0
adb shell "su -c 'ls /data/adb/modules/FlipMouseArcade/module.prop 2>/dev/null'" | tr -d '\r'
adb shell "su -c 'pgrep -a mouse 2>/dev/null'" | tr -d '\r'
adb shell "su -c 'tail -3 /cache/FlipMouseArcade.log 2>/dev/null'" | tr -d '\r'
