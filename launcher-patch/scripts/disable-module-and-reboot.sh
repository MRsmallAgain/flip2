#!/usr/bin/env bash
# Disable flip2_launcher3_null_icon_fix Magisk module and reboot (fixes homescreen crash loop).
set -euo pipefail
MOD=flip2_launcher3_null_icon_fix
adb wait-for-device
adb shell "su -c 'touch /data/adb/modules/${MOD}/disable || rm -rf /data/adb/modules/${MOD}'"
echo "Module disabled. Rebooting…"
adb reboot
