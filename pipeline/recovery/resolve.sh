#!/usr/bin/env bash
# Pipeline: remove bad Magisk launcher mod → restore stock Launcher3 if needed → overlay apply
set -euo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "$FLIP2_ROOT/lib/bootstrap.sh"

flip2_env_init
flip2_adb_require_device
flip2_adb_wait_boot 45

STOCK="${STOCK_LAUNCHER:-$FLIP2_PATCH/stock/Launcher3.apk}"
if [[ ! -f "$STOCK" && -f /tmp/flip2-launcher-pull/Launcher3.apk ]]; then
  STOCK=/tmp/flip2-launcher-pull/Launcher3.apk
fi

adb shell "su -c 'rm -rf /data/adb/modules/${FLIP2_MAGISK_BAD_LAUNCHER_MOD}'" 2>/dev/null || true

size=$(adb shell "su -c 'wc -c < ${FLIP2_LAUNCHER_APK}'" 2>/dev/null | tr -d '\r ')
if [[ "${size:-0}" -eq "$FLIP2_PATCHED_LAUNCHER_BYTES" && -f "$STOCK" ]]; then
  echo "Patched launcher still on system — restoring stock from $STOCK"
  adb push "$STOCK" /sdcard/Download/Launcher3-stock.apk
  adb shell "su -c 'mount -o rw,remount /system 2>/dev/null || true; cp /sdcard/Download/Launcher3-stock.apk ${FLIP2_LAUNCHER_APK}; chmod 644 ${FLIP2_LAUNCHER_APK}; chown root:root ${FLIP2_LAUNCHER_APK}'"
  echo "Stock Launcher3 restored — rebooting…"
  adb reboot
  flip2_adb_wait_boot 45
fi

"$FLIP2_PIPELINE/overlay/apply.sh"

flip2_launcher_restart
echo "Recovery pipeline: done. Open Menu on phone."
adb shell "su -c 'ls /data/adb/modules/ 2>/dev/null; wc -c ${FLIP2_LAUNCHER_APK}'" 2>/dev/null || true
