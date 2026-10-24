#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MOD="$ROOT/magisk-module"
ZIP="$ROOT/dist/flip2_keypad_backspace-magisk.zip"
mkdir -p "$ROOT/dist" "$MOD/system/usr/keylayout"
rm -f "$ZIP"
(cd "$MOD" && zip -r "$ZIP" module.prop service.sh system >/dev/null)
echo "Magisk module: $ZIP"
