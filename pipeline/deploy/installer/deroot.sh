#!/system/bin/sh
# flip2 de-root helper. Runs from plain `adb shell` (no root needed for the
# shell-uid parts); uses su only if available for module removal.
#   sh /data/local/flip2/deroot.sh [--uninstall-apks]
# The boot-image restore is manual: Magisk app -> Uninstall -> Restore Images
# (or Complete Uninstall), then reboot. Magisk's CLI cannot safely do that step.

MODS="flip2_nav_overlay flip2_keypad_backspace FlipMouse flip2_pixel_tag_drawer flip2_launcher_overlay flip2_launcher3_null_icon_fix"
KIME="com.iqqijni.dvt912key/.keyboard_service.view.HDKeyboardService"
NULL_IME="com.tim.flip2.nullkeyboard/.NullKeyboardService"
APKS="com.tim.flip2.launcher4 com.tim.flip2.nullkeyboard org.forkgram.classic"
KEYS="keyshortcut_leftkey keyshortcut_rightkey keyshortcut_upkey keyshortcut_downkey keyshortcut_shortcutsbar"

UNINSTALL=0
case "$1" in --uninstall-apks|-u) UNINSTALL=1 ;; esac

echo "== flip2 deroot =="

if su -c true 2>/dev/null; then
  echo "-- rooted: marking flip2 modules for removal"
  for m in $MODS; do
    if [ -d "/data/adb/modules/$m" ]; then
      touch "/data/adb/modules/$m/remove"
      echo "   $m -> removed at next boot"
    fi
  done
  pkill -f 'FlipMouse/service.sh' 2>/dev/null
  pkill -f 'FlipMouse/mouse' 2>/dev/null
  echo "   FlipMouse stopped"
  echo "-- next: Magisk app -> Uninstall -> Restore Images, then reboot"
else
  echo "-- no root: module removal skipped (needs root; do it from the Magisk app)"
fi

echo "-- restoring stock IME ($KIME)"
ime enable "$KIME" >/dev/null 2>&1
ime set "$KIME" >/dev/null 2>&1 || settings put secure default_input_method "$KIME"

echo "-- clearing flip2 settings overrides (back to stock defaults)"
settings delete secure accessibility_soft_keyboard_mode >/dev/null 2>&1
settings delete secure show_ime_with_hard_keyboard >/dev/null 2>&1
for k in $KEYS; do settings delete global "$k" >/dev/null 2>&1; done
appops reset com.tim.flip2.nullkeyboard >/dev/null 2>&1

if [ "$UNINSTALL" = 1 ]; then
  echo "-- uninstalling user APKs"
  ime disable "$NULL_IME" >/dev/null 2>&1
  for p in $APKS; do
    if pm uninstall --user 0 "$p" >/dev/null 2>&1; then
      echo "   removed $p"
    else
      echo "   not installed: $p"
    fi
  done
  echo "   (stock launcher returns once Launcher4 is removed)"
else
  echo "-- user APKs kept; rerun with --uninstall-apks to remove them"
fi

echo "== done =="
if su -c true 2>/dev/null; then
  echo "Reboot, then in the Magisk app: Uninstall -> Restore Images."
else
  echo "Remaining step (needs root): remove flip2 modules + Magisk app ->"
  echo "Uninstall -> Restore Images, then reboot."
fi
