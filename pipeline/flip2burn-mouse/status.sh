#!/usr/bin/env bash
set -uo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ZIP="$FLIP2_ROOT/pipeline/flip2burn-mouse/build/flip2burnMouse.zip"
[[ -f "$ZIP" ]] && echo "Built: $ZIP ($(wc -c <"$ZIP" | tr -d ' ') bytes)" || echo "Not built — run: flip2 flip2burn-mouse build"
adb get-state >/dev/null 2>&1 || exit 0
adb shell "su -c 'ls /data/adb/modules/flip2burnMouse/module.prop 2>/dev/null'" | tr -d '\r'
adb shell "su -c 'pgrep -a mouse 2>/dev/null'" | tr -d '\r'
adb shell "su -c 'tail -5 /cache/flip2burnMouse.log 2>/dev/null'" | tr -d '\r'
