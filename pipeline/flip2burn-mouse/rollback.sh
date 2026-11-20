#!/usr/bin/env bash
set -euo pipefail
adb shell su -c 'pkill -f flip2burnMouse/mouse 2>/dev/null; pkill -f flip2burnMouse/service.sh 2>/dev/null; killall mouse 2>/dev/null; true'
adb shell su -c 'rm -rf /data/adb/modules/flip2burnMouse'
echo "flip2burnMouse module removed."
