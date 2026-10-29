#!/usr/bin/env bash
# Tier C: one-shot full rooted setup. Runs the existing per-component installs
# in the verified order (navoverlay -> keypad -> flipmouse -> tagdrawer ->
# launcher4 -> ime -> home-keys -> forkgram release), tolerating individual
# failures, and prints a status summary at the end.
#
# The Tier B installer zip (flip2 installer pack --flavor full) does the same
# job as a self-removing Magisk module; this wrapper drives the live adb paths
# instead and is what was used to provision the device by hand.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/lib/bootstrap.sh"
flip2_env_init

usage() {
  cat <<EOF
Usage: flip2 setup [full]

Run the full rooted flip2 install over adb, in the verified order:

  1. navoverlay      Magisk module (reboot required)
  2. keypad          Magisk module, backspace remap (reboot required)
  3. flipmouse       Magisk module, daemon started immediately
  4. tagdrawer       Magisk module, /system/app PixelTagDrawer (reboot required)
  5. launcher4       user APK + default HOME
  6. ime             Null Keyboard APK + IME settings + STT models
  7. home-keys       Settings.Global keyshortcut_* from home-keys.json
  8. forkgram        release APK (download + verify + install)
  9. display         logical size override 321x428 (reboot required)
 10. wallpaper       default wallpaper into /data/system/users/0 (reboot required)

Each step reports PASS/FAIL; a failed step does not stop the rest. Modules
that need a reboot are listed in the summary.
EOF
}

ARG="${1:-full}"
case "$ARG" in
  full|help|-h|--help) [[ "$ARG" == full ]] || { usage; exit 0; } ;;
  *) echo "Unknown setup target: $ARG (only 'full' exists)" >&2; usage; exit 1 ;;
esac

flip2_adb_require_device || exit 1

PASS=()
FAIL=()
REBOOT_NEEDED=()

step() {
  local name="$1"; shift
  echo ""
  echo "==> [$name]"
  if "$@"; then
    PASS+=("$name")
  else
    FAIL+=("$name")
    echo "    !! $name FAILED -- continuing with the remaining steps"
  fi
}

step_navoverlay() {
  "$FLIP2_BIN/flip2" navoverlay install
  REBOOT_NEEDED+=("navoverlay")
}

step_keypad() {
  bash "$FLIP2_ROOT/keypad-backspace/scripts/pack.sh"
  flip2_magisk_push_install "$FLIP2_ROOT/keypad-backspace/dist/flip2_keypad_backspace-magisk.zip"
  REBOOT_NEEDED+=("keypad (backspace remap)")
}

step_flipmouse() {
  "$FLIP2_BIN/flip2" flipmouse install
}

step_tagdrawer() {
  "$FLIP2_BIN/flip2" tagdrawer pack
  "$FLIP2_BIN/flip2" tagdrawer install
  REBOOT_NEEDED+=("tagdrawer (/system/app placement)")
}

step_launcher4() {
  [[ -f "$FLIP2_LAUNCHER4/dist/launcher4.apk" ]] || "$FLIP2_BIN/flip2" launcher4 build
  "$FLIP2_BIN/flip2" launcher4 install
  "$FLIP2_BIN/flip2" launcher4 set-home
}

step_ime() {
  "$FLIP2_BIN/flip2" ime hide-bar
}

step_home_keys() {
  "$FLIP2_BIN/flip2" home-keys
}

step_forkgram() {
  "$FLIP2_BIN/flip2" forkgram release
}

step_display() {
  # Same value the installer bakes into display_size_forced; `wm size` applies
  # it now and WindowManager re-reads it at every boot.
  "$FLIP2_BIN/flip2" display size 321x428
  REBOOT_NEEDED+=("display (logical 321x428 on the next boot)")
}

step_wallpaper() {
  "$FLIP2_BIN/flip2" wallpaper apply
  REBOOT_NEEDED+=("wallpaper (shows on the next boot)")
}

step navoverlay  step_navoverlay
step keypad      step_keypad
step flipmouse   step_flipmouse
step tagdrawer   step_tagdrawer
step launcher4   step_launcher4
step ime         step_ime
step home-keys   step_home_keys
step forkgram    step_forkgram
step display     step_display
step wallpaper   step_wallpaper

# --- status summary ---------------------------------------------------------
echo ""
echo "========================================"
echo "flip2 setup summary ($ARG)"
for p in "${PASS[@]}"; do echo "  PASS  $p"; done
for f in "${FAIL[@]}"; do echo "  FAIL  $f"; done
echo "----------------------------------------"
if [ "${#FAIL[@]}" -gt 0 ]; then
  echo "Failed steps: rerun 'flip2 setup full' (steps are idempotent) or run"
  echo "the failing component directly, e.g. 'flip2 ime hide-bar'."
fi
echo "Reboot required for: ${REBOOT_NEEDED[*]}"
echo "After reboot verify: flip2 flipmouse status && flip2 ime status"
echo "========================================"

[ "${#FAIL[@]}" -eq 0 ]
