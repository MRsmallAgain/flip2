#!/usr/bin/env bash
# Open default-home picker (user must confirm on device).
set -euo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "$FLIP2_ROOT/lib/bootstrap.sh"

PKG="${FLIP2_LAUNCHER4_PKG:-com.tim.flip2.launcher4}"
ACTIVITY="${PKG}/com.android.launcher3.Launcher"

flip2_adb_require_device || exit 1
adb shell cmd package set-home-activity "$ACTIVITY" 2>/dev/null || {
  adb shell am start -a android.settings.HOME_SETTINGS 2>/dev/null || true
  echo "Pick \"$PKG\" (Flip2 Launcher4) as Home app on the phone."
  exit 0
}
echo "Default home set to $ACTIVITY"
