#!/usr/bin/env bash
# Pull Launcher3 APK and extract string resource names for RRO overrides.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG=com.android.launcher3
TMP="${TMPDIR:-/tmp}/flip2-launcher-pull"
mkdir -p "$TMP"

if ! adb get-state >/dev/null 2>&1; then
  echo "No adb device. Connect phone (USB or wireless adb)."
  exit 1
fi

APK_PATH=$(adb shell pm path "$PKG" | head -1 | sed 's/package://')
echo "Pulling $APK_PATH ..."
adb pull "$APK_PATH" "$TMP/Launcher3.apk"

command -v apktool >/dev/null || { echo "Install apktool to decode"; exit 1; }
rm -rf "$TMP/decoded"
apktool d -f "$TMP/Launcher3.apk" -o "$TMP/decoded"

OUT="$ROOT/reference/launcher3-strings.txt"
mkdir -p "$ROOT/reference"
grep -rh 'name="' "$TMP/decoded/res/values"/strings*.xml 2>/dev/null \
  | sed -n 's/.*name="\([^"]*\)".*/\1/p' | sort -u > "$OUT"

echo "Wrote resource names: $OUT ($(wc -l < "$OUT") lines)"
echo "Sample (menu/drawer related):"
grep -iE 'menu|drawer|all_app|workspace|hotseat|folder' "$OUT" | head -30 || true
