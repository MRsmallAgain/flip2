#!/usr/bin/env bash
set -euo pipefail
adb shell su -c 'pkill -f FlipMouse/mouse 2>/dev/null; true'
adb shell su -c 'rm -rf /data/adb/modules/FlipMouse'
echo "FlipMouse module removed — reboot clears any leftover state."
