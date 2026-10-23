#!/usr/bin/env bash
set -euo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$FLIP2_ROOT/lib/bootstrap.sh"
flip2_env_init

APK="${1:-$FLIP2_FORK/dist/Launcher3-fork.apk}"
[[ -f "$APK" ]] || { echo "Missing APK: $APK" >&2; exit 1; }

size=$(wc -c < "$APK" | tr -d ' ')
if [[ "$size" -eq "$FLIP2_PATCHED_LAUNCHER_BYTES" ]]; then
  echo "warn: APK size matches old withdrawn patch ($size)" >&2
fi

AAPT=$(command -v aapt2 2>/dev/null || find "$ANDROID_SDK_ROOT/build-tools" -name aapt2 2>/dev/null | head -1)
if [[ -n "${AAPT:-}" && -x "$AAPT" ]]; then
  pkg=$("$AAPT" dump badging "$APK" 2>/dev/null | grep "package:" | head -1)
  echo "$pkg"
  echo "$pkg" | grep -q "name='com.android.launcher3'" || { echo "wrong package" >&2; exit 1; }
fi
echo "verify-apk: OK size=$size"
