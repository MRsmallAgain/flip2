#!/usr/bin/env bash
# Flip2 chat IME: Kika shows Abc + candidate bar and breaks backspace on hardware keypad.
# hide-bar: Flip2 Null Keyboard — zero UI, forwards keys (incl. delete) to the focused field.
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

usage() {
  cat <<EOF
Usage: flip2 ime <subcommand>

  hide-bar    Install/set Flip2 Null Keyboard (no Abc bar, hardware backspace in chat)
  restore     Default back to stock Kika 12Key IME
  status      IME packages and default_input_method
  build       Build nullkeyboard.apk (needs JDK — see pipeline/ime/null-keyboard/build.sh)

Hardware D-pad typing goes through the null IME InputConnection when hide-bar is active.
EOF
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
  hide-bar)
    flip2_adb_require_device
    if [[ ! -f "$NULL_APK" ]]; then
      echo "Building null keyboard…" >&2
      export JAVA_HOME="${JAVA_HOME:-$HOME/.local/opt/jdk17}"
      export PATH="$JAVA_HOME/bin:$PATH"
      "$NULL_BUILD"
    fi
    adb install -r "$NULL_APK" >/dev/null
    adb shell settings put secure show_ime_with_hard_keyboard 0
    adb shell settings put global show_ime_with_hard_keyboard 0 2>/dev/null || true
    adb shell settings put secure enabled_input_methods "$NULL_IME"
    adb shell settings put secure default_input_method "$NULL_IME"
    adb shell settings put secure accessibility_soft_keyboard_mode 1 2>/dev/null || true
    adb shell pm disable-user --user 0 "$KIKA_PKG" 2>/dev/null || true
    echo "Default IME: Flip2 Null Keyboard. Kika disabled."
    echo "Force-stop chat app and reopen a thread — no Abc bar; backspace via keypad."
    echo "Restore stock: flip2 ime restore"
    ;;
  restore)
    flip2_adb_require_device
    adb shell pm enable "$KIKA_PKG"
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
    adb shell "dumpsys input_method 2>/dev/null | grep -E 'mCurId|CandidatesView|InputViewShown' | head -5" 2>/dev/null || true
    ;;
  *)
    echo "Unknown ime subcommand: $cmd" >&2
    usage >&2
    exit 1
    ;;
esac
