#!/usr/bin/env bash
set -euo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$FLIP2_ROOT/lib/bootstrap.sh"

if ! adb get-state >/dev/null 2>&1; then
  echo "No adb device"
  ls -la "$FLIP2_FORK/dist/" 2>/dev/null || echo "(no dist yet)"
  exit 0
fi

echo "=== Launcher3 on device ==="
adb shell "su -c 'wc -c ${FLIP2_LAUNCHER_APK}'" 2>/dev/null | tr -d '\r' || true
echo "stock=$FLIP2_STOCK_LAUNCHER_BYTES patched_old=$FLIP2_PATCHED_LAUNCHER_BYTES"

echo "=== Magisk modules ==="
adb shell "su -c 'ls /data/adb/modules/ 2>/dev/null'" 2>/dev/null | tr -d '\r' || true

echo "=== Local fork build ==="
ls -la "$FLIP2_FORK/dist/" 2>/dev/null || echo "(no dist yet)"
