#!/system/bin/sh
# flip2 web setup wizard — on-device installer.
#
# The wizard page (Chrome, WebUSB) verifies every SHA-256 in the browser,
# pushes the checked files into /data/local/flip2/incoming/, pushes this
# script to /data/local/flip2/install.sh, and runs it once as root.
#
# incoming/ contents (names fixed by the page):
#   flip2_nav_overlay-magisk.zip flip2_keypad_backspace-magisk.zip
#   FlipMouse.zip flip2_pixel_tag_drawer-magisk.zip flip2_launcher_overlay-magisk.zip
#     — extracted from the published full installer zip payload/modules/;
#       the page rebuilds the Tag Drawer zip so it embeds the fresh F-Droid APK
#   launcher4.apk nullkeyboard.apk  — payload/apks/ from the same zip
#   forkgram.apk intertune.apk bouncy.apk materialfiles.apk — browser
#     downloads (catalog.json)
#   ggml-tiny-q5_1.bin vosk-model-small-en-us-0.15.zip vosk-model-small-uk-v3-nano.zip
#   headwind.apk — managed profile only, not part of a base push
#
# Install order follows pipeline/deploy/manifest.json (10→90). Stops on the
# first failed step with a "FAIL:" line — the page offers Retry. Idempotent:
# safe to re-run. Never flashes, never wipes, never clears keyshortcuts.
# No wget, no jq: the phone downloads nothing.
#
# /data/local/flip2/profile.list is one component id per line. A missing file
# means the full base install, and does not install Headwind. A listed
# component whose incoming file is missing is still FAIL. This script never
# calls dpm and never wipes the phone.

IN=/data/local/flip2/incoming
STAGE=/data/local/flip2
BB=/data/adb/magisk/busybox
NULL_PKG=com.tim.flip2.nullkeyboard
NULL_IME=com.tim.flip2.nullkeyboard/.NullKeyboardService
HOME_ACT=com.tim.flip2.launcher4/com.android.launcher3.Launcher

fail() { echo "FAIL: $*"; exit 1; }
ok()   { echo "OK: $*"; }

[ "$(id -u)" = 0 ] || exec su -c "sh $0"

[ -d "$IN" ] || fail "incoming dir missing: $IN — the page must push files first"

unzip_any() {
  if unzip -o "$1" -d "$2/" >/dev/null 2>&1; then return 0; fi
  if [ -x "$BB" ]; then "$BB" unzip -o "$1" -d "$2/" >/dev/null 2>&1; return $?; fi
  return 1
}

# --- wait for pm (same loop as installer/service.sh) -----------------------
i=0
until pm list packages >/dev/null 2>&1; do
  i=$((i + 1)); [ "$i" -ge 30 ] && fail "package manager not ready after 60s"
  sleep 2
done

# --- modules, manifest 10-50 (stop FlipMouse first: Text file busy) --------
pkill -f 'FlipMouse/service.sh' 2>/dev/null
pkill -f 'FlipMouse/mouse' 2>/dev/null
sleep 1

# Missing profile.list means the full base install. Headwind is not part of
# that default: an old push has no list and must not install it. An empty
# list matches nothing. Exact line match, CR stripped.
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

# BEGIN GENERATED
place_module() {
  mid=$1; zip=$2
  [ -f "$IN/$zip" ] || fail "module zip missing: $IN/$zip"
  T=/data/adb/modules/$mid
  mkdir -p "$T"
  unzip_any "$IN/$zip" "$T" || fail "could not unpack module: $mid"
  ok "module placed: $mid"
}

if want navoverlay; then
  place_module flip2_nav_overlay              flip2_nav_overlay-magisk.zip
else
  echo "NOTE: skip navoverlay"
fi
if want keypad; then
  place_module flip2_keypad_backspace         flip2_keypad_backspace-magisk.zip
else
  echo "NOTE: skip keypad"
fi
if want flipmouse; then
  place_module FlipMouse                      FlipMouse.zip
else
  echo "NOTE: skip flipmouse"
fi
if want tagdrawer; then
  place_module flip2_pixel_tag_drawer         flip2_pixel_tag_drawer-magisk.zip
else
  echo "NOTE: skip tagdrawer"
fi
if want launcher_overlay; then
  place_module flip2_launcher_overlay         flip2_launcher_overlay-magisk.zip
else
  echo "NOTE: skip launcher_overlay"
fi

if want flipmouse; then
# Nothing starts FlipMouse's daemon until Magisk service time — start it now,
# the way installer/service.sh does.
FM=/data/adb/modules/FlipMouse
[ -x "$FM/mouse" ] || fail "FlipMouse module has no mouse binary"
rm -f "$FM/update"
chmod 755 "$FM/mouse" "$FM/service.sh" 2>/dev/null
chmod 644 "$FM/module.prop" 2>/dev/null
nohup sh "$FM/service.sh" </dev/null >/dev/null 2>&1 &
ok "FlipMouse daemon started"
else
  echo "NOTE: skip flipmouse"
fi

# --- user APKs, manifest 60-80 plus the wizard's own downloads -------------
install_apk() {
  f=$1; pkg=$2
  [ -f "$IN/$f" ] || fail "APK missing: $IN/$f"
  S=$STAGE/$f
  cp "$IN/$f" "$S" && chmod 644 "$S" || fail "could not stage $f"
  pm install -r "$S" >/dev/null 2>&1 || { rm -f "$S"; fail "pm install failed: $pkg ($f)"; }
  rm -f "$S"
  ok "installed: $pkg"
}

if want launcher4; then
  install_apk launcher4.apk          com.tim.flip2.launcher4
else
  echo "NOTE: skip launcher4"
fi
if want ime; then
  install_apk nullkeyboard.apk       com.tim.flip2.nullkeyboard
else
  echo "NOTE: skip ime"
fi
if want forkgram; then
  install_apk forkgram.apk           org.forkgram.classic
else
  echo "NOTE: skip forkgram"
fi
if want materialfiles; then
  install_apk materialfiles.apk      me.zhanghai.android.files
else
  echo "NOTE: skip materialfiles"
fi
if want intertune; then
  install_apk intertune.apk          dev.skye.intertune
else
  echo "NOTE: skip intertune"
fi
if want bouncy; then
  install_apk bouncy.apk             com.dozingcatsoftware.bouncy
else
  echo "NOTE: skip bouncy"
fi

if want ime; then
# --- IME settings (manifest 70): values mirror payload data/settings.txt ---
settings put secure show_ime_with_hard_keyboard '1' \
  || fail "settings: show_ime_with_hard_keyboard"
settings put secure enabled_input_methods "$NULL_IME" \
  || fail "settings: enabled_input_methods"
settings put secure default_input_method "$NULL_IME" \
  || fail "settings: default_input_method"
settings put secure accessibility_soft_keyboard_mode '1' \
  || fail "settings: accessibility_soft_keyboard_mode"
settings put system dtmf_tone '0' \
  || fail "settings: dtmf_tone"
settings put system dtmf_tone_type '0' \
  || fail "settings: dtmf_tone_type"
appops set --user 0 $NULL_PKG WRITE_SETTINGS allow \
  || fail "appops: WRITE_SETTINGS for $NULL_PKG"
pm grant $NULL_PKG android.permission.RECORD_AUDIO \
  || fail "pm grant: RECORD_AUDIO for $NULL_PKG"
ok "IME settings applied"
else
  echo "NOTE: skip ime"
fi

if want home_keys; then
# --- home keys, manifest 90: values mirror launcher-overlay/home-keys.json -
# Quoted: & and $ inside Label-package-component break unquoted args.
settings put global 'keyshortcut_leftkey' 'Intertune-dev.skye.intertune-com.dd3boh.outertune.MainActivity' \
  || fail "keyshortcut_leftkey"
settings put global 'keyshortcut_rightkey' 'Messages-com.android.mms-com.android.mms.ui.ConversationList' \
  || fail "keyshortcut_rightkey"
settings put global 'keyshortcut_shortcutsbar' 'Bluetooth-com.android.settings-com.android.settings.Settings$ConnectedDeviceDashboardActivity' \
  || fail "keyshortcut_shortcutsbar"
settings put global 'keyshortcut_upkey' 'Tags-com.iwadjp.pixeltagdrawer-com.iwadjp.pixeltagdrawer.MainActivity' \
  || fail "keyshortcut_upkey"
settings put global 'keyshortcut_downkey' 'Recents-com.android.systemui-com.tcl.recents.RecentsListActivity' \
  || fail "keyshortcut_downkey"
ok "home keys applied"
else
  echo "NOTE: skip home_keys"
fi

if want display; then
# --- display size, manifest 95: logical 321x428 on the 240x320 panel --------
settings put global 'display_size_forced' '321,428' \
  || fail "settings: display_size_forced"
ok "display size 321x428 (takes effect after reboot)"
else
  echo "NOTE: skip display"
fi

if want wallpaper; then
# --- wallpaper: default background, copied where the framework reads it -----
WP=/data/local/flip2/incoming/flip2-wallpaper.png
WPDST=/data/system/users/0/wallpaper
if [ -f "$WP" ] && [ ! -f "$STAGE/.wallpaper-applied" ]; then
  cp "$WP" "$WPDST" || fail "wallpaper copy"
  chown system:system "$WPDST" 2>/dev/null
  chmod 600 "$WPDST"
  restorecon "$WPDST" 2>/dev/null
  touch "$STAGE/.wallpaper-applied"
  ok "wallpaper installed (shows after reboot)"
else
  echo "NOTE: no flip2-wallpaper.png in incoming/; keeping the current wallpaper"
fi
else
  echo "NOTE: skip wallpaper"
fi

if want launcher4; then
cmd package set-home-activity $HOME_ACT >/dev/null 2>&1 \
  || fail "could not set HOME to launcher4"
ok "HOME set to launcher4"
else
  echo "NOTE: skip launcher4"
fi
# END GENERATED

# Headwind is managed-only and stays outside the generator on purpose.
# Installing the APK does not set device owner. Do not call dpm here.
if want headwind; then
  install_apk headwind.apk com.hmdm.launcher
else
  echo "NOTE: skip headwind"
fi

# --- Whisper ggml: one multilingual bin serves both lang dirs --------------
if want whisper; then
  W=$IN/ggml-tiny-q5_1.bin
  [ -f "$W" ] || fail "whisper model missing: $W"
  for lang in en uk; do
    D=/data/data/$NULL_PKG/files/whisper/$lang
    mkdir -p "$D" || fail "mkdir $D"
    cp "$W" "$D/model.bin" || fail "whisper copy: $lang"
  done
  ok "whisper placed (en, uk)"
else
  echo "NOTE: skip whisper"
fi

# --- Vosk: zips carry an inner top-level dir — flatten it so
# --- files/vosk/<lang>/{am,conf,graph} matches VoskSttHelper.looksLikeModel
place_vosk() {
  name=$1; zip=$2
  [ -f "$IN/$zip" ] || fail "vosk zip missing: $IN/$zip"
  TMP=$STAGE/.vosk-$name
  rm -rf "$TMP"; mkdir -p "$TMP"
  unzip_any "$IN/$zip" "$TMP" || fail "could not unpack vosk: $name"
  SRC=$TMP
  if [ ! -d "$TMP/am" ]; then
    for d in "$TMP"/*/; do
      if [ -d "${d}am" ]; then SRC=${d%/}; break; fi
    done
  fi
  [ -d "$SRC/am" ] || fail "vosk $name: no am/ dir after unpack"
  D=/data/data/$NULL_PKG/files/vosk/$name
  rm -rf "$D"; mkdir -p "$D"
  cp -a "$SRC/." "$D/" || fail "vosk copy: $name"
  rm -rf "$TMP"
  ok "vosk placed: $name"
}

if want vosk; then
  place_vosk en vosk-model-small-en-us-0.15.zip
  place_vosk uk vosk-model-small-uk-v3-nano.zip
else
  echo "NOTE: skip vosk"
fi

# Model ownership and stt_lang follow the speech models and the IME.
# A profile that lists none of them must not fail on a missing model file.
if want whisper || want vosk || want ime; then
  OWNER=$(stat -c %u:%g /data/data/$NULL_PKG 2>/dev/null)
  [ -n "$OWNER" ] || fail "could not stat /data/data/$NULL_PKG"
  if want whisper || want vosk; then
    chown -R "$OWNER" /data/data/$NULL_PKG/files || fail "chown files"
    restorecon -RF /data/data/$NULL_PKG/files 2>/dev/null
    ok "models owned by $OWNER"
  fi
  if want ime; then
    SP=/data/data/$NULL_PKG/shared_prefs
    mkdir -p "$SP" || fail "mkdir $SP"
    cat > "$STAGE/flip2_null_ime.xml" <<XML
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
    <string name="stt_lang">uk</string>
</map>
XML
    cp "$STAGE/flip2_null_ime.xml" "$SP/flip2_null_ime.xml" || fail "stt_lang copy"
    chown "$OWNER" "$SP" "$SP/flip2_null_ime.xml" 2>/dev/null
    chmod 771 "$SP"
    chmod 660 "$SP/flip2_null_ime.xml"
    rm -f "$STAGE/flip2_null_ime.xml"
    restorecon -RF "$SP" 2>/dev/null
    ok "stt_lang=uk"
  else
    echo "NOTE: skip stt_lang"
  fi
else
  echo "NOTE: skip stt_lang"
fi

# incoming/ stays — a Retry re-run needs it; the page cleans up on success.
echo "DONE: install complete"
