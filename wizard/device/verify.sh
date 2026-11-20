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
# BEGIN GENERATED PATHS
# --- on-device paths (generated from pipeline/wizard/device-paths.json) ------
PROFILE=/data/local/flip2/profile.list
WP_DEV=/data/system/users/0/wallpaper
# END GENERATED PATHS
want() {
  local comp line
  comp=$1
  if [ ! -f "$PROFILE" ]; then
    case "$comp" in
      headwind|where|block_camera|enable_camera|block_browser|enable_browser) return 1 ;;
    esac
    return 0
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    line=$(printf '%s' "$line" | tr -d '\r')
    [ -n "$line" ] || continue
    [ "$line" = "$comp" ] && return 0
  done < "$PROFILE"
  return 1
}

# --- mouse daemon (FlipMouse base vs flip2burnMouse arcade) -------------------
check_mouse_legacy() {
  leg=$1
  if [ ! -d "/data/adb/modules/$leg" ]; then
    echo "PASS: $leg not installed (expected)"
    PASS=$((PASS + 1))
  elif [ -f "/data/adb/modules/$leg/disable" ]; then
    echo "PASS: $leg disabled"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $leg still enabled — install.sh should clear the other stack"
    FAILS=$((FAILS + 1))
  fi
}
if want flipmouse; then
  FM_WANT=/data/adb/modules/FlipMouse
  if pgrep -f "$FM_WANT/mouse" >/dev/null 2>&1; then
    echo "PASS: FlipMouse daemon running"
    PASS=$((PASS + 1))
  else
    echo "FAIL: FlipMouse daemon running (reboot, or run install.sh again)"
    FAILS=$((FAILS + 1))
  fi
  check_mouse_legacy flip2burnMouse
  check_mouse_legacy FlipMouseArcade
elif want flip2burn_mouse; then
  FM_WANT=/data/adb/modules/flip2burnMouse
  if pgrep -f "$FM_WANT/mouse" >/dev/null 2>&1; then
    echo "PASS: flip2burnMouse daemon running"
    PASS=$((PASS + 1))
  else
    echo "FAIL: flip2burnMouse daemon running (reboot, or run install.sh again)"
    FAILS=$((FAILS + 1))
  fi
  check_mouse_legacy FlipMouse
  check_mouse_legacy FlipMouseArcade
else
  echo "NOTE: skip mouse module"
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
if want appshelf; then
  check "AppShelf installed" pm path io.github.xtratter.appshelf
else
  echo "NOTE: skip appshelf"
fi
if want fdroid_basic; then
  check "F-Droid Basic installed" pm path org.fdroid.basic
else
  echo "NOTE: skip fdroid_basic"
fi
if want newpipe; then
  check "NewPipe installed" pm path org.schabi.newpipe
else
  echo "NOTE: skip newpipe"
fi
if want vlc; then
  check "VLC installed" pm path org.videolan.vlc
else
  echo "NOTE: skip vlc"
fi
if want astro_loop; then
  check "Astro Loop installed" pm path com.astroloop.game
else
  echo "NOTE: skip astro_loop"
fi
if want scummvm; then
  check "ScummVM installed" pm path org.scummvm.scummvm
else
  echo "NOTE: skip scummvm"
fi
if want shattered_pd; then
  check "Shattered Pixel Dungeon installed" pm path com.shatteredpixel.shatteredpixeldungeon
else
  echo "NOTE: skip shattered_pd"
fi
if want tagdrawer; then
  tagdrawer_ok=0
  if pm path com.iwadjp.pixeltagdrawer >/dev/null 2>&1; then
    tagdrawer_ok=1
  elif pm list packages com.iwadjp.pixeltagdrawer 2>/dev/null | grep -q com.iwadjp.pixeltagdrawer; then
    tagdrawer_ok=1
  elif [ -f /system/app/PixelTagDrawer/PixelTagDrawer.apk ]; then
    tagdrawer_ok=1
  elif [ -f /data/adb/modules/flip2_pixel_tag_drawer/system/app/PixelTagDrawer/PixelTagDrawer.apk ]; then
    tagdrawer_ok=1
  fi
  if [ "$tagdrawer_ok" -eq 1 ]; then
    echo "PASS: Tag Drawer installed"
    PASS=$((PASS + 1))
  else
    echo "FAIL: Tag Drawer installed (place flip2_pixel_tag_drawer module and reboot)"
    FAILS=$((FAILS + 1))
  fi
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

if want wallpaper; then
# --- Wallpaper: a preference, so a mismatch is a NOTE, never a FAIL ----------
# See docs/WALLPAPER.md: install.sh fills an empty slot and leaves an existing
# file alone, so 'differs from the default' is the expected result for anyone
# who chose their own image. 'flip2 wallpaper apply' is the deliberate override.
WP_DEFAULT_MD5=d0eb46bc33e2751940150abf72b93c5f
if [ ! -f "$WP_DEV" ]; then
  echo "NOTE: no wallpaper file yet (install fills an empty slot; a reboot may be pending)"
else
  WP_NOW=$(md5sum "$WP_DEV" 2>/dev/null | cut -d' ' -f1)
  if [ "$WP_NOW" = "$WP_DEFAULT_MD5" ]; then
    echo "PASS: wallpaper is the flip2 default"
    PASS=$((PASS + 1))
  else
    echo "NOTE: this phone has its own wallpaper — fine (flip2 wallpaper apply restores the default)"
  fi
fi
else
  echo "NOTE: skip wallpaper"
fi
# END GENERATED

# Headwind is managed-only and stays outside the generator on purpose.
if want headwind; then
  check "Headwind MDM installed" pm path com.hmdm.launcher
else
  echo "NOTE: skip headwind"
fi

if want where; then
  check "Where installed" pm path net.af0.where
else
  echo "NOTE: skip where"
fi

# enabled=3 is disabled for the user. enabled=0/1 is on.
pkg_user_disabled() {
  dumpsys package "$1" 2>/dev/null | grep -q 'enabled=3'
}

if want block_camera; then
  if pm path com.tcl.camera >/dev/null 2>&1 && pkg_user_disabled com.tcl.camera; then
    echo "PASS: camera disabled"
    PASS=$((PASS + 1))
  else
    echo "FAIL: camera disabled"
    FAILS=$((FAILS + 1))
  fi
elif want enable_camera; then
  if pm path com.tcl.camera >/dev/null 2>&1 && ! pkg_user_disabled com.tcl.camera; then
    echo "PASS: camera enabled"
    PASS=$((PASS + 1))
  else
    echo "FAIL: camera enabled"
    FAILS=$((FAILS + 1))
  fi
else
  echo "NOTE: skip camera"
fi

if want block_browser; then
  for pkg in org.chromium.chrome com.mediatek.op07.browser; do
    if pm path "$pkg" >/dev/null 2>&1 && pkg_user_disabled "$pkg"; then
      echo "PASS: $pkg disabled"
      PASS=$((PASS + 1))
    elif ! pm path "$pkg" >/dev/null 2>&1; then
      echo "NOTE: $pkg not installed"
    else
      echo "FAIL: $pkg disabled"
      FAILS=$((FAILS + 1))
    fi
  done
elif want enable_browser; then
  for pkg in org.chromium.chrome com.mediatek.op07.browser; do
    if pm path "$pkg" >/dev/null 2>&1 && ! pkg_user_disabled "$pkg"; then
      echo "PASS: $pkg enabled"
      PASS=$((PASS + 1))
    elif ! pm path "$pkg" >/dev/null 2>&1; then
      echo "NOTE: $pkg not installed"
    else
      echo "FAIL: $pkg enabled"
      FAILS=$((FAILS + 1))
    fi
  done
else
  echo "NOTE: skip browser"
fi

# --- Sherpa-ONNX models (tokens.txt per lang) ---------------------------------
if want sherpa-en; then
  check "sherpa en model" test -s "/data/data/$NULL_PKG/files/sherpa/en/tokens.txt"
else
  echo "NOTE: skip sherpa-en"
fi
if want sherpa-uk; then
  check "sherpa uk model" test -s "/data/data/$NULL_PKG/files/sherpa/uk/tokens.txt"
else
  echo "NOTE: skip sherpa-uk"
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

# The wallpaper check is generated (pipeline/wizard/render.sh, gen_verify): it
# compares the live file against the default's md5, baked in at render time
# because cleanup consumes incoming/ before verify runs. A phone showing its
# own background is the correct end state there — NOTE, never FAIL.

echo ""
echo "SUMMARY: $PASS passed, $FAILS failed"
[ "$FAILS" -eq 0 ] && exit 0
echo "RETRY: fix the FAIL lines above, then run verify.sh again"
exit 1
