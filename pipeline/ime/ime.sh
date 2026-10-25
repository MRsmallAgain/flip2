#!/usr/bin/env bash
# Flip2 chat IME: Kika shows Abc + candidate bar and breaks backspace on hardware keypad.
# hide-bar: Flip2 Null Keyboard — zero UI, T9 + symbols + offline Vosk STT (EN/UK).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/lib/bootstrap.sh"

KIKA_PKG="${FLIP2_KIKA_IME_PKG:-com.iqqijni.dvt912key}"
KIKA_IME="com.iqqijni.dvt912key/.keyboard_service.view.HDKeyboardService"
NULL_PKG="${FLIP2_NULL_IME_PKG:-com.tim.flip2.nullkeyboard}"
NULL_IME="com.tim.flip2.nullkeyboard/.NullKeyboardService"
NULL_APK="$ROOT/pipeline/ime/null-keyboard/dist/nullkeyboard.apk"
NULL_BUILD="$ROOT/pipeline/ime/null-keyboard/build.sh"
NULL_DIR="$ROOT/pipeline/ime/null-keyboard"
MODEL_HOST_EN="$NULL_DIR/models/en"
MODEL_HOST_UK="$NULL_DIR/models/uk"
# App-private path (SELinux-safe for IME uid). /data/local/flip2/vosk is system_data_file.
MODEL_DEVICE_ROOT="/data/data/$NULL_PKG/files/vosk"

usage() {
  cat <<EOF
Usage: flip2 ime <subcommand>

  hide-bar    Install/set Flip2 Null Keyboard (no Abc bar, hardware backspace in chat)
  restore     Default back to stock Kika 12Key IME
  status      IME packages, default_input_method, STT models/lang
  build       Build nullkeyboard.apk (needs JDK — see pipeline/ime/null-keyboard/build.sh)
  models      Push EN+UK Vosk models to device + grant RECORD_AUDIO
  lang [en|uk]  Show or set STT language

STT: hold * to listen (Vosk offline). While listening: # = EN↔UK, * = stop.
Models stay on-device (~40MB EN + ~75MB UK), not inside the APK.
EOF
}

ensure_built() {
  if [[ ! -f "$NULL_APK" ]]; then
    echo "Building null keyboard…" >&2
    export JAVA_HOME="${JAVA_HOME:-$HOME/.local/opt/jdk17}"
    export PATH="$JAVA_HOME/bin:$PATH"
    "$NULL_BUILD"
  fi
}

grant_mic() {
  adb shell pm grant "$NULL_PKG" android.permission.RECORD_AUDIO 2>/dev/null \
    || adb shell "su -c 'pm grant $NULL_PKG android.permission.RECORD_AUDIO'" 2>/dev/null \
    || echo "WARN: could not grant RECORD_AUDIO — grant manually" >&2
}

push_models() {
  local en_src uk_src owner
  en_src="$(readlink -f "$MODEL_HOST_EN" 2>/dev/null || true)"
  uk_src="$(readlink -f "$MODEL_HOST_UK" 2>/dev/null || true)"
  [[ -d "$en_src" ]] || { echo "Missing EN model at $MODEL_HOST_EN (symlink to cache)" >&2; exit 1; }
  [[ -d "$uk_src" ]] || { echo "Missing UK model at $MODEL_HOST_UK (symlink to cache)" >&2; exit 1; }

  echo "Pushing Vosk models -> $MODEL_DEVICE_ROOT/{en,uk}"
  owner="$(adb shell "su -c 'stat -c %u:%g /data/data/$NULL_PKG'" 2>/dev/null | tr -d '\r')"
  [[ -n "$owner" ]] || owner="u0_a116:u0_a116"

  adb shell "rm -rf /sdcard/Download/flip2-vosk && mkdir -p /sdcard/Download/flip2-vosk" >/dev/null
  echo "  EN..."
  adb push "$en_src" /sdcard/Download/flip2-vosk/en >/dev/null
  echo "  UK..."
  adb push "$uk_src" /sdcard/Download/flip2-vosk/uk >/dev/null

  # Copy into app files dir and chown to package uid (correct SELinux label via restorecon)
  adb shell "su -c 'mkdir -p /data/data/$NULL_PKG/files; rm -rf $MODEL_DEVICE_ROOT; mkdir -p $MODEL_DEVICE_ROOT; cp -a /sdcard/Download/flip2-vosk/en $MODEL_DEVICE_ROOT/en; cp -a /sdcard/Download/flip2-vosk/uk $MODEL_DEVICE_ROOT/uk; chown -R $owner /data/data/$NULL_PKG/files; restorecon -RF /data/data/$NULL_PKG/files 2>/dev/null || true; rm -rf /sdcard/Download/flip2-vosk'" >/dev/null
  grant_mic
  echo "Models on device:"
  adb shell "su -c 'du -sh $MODEL_DEVICE_ROOT/en $MODEL_DEVICE_ROOT/uk'" 2>/dev/null | tr -d '\r'
  adb shell "su -c 'ls -Za $MODEL_DEVICE_ROOT/en/am/final.mdl 2>/dev/null | head -1'" 2>/dev/null | tr -d '\r'
}
set_lang() {
  local lang="${1:-}"
  case "$lang" in
    en|uk) ;;
    *) echo "Usage: flip2 ime lang [en|uk]" >&2; exit 1 ;;
  esac
  local owner
  owner="$(adb shell "su -c 'stat -c %u:%g /data/data/$NULL_PKG'" 2>/dev/null | tr -d '\r')"
  adb shell "su -c 'mkdir -p /data/data/$NULL_PKG/shared_prefs'" >/dev/null
  # Write prefs via a staged file to avoid nested-heredoc quoting pain
  adb shell "cat > /sdcard/Download/flip2_null_ime.xml" <<XML
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
    <string name="stt_lang">$lang</string>
</map>
XML
  adb shell "su -c 'cp /sdcard/Download/flip2_null_ime.xml /data/data/$NULL_PKG/shared_prefs/flip2_null_ime.xml; chown ${owner:-system:system} /data/data/$NULL_PKG/shared_prefs /data/data/$NULL_PKG/shared_prefs/flip2_null_ime.xml 2>/dev/null || true; chmod 771 /data/data/$NULL_PKG/shared_prefs; chmod 660 /data/data/$NULL_PKG/shared_prefs/flip2_null_ime.xml; rm -f /sdcard/Download/flip2_null_ime.xml'" >/dev/null
  echo "STT language set to: $lang"
}

get_lang() {
  adb shell "su -c 'grep stt_lang /data/data/$NULL_PKG/shared_prefs/flip2_null_ime.xml 2>/dev/null'" \
    | tr -d '\r' || echo "(default en — prefs not set yet)"
}

cmd="${1:-help}"
shift || true

case "$cmd" in
  help|-h|--help)
    usage
    ;;
  build)
    export JAVA_HOME="${JAVA_HOME:-$HOME/.local/opt/jdk17}"
    export PATH="$JAVA_HOME/bin:$PATH"
    exec "$NULL_BUILD"
    ;;
  models)
    flip2_adb_require_device
    push_models
    ;;
  lang)
    flip2_adb_require_device
    if [[ $# -eq 0 ]]; then
      echo -n "stt_lang: "
      get_lang
    else
      set_lang "$1"
    fi
    ;;
  hide-bar)
    flip2_adb_require_device
    ensure_built
    adb install -r "$NULL_APK" >/dev/null
    grant_mic
    # Matrix * / # DTMF spam while typing (IME cannot always write Settings.System).
    adb shell settings put system dtmf_tone 0 2>/dev/null || true
    adb shell settings put system dtmf_tone_type 0 2>/dev/null || true
    # Route matrix BACK / keypad to null IME (onKeyPreIme); zero UI height still hides bar.
    adb shell settings put secure show_ime_with_hard_keyboard 1
    adb shell settings put global show_ime_with_hard_keyboard 1 2>/dev/null || true
    adb shell settings put secure enabled_input_methods "$NULL_IME"
    adb shell settings put secure default_input_method "$NULL_IME"
    adb shell settings put secure accessibility_soft_keyboard_mode 1 2>/dev/null || true
    adb shell pm disable-user --user 0 "$KIKA_PKG" 2>/dev/null || true
    if ! adb shell "su -c 'test -d $MODEL_DEVICE_ROOT/en/am && test -d $MODEL_DEVICE_ROOT/uk/am'" >/dev/null 2>&1; then
      echo "STT models not on device — pushing…"
      push_models
    fi
    echo "Default IME: Flip2 Null Keyboard. Kika disabled."
    echo "STT: hold * to dictate (EN/UK). While listening: # = switch lang, * = stop."
    echo "Force-stop chat app and reopen a thread."
    echo "Restore stock: flip2 ime restore"
    ;;
  restore)
    flip2_adb_require_device
    adb shell pm enable "$KIKA_PKG"
    adb shell settings put system dtmf_tone 1 2>/dev/null || true
    adb shell settings put secure show_ime_with_hard_keyboard 1
    adb shell settings put global show_ime_with_hard_keyboard 1 2>/dev/null || true
    adb shell settings put secure enabled_input_methods "$KIKA_IME"
    adb shell settings put secure default_input_method "$KIKA_IME"
    adb shell settings put secure accessibility_soft_keyboard_mode 0 2>/dev/null || true
    echo "Kika restored as default IME."
    ;;
  status)
    flip2_adb_require_device
    echo -n "default_input_method: "
    adb shell settings get secure default_input_method 2>/dev/null || echo "?"
    echo -n "show_ime_with_hard_keyboard (secure): "
    adb shell settings get secure show_ime_with_hard_keyboard 2>/dev/null || echo "?"
    adb shell pm path "$NULL_PKG" >/dev/null 2>&1 && echo "Null keyboard: installed" || echo "Null keyboard: not installed"
    if adb shell pm list packages -d 2>/dev/null | grep -q "$KIKA_PKG"; then
      echo "Kika IME: disabled"
    elif adb shell pm path "$KIKA_PKG" >/dev/null 2>&1; then
      echo "Kika IME: enabled"
    else
      echo "Kika IME: not installed"
    fi
    echo -n "RECORD_AUDIO: "
    adb shell dumpsys package "$NULL_PKG" 2>/dev/null \
      | grep -A1 'android.permission.RECORD_AUDIO' | head -2 | tr -d '\r' || echo "?"
    echo -n "stt_lang: "
    get_lang
    echo "STT models:"
    adb shell "su -c 'du -sh $MODEL_DEVICE_ROOT/en $MODEL_DEVICE_ROOT/uk 2>/dev/null || echo missing'" 2>/dev/null | tr -d '\r' || echo "  (none — flip2 ime models)"
    adb shell "dumpsys input_method 2>/dev/null | grep -E 'mCurId|CandidatesView|InputViewShown' | head -5" 2>/dev/null || true
    ;;
  *)
    echo "Unknown ime subcommand: $cmd" >&2
    usage >&2
    exit 1
    ;;
esac
