#!/usr/bin/env bash
set -euo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$FLIP2_ROOT/lib/bootstrap.sh"
MOD_ID=flip2_pixel_tag_drawer
flip2_adb_require_device
adb shell "su -c 'rm -rf /data/adb/modules/$MOD_ID'" 2>/dev/null || true
echo "Module removed. Reboot to drop system overlay."
