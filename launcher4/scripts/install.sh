#!/usr/bin/env bash
# adb install -r launcher4.apk — does NOT touch /system Launcher3.
set -euo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "$FLIP2_ROOT/lib/bootstrap.sh"
flip2_env_init

APK="$FLIP2_LAUNCHER4/dist/launcher4.apk"
[[ -f "$APK" ]] || { echo "Missing $APK — run: flip2 launcher4 build" >&2; exit 1; }

flip2_adb_require_device || exit 1
adb install -r "$APK"
if [[ -f "$FLIP2_OVERLAY/home-keys.json" ]]; then
  echo ""
  echo "Applying home-keys.json (Shortcuts / workspace soft keys)…"
  "$FLIP2_OVERLAY/scripts/apply-home-keys.sh"
fi
echo ""
echo "Installed. Set default home:"
echo "  flip2 launcher4 set-home"
echo "Or: Settings → Apps → Default apps → Home app"
echo "Rollback: flip2 launcher4 uninstall then pick stock Launcher3."
