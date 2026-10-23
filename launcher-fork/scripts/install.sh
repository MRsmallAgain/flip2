#!/usr/bin/env bash
set -euo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "$FLIP2_ROOT/lib/bootstrap.sh"

MOD_ID=flip2_launcher3_fork
ZIP="$FLIP2_FORK/dist/flip2_launcher3_fork-magisk.zip"

flip2_adb_require_device

size=$(adb shell "su -c 'wc -c < ${FLIP2_LAUNCHER_APK}'" 2>/dev/null | tr -d '\r ')
if [[ "${size:-0}" -ne "$FLIP2_STOCK_LAUNCHER_BYTES" ]]; then
  echo "warn: system Launcher3 size is ${size:-?}, expected stock $FLIP2_STOCK_LAUNCHER_BYTES" >&2
fi

[[ -f "$ZIP" ]] || { echo "Missing $ZIP — run: flip2 fork pack" >&2; exit 1; }

adb push "$ZIP" /sdcard/Download/flip2_launcher3_fork-magisk.zip
adb shell "su -c 'magisk --install-module /sdcard/Download/flip2_launcher3_fork-magisk.zip'"
echo "Installed. Reboot required. Rollback: flip2 fork rollback"
