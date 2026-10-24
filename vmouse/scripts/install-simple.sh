#!/usr/bin/env bash
# Replace vMouse Magisk module binary with simple-release1 mouse; disable OK-click helper.
set -euo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$FLIP2_ROOT/lib/bootstrap.sh"
"$FLIP2_ROOT/vmouse/scripts/fetch-simple.sh"
BIN="$FLIP2_ROOT/vmouse/stock/mouse"
MOD="/data/adb/modules/vMouse"
OK_HELPER="/data/adb/service.d/flip2-vmouse-ok-click.sh"

flip2_adb_require_device

[[ -f "$BIN" ]] || { echo "Missing $BIN" >&2; exit 1; }

adb shell "su -c 'test -d $MOD || exit 2'" || {
  echo "Magisk module vMouse not found at $MOD." >&2
  echo "Install neutronscott vMouse module first (https://github.com/neutronscott/flip2/releases/tag/v2), then re-run." >&2
  exit 1
}

adb push "$BIN" /sdcard/Download/flip2-simple-mouse
adb shell "su -c '
  pkill -9 -f vMouse/mouse 2>/dev/null || killall -9 mouse 2>/dev/null || true
  sleep 1
  cp /sdcard/Download/flip2-simple-mouse $MOD/mouse
  chmod 755 $MOD/mouse
  if [ -f $OK_HELPER ]; then mv $OK_HELPER ${OK_HELPER}.disabled; fi
  settings put system keyboard_pointer_enable 0
  nohup $MOD/service.sh >/dev/null 2>&1 &
'"
echo "Simple mouse installed in vMouse module ($(wc -c <"$BIN" | tr -d ' ') bytes)."
echo "Reboot recommended. Toggle: long-press left soft key (Menu). D-pad + OK in mouse mode."
echo "Rollback: reinstall vMouse zip from https://github.com/neutronscott/flip2/releases/tag/v2"
