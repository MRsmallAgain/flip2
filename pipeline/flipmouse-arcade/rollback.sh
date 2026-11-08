#!/usr/bin/env bash
set -euo pipefail
adb shell su -c 'pkill -f FlipMouseArcade/mouse 2>/dev/null; pkill -f FlipMouseArcade/service.sh 2>/dev/null; true'
adb shell su -c 'rm -rf /data/adb/modules/FlipMouseArcade'
echo "FlipMouse Arcade module removed — reboot clears any leftover state."
