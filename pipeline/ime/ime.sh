#!/usr/bin/env bash
# Flip2 chat IME: Kika shows Abc + candidate bar and breaks backspace on hardware keypad.
# hide-bar: Flip2 Null Keyboard — zero UI, T9 + symbols + offline STT (Sherpa-ONNX; EN/UK).
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
MODEL_DEVICE_ROOT="/data/data/$NULL_PKG/files/sherpa"
FETCH_MODELS="$NULL_DIR/models/fetch-sherpa-models.sh"

usage() {
  cat <<EOF
Usage: flip2 ime <subcommand>

  hide-bar    Install/set Flip2 Null Keyboard (no Abc bar, hardware backspace in chat)
  restore     Default back to stock Kika 12Key IME
  status      IME packages, default_input_method, STT models/lang
  build       Build nullkeyboard.apk (run vendor/fetch-sherpa.sh first)
  sherpa      Fetch host models (if needed) and push EN+UK Sherpa-ONNX to device
  fetch-models  Download EN+UK model tarballs to pipeline/ime/null-keyboard/models/
  lang [en|uk]  Show or set STT language

STT: hold * to listen (Sherpa-ONNX streaming). While listening: # = EN↔UK, * = stop.
Models stay on-device under files/sherpa/{en,uk}, not inside the APK.
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
  adb shell cmd appops set "$NULL_PKG" WRITE_SETTINGS allow 2>/dev/null \
    || adb shell "su -c 'cmd appops set $NULL_PKG WRITE_SETTINGS allow'" 2>/dev/null \
    || echo "WARN: could not grant WRITE_SETTINGS appop — DTMF muting disabled" >&2
}

ensure_host_models() {
  [[ -f "$MODEL_HOST_EN/tokens.txt" && -f "$MODEL_HOST_UK/tokens.txt" ]] && return 0
  [[ -x "$FETCH_MODELS" ]] || { echo "Missing $FETCH_MODELS" >&2; exit 1; }
  bash "$FETCH_MODELS"
}

push_sherpa() {
  ensure_host_models
  local en_src uk_src owner
  en_src="$(readlink -f "$MODEL_HOST_EN" 2>/dev/null || echo "$MODEL_HOST_EN")"
  uk_src="$(readlink -f "$MODEL_HOST_UK" 2>/dev/null || echo "$MODEL_HOST_UK")"
  [[ -f "$en_src/tokens.txt" ]] || { echo "Missing EN Sherpa model at $MODEL_HOST_EN" >&2; exit 1; }
  [[ -f "$uk_src/tokens.txt" ]] || { echo "Missing UK Sherpa model at $MODEL_HOST_UK" >&2; exit 1; }

  echo "Pushing Sherpa models -> $MODEL_DEVICE_ROOT/{en,uk}"
  owner="$(adb shell "su -c 'stat -c %u:%g /data/data/$NULL_PKG'" 2>/dev/null | tr -d '\r')"
  [[ -n "$owner" ]] || owner="u0_a116:u0_a116"

  adb shell "rm -rf /sdcard/Download/flip2-sherpa && mkdir -p /sdcard/Download/flip2-sherpa" >/dev/null
  echo "  EN..."
  adb push "$en_src" /sdcard/Download/flip2-sherpa/en >/dev/null
  echo "  UK..."
  adb push "$uk_src" /sdcard/Download/flip2-sherpa/uk >/dev/null

  adb shell "su -c 'mkdir -p /data/data/$NULL_PKG/files; rm -rf $MODEL_DEVICE_ROOT; mkdir -p $MODEL_DEVICE_ROOT; cp -a /sdcard/Download/flip2-sherpa/en $MODEL_DEVICE_ROOT/en; cp -a /sdcard/Download/flip2-sherpa/uk $MODEL_DEVICE_ROOT/uk; chown -R $owner /data/data/$NULL_PKG/files; restorecon -RF /data/data/$NULL_PKG/files 2>/dev/null || true; rm -rf /sdcard/Download/flip2-sherpa'" >/dev/null
  grant_mic
  echo "Sherpa models on device:"
  adb shell "su -c 'du -sh $MODEL_DEVICE_ROOT/en $MODEL_DEVICE_ROOT/uk'" 2>/dev/null | tr -d '\r'
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

sherpa_on_device() {
  adb shell "su -c 'test -f $MODEL_DEVICE_ROOT/en/tokens.txt && test -f $MODEL_DEVICE_ROOT/uk/tokens.txt'" >/dev/null 2>&1
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
  fetch-models)
    bash "$FETCH_MODELS"
    ;;
  sherpa|models)
    flip2_adb_require_device
    push_sherpa
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
    adb shell settings put system dtmf_tone 0 2>/dev/null || true
    adb shell settings put system dtmf_tone_type 0 2>/dev/null || true
    adb shell settings put secure show_ime_with_hard_keyboard 1
    adb shell settings put global show_ime_with_hard_keyboard 1 2>/dev/null || true
    adb shell settings put secure enabled_input_methods "$NULL_IME"
    adb shell settings put secure default_input_method "$NULL_IME"
    adb shell settings put secure accessibility_soft_keyboard_mode 1 2>/dev/null || true
    adb shell pm disable-user --user 0 "$KIKA_PKG" 2>/dev/null || true
    if ! sherpa_on_device; then
      echo "Sherpa STT models not on device — pushing…"
      push_sherpa
    fi
    echo "Default IME: Flip2 Null Keyboard. Kika disabled."
    echo "STT: hold * to dictate (Sherpa-ONNX EN/UK). While listening: # = switch lang, * = stop."
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
    echo "Sherpa STT models:"
    adb shell "su -c 'du -sh $MODEL_DEVICE_ROOT/en $MODEL_DEVICE_ROOT/uk 2>/dev/null || echo missing'" 2>/dev/null | tr -d '\r' || echo "  (none — flip2 ime sherpa)"
    adb shell "dumpsys input_method 2>/dev/null | grep -E 'mCurId|CandidatesView|InputViewShown' | head -5" 2>/dev/null || true
    ;;
  whisper)
    echo "Whisper removed — use: flip2 ime sherpa" >&2
    exit 1
    ;;
  *)
    echo "Unknown ime subcommand: $cmd" >&2
    usage >&2
    exit 1
    ;;
esac
