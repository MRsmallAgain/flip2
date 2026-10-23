#!/usr/bin/env bash
# Retry adb until Magisk launcher module is disabled (use on local PC when phone boot-loops).
set -euo pipefail
MOD=flip2_launcher3_null_icon_fix
echo "Waiting for device… (Ctrl+C to stop)"
while true; do
  if adb get-state >/dev/null 2>&1; then
    if adb shell "su -c 'test -f /data/adb/modules/${MOD}/disable && echo already_disabled || (touch /data/adb/modules/${MOD}/disable 2>/dev/null || rm -rf /data/adb/modules/${MOD}) && echo disabled'" 2>/dev/null | grep -q disabled; then
      echo "Module disabled. Rebooting…"
      adb reboot
      exit 0
    fi
  fi
  sleep 2
done
