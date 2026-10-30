#!/system/bin/sh
# flip2 web setup wizard — on-device verifier.
#
# Run as root after install.sh (and after the reboot pause). Prints one
# PASS/FAIL line per check and exits 0 only when every check passes.
# The page shows the list; a FAIL line names the fix.
#
# /data/local/flip2/profile.list is one component id per line. A missing file
# means the full base checks, and does not require Headwind. A skipped check
# prints NOTE and does not increment FAILS. This script never calls dpm and
# never wipes the phone.

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

# Missing profile.list means the full base checks. Headwind is not part of
# that default. An empty list matches nothing. Exact line match, CR stripped.
PROFILE=/data/local/flip2/profile.list
want() {
  local comp line
  comp=$1
  if [ ! -f "$PROFILE" ]; then
    [ "$comp" = "headwind" ] && return 1
    return 0
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    line=$(printf '%s' "$line" | tr -d '\r')
    [ -n "$line" ] || continue
    [ "$line" = "$comp" ] && return 0
  done < "$PROFILE"
  return 1
}

# --- FlipMouse daemon is running -------------------------------------------
if want flipmouse; then
  if pgrep -f 'FlipMouse/mouse' >/dev/null 2>&1; then
    echo "PASS: FlipMouse daemon running"
    PASS=$((PASS + 1))
  else
    echo "FAIL: FlipMouse daemon running (reboot, or run install.sh again)"
    FAILS=$((FAILS + 1))
  fi
else
  echo "NOTE: skip flipmouse"
fi

# --- Null Keyboard is the default IME ---------------------------------------
if want ime; then
  IME=$(settings get secure default_input_method 2>/dev/null)
  if [ "$IME" = "$NULL_IME" ]; then
    echo "PASS: default IME is Null Keyboard"
    PASS=$((PASS + 1))
  else
    echo "FAIL: default IME is '$IME' (expected $NULL_IME)"
    FAILS=$((FAILS + 1))
  fi
else
  echo "NOTE: skip ime"
fi

# --- Home is Launcher4 -------------------------------------------------------
if want launcher4; then
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
else
  echo "NOTE: skip launcher4"
fi

# BEGIN GENERATED
# --- Apps installed (manifest full|wizard user-apk labels) ----------------
if want launcher4; then
  check "Launcher4 installed" pm path com.tim.flip2.launcher4
else
  echo "NOTE: skip launcher4"
fi
if want ime; then
  check "Null Keyboard installed" pm path com.tim.flip2.nullkeyboard
else
  echo "NOTE: skip ime"
fi
if want forkgram; then
  check "Forkgram installed" pm path org.forkgram.classic
else
  echo "NOTE: skip forkgram"
fi
if want materialfiles; then
  check "Material Files installed" pm path me.zhanghai.android.files
else
  echo "NOTE: skip materialfiles"
fi
if want intertune; then
  check "Intertune installed" pm path dev.skye.intertune
else
  echo "NOTE: skip intertune"
fi
if want bouncy; then
  check "Bouncy Ball installed" pm path com.dozingcatsoftware.bouncy
else
  echo "NOTE: skip bouncy"
fi
if want tagdrawer; then
  check "Tag Drawer installed" pm path com.iwadjp.pixeltagdrawer
else
  echo "NOTE: skip tagdrawer"
fi

if want home_keys; then
# --- The five keyshortcuts match home-keys.json -------------------------------
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
else
  echo "NOTE: skip home_keys"
fi

if want display; then
# --- Display size (logical 321x428 on the 240x320 panel) ----------------------
SIZE=$(settings get global display_size_forced 2>/dev/null)
if [ "$SIZE" = "321,428" ]; then
  echo "PASS: display_size_forced=321,428"
  PASS=$((PASS + 1))
else
  echo "FAIL: display_size_forced is '$SIZE' (expected 321,428)"
  FAILS=$((FAILS + 1))
fi
else
  echo "NOTE: skip display"
fi
# END GENERATED

# Headwind is managed-only and stays outside the generator on purpose.
if want headwind; then
  check "Headwind MDM installed" pm path com.hmdm.launcher
else
  echo "NOTE: skip headwind"
fi

# --- Speech models exist (Whisper bin in both langs, Vosk am/conf/graph) -----
if want whisper; then
  for lang in en uk; do
    check "whisper $lang model" test -s "/data/data/$NULL_PKG/files/whisper/$lang/model.bin"
  done
else
  echo "NOTE: skip whisper"
fi
if want vosk; then
  for lang in en uk; do
    for sub in am conf graph; do
      check "vosk $lang/$sub" test -e "/data/data/$NULL_PKG/files/vosk/$lang/$sub"
    done
  done
else
  echo "NOTE: skip vosk"
fi

# --- stt_lang=uk --------------------------------------------------------------
if want ime; then
  LANG_NOW=$(grep stt_lang "/data/data/$NULL_PKG/shared_prefs/flip2_null_ime.xml" 2>/dev/null \
    | sed 's/.*>\([^<]*\)<.*/\1/')
  if [ "$LANG_NOW" = "uk" ]; then
    echo "PASS: stt_lang=uk"
    PASS=$((PASS + 1))
  else
    echo "FAIL: stt_lang='$LANG_NOW' (expected uk)"
    FAILS=$((FAILS + 1))
  fi
else
  echo "NOTE: skip stt_lang"
fi

# --- IME-related settings ------------------------------------------------------
# accessibility_soft_keyboard_mode is deliberately NOT a check: TCL's
# system_server force-reverts it to 0 within seconds (dumpsys shows the value
# owned by pkg:android), and pipeline/ime/ime.sh treats it as best-effort too.
# Null Keyboard draws no soft keyboard, so the revert is cosmetic.
if want ime; then
  for entry in \
    'show_ime_with_hard_keyboard secure 1' \
    'dtmf_tone system 0' \
    'dtmf_tone_type system 0'; do
    set -- $entry
    key=$1; ns=$2; expected=$3
    got=$(settings get "$ns" "$key" 2>/dev/null)
    if [ "$got" = "$expected" ]; then
      echo "PASS: $key=$expected"
      PASS=$((PASS + 1))
    else
      echo "FAIL: $key is '$got' (expected $expected)"
      FAILS=$((FAILS + 1))
    fi
  done
  SKB=$(settings get secure accessibility_soft_keyboard_mode 2>/dev/null)
  echo "NOTE: accessibility_soft_keyboard_mode=$SKB (TCL reverts this; harmless)"
else
  echo "NOTE: skip ime settings"
fi

# --- Wallpaper (optional: only checked when the installer shipped an asset) --
# This ROM has no `cmd wallpaper`; the file at /data/system/users/0/wallpaper is
# what the framework loads at boot. A phone that was installed before the asset
# existed keeps whatever wallpaper the user has, so absence is a NOTE.
if want wallpaper; then
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
else
  echo "NOTE: skip wallpaper"
fi

echo ""
echo "SUMMARY: $PASS passed, $FAILS failed"
[ "$FAILS" -eq 0 ] && exit 0
echo "RETRY: fix the FAIL lines above, then run verify.sh again"
exit 1
