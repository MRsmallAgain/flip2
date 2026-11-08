#!/usr/bin/env bash
set -euo pipefail
adb shell su -c 'pkill -f Flip2Gamepad/gamepad 2>/dev/null; pkill gamepad 2>/dev/null; true'
adb shell su -c 'rm -rf /data/adb/modules/Flip2Gamepad'
echo "Flip2Gamepad module removed — reboot to clear uinput node if stuck."
