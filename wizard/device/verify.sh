#!/system/bin/sh
# flip2 web setup wizard — on-device verifier.
#
# Run as root after install.sh (and after the reboot pause). Prints one
# PASS/FAIL line per check and exits 0 only when every check passes.
# The page shows the list; a FAIL line names the fix.

NULL_PKG=com.tim.flip2.nullkeyboard
NULL_IME=com.tim.flip2.nullkeyboard/.NullKeyboardService
HOME_ACT=com.tim.flip2.launcher4/com.android.launcher3.Launcher

[ "$(id -u)" = 0 ] || exec su -c "sh $0"

PASS=0
FAILS=0

check() {  # check <label> <command...>
  label=$1; shift
  if "$@" >/dev/null 2>&1; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label"
    FAILS=$((FAILS + 1))
  fi
}

# --- FlipMouse daemon is running -------------------------------------------
if pgrep -f 'FlipMouse/mouse' >/dev/null 2>&1; then
  echo "PASS: FlipMouse daemon running"
  PASS=$((PASS + 1))
else
  echo "FAIL: FlipMouse daemon running (reboot, or run install.sh again)"
  FAILS=$((FAILS + 1))
fi

# --- Null Keyboard is the default IME ---------------------------------------
IME=$(settings get secure default_input_method 2>/dev/null)
if [ "$IME" = "$NULL_IME" ]; then
  echo "PASS: default IME is Null Keyboard"
  PASS=$((PASS + 1))
else
  echo "FAIL: default IME is '$IME' (expected $NULL_IME)"
  FAILS=$((FAILS + 1))
fi

# --- Home is Launcher4 -------------------------------------------------------
HOME_NOW=$(cmd package resolve-activity --brief -c android.intent.category.HOME \
  -a android.intent.action.MAIN 2>/dev/null | tail -n 1)
case "$HOME_NOW" in
  com.tim.flip2.launcher4/*)
    echo "PASS: Home is Launcher4"
    PASS=$((PASS + 1))
    ;;
  *)
    echo "FAIL: Home is '$HOME_NOW' (expected $HOME_ACT)"
    FAILS=$((FAILS + 1))
    ;;
esac

# --- Apps installed -----------------------------------------------------------
for entry in \
  'Intertune dev.skye.intertune' \
  'Bouncy com.dozingcatsoftware.bouncy' \
  'Forkgram org.forkgram.classic' \
  'Tag Drawer com.iwadjp.pixeltagdrawer' \
  'Material Files me.zhanghai.android.files' \
  'Launcher4 com.tim.flip2.launcher4' \
  'Null Keyboard com.tim.flip2.nullkeyboard'; do
  pkg=${entry##* }; label=${entry% *}
  check "$label installed" pm path "$pkg"
done

# --- Speech models exist (Whisper bin in both langs, Vosk am/conf/graph) -----
for lang in en uk; do
  check "whisper $lang model" test -s "/data/data/$NULL_PKG/files/whisper/$lang/model.bin"
done
for lang in en uk; do
  for sub in am conf graph; do
    check "vosk $lang/$sub" test -e "/data/data/$NULL_PKG/files/vosk/$lang/$sub"
  done
done

# --- stt_lang=uk --------------------------------------------------------------
LANG_NOW=$(grep stt_lang "/data/data/$NULL_PKG/shared_prefs/flip2_null_ime.xml" 2>/dev/null \
  | sed 's/.*>\([^<]*\)<.*/\1/')
if [ "$LANG_NOW" = "uk" ]; then
  echo "PASS: stt_lang=uk"
  PASS=$((PASS + 1))
else
  echo "FAIL: stt_lang='$LANG_NOW' (expected uk)"
  FAILS=$((FAILS + 1))
fi

# --- The five keyshortcuts match home-keys.json -------------------------------
# Same values launcher-overlay/home-keys.json pins (== installer settings.txt).
expect_leftkey='Intertune-dev.skye.intertune-com.dd3boh.outertune.MainActivity'
expect_rightkey='Messages-com.android.mms-com.android.mms.ui.ConversationList'
expect_shortcutsbar='Bluetooth-com.android.settings-com.android.settings.Settings$ConnectedDeviceDashboardActivity'
expect_upkey='Tags-com.iwadjp.pixeltagdrawer-com.iwadjp.pixeltagdrawer.MainActivity'
expect_downkey='Recents-com.android.systemui-com.tcl.recents.RecentsListActivity'
for entry in \
  "leftkey $expect_leftkey" \
  "rightkey $expect_rightkey" \
  "shortcutsbar $expect_shortcutsbar" \
  "upkey $expect_upkey" \
  "downkey $expect_downkey"; do
  name=${entry%% *}; expect=${entry#* }
  got=$(settings get global "keyshortcut_$name" 2>/dev/null)
  if [ "$got" = "$expect" ]; then
    echo "PASS: keyshortcut_$name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: keyshortcut_$name is '$got'"
    FAILS=$((FAILS + 1))
  fi
done

# --- IME-related settings ------------------------------------------------------
# accessibility_soft_keyboard_mode is deliberately NOT a check: TCL's
# system_server force-reverts it to 0 within seconds (dumpsys shows the value
# owned by pkg:android), and pipeline/ime/ime.sh treats it as best-effort too.
# Null Keyboard draws no soft keyboard, so the revert is cosmetic.
for entry in \
  'show_ime_with_hard_keyboard secure 1' \
  'dtmf_tone system 0' \
  'dtmf_tone_type system 0'; do
  set -- $entry
  key=$1; ns=$2; want=$3
  got=$(settings get "$ns" "$key" 2>/dev/null)
  if [ "$got" = "$want" ]; then
    echo "PASS: $key=$want"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $key is '$got' (expected $want)"
    FAILS=$((FAILS + 1))
  fi
done
SKB=$(settings get secure accessibility_soft_keyboard_mode 2>/dev/null)
echo "NOTE: accessibility_soft_keyboard_mode=$SKB (TCL reverts this; harmless)"

# --- Display size (logical 321x428 on the 240x320 panel) ----------------------
# Checked against the persisted setting rather than `wm size`, because the
# override only becomes an active size at the next boot; a phone whose reboot
# has not happened yet still reports `Physical size` only.
SIZE=$(settings get global display_size_forced 2>/dev/null)
if [ "$SIZE" = "321,428" ]; then
  echo "PASS: display_size_forced=321,428"
  PASS=$((PASS + 1))
else
  echo "FAIL: display_size_forced is '$SIZE' (expected 321,428; set it in Settings → Display or reboot)"
  FAILS=$((FAILS + 1))
fi

# --- Wallpaper (optional: only checked when the installer shipped an asset) --
# This ROM has no `cmd wallpaper`; the file at /data/system/users/0/wallpaper is
# what the framework loads at boot. A phone that was installed before the asset
# existed keeps whatever wallpaper the user has, so absence is a NOTE.
WP_DEV=/data/system/users/0/wallpaper
WP_HOST=/data/local/flip2/incoming/flip2-wallpaper.png
if [ -f "$WP_HOST" ]; then
  if [ -f "$WP_DEV" ] && cmp -s "$WP_HOST" "$WP_DEV"; then
    echo "PASS: wallpaper is the flip2 default"
    PASS=$((PASS + 1))
  else
    echo "FAIL: wallpaper does not match the shipped flip2-wallpaper.png (reboot, or apply with 'flip2 wallpaper apply')"
    FAILS=$((FAILS + 1))
  fi
else
  echo "NOTE: no shipped wallpaper asset in incoming/; skipping that check"
fi

echo ""
echo "SUMMARY: $PASS passed, $FAILS failed"
[ "$FAILS" -eq 0 ] && exit 0
echo "RETRY: fix the FAIL lines above, then run verify.sh again"
exit 1
