#!/usr/bin/env bash
set -euo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "$FLIP2_ROOT/lib/bootstrap.sh"

MOD_ID=flip2_launcher3_fork
STOCK="${STOCK_LAUNCHER:-$FLIP2_FORK/stock/Launcher3.apk}"

flip2_adb_require_device

adb shell "su -c 'rm -rf /data/adb/modules/${MOD_ID}'" 2>/dev/null || true

size=$(adb shell "su -c 'wc -c < ${FLIP2_LAUNCHER_APK}'" 2>/dev/null | tr -d '\r ')
if [[ "${size:-0}" -eq "$FLIP2_PATCHED_LAUNCHER_BYTES" && -f "$STOCK" ]]; then
  echo "Restoring stock Launcher3 from $STOCK"
  adb push "$STOCK" /sdcard/Download/Launcher3-stock.apk
  adb shell "su -c 'mount -o rw,remount /system 2>/dev/null || true; cp /sdcard/Download/Launcher3-stock.apk ${FLIP2_LAUNCHER_APK}; chmod 644 ${FLIP2_LAUNCHER_APK}; chown root:root ${FLIP2_LAUNCHER_APK}'"
fi

echo "Module removed. Rebooting…"
adb reboot
