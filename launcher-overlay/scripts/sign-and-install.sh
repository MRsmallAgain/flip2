#!/usr/bin/env bash
# Build overlay, sign with debug key (userdebug / many rooted builds), install, enable.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
KEY="${ANDROID_DEBUG_KEY:-$HOME/.android/debug.keystore}"

export JAVA_HOME="${JAVA_HOME:-$HOME/.local/opt/jdk}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/.local/share/android-sdk}"
export PATH="$JAVA_HOME/bin:$ANDROID_SDK_ROOT/build-tools/34.0.0:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$HOME/.local/bin:$PATH"

find_apksigner() {
  if command -v apksigner >/dev/null; then
    command -v apksigner
    return
  fi
  for p in "$ANDROID_SDK_ROOT/build-tools/"*/apksigner; do
    [[ -x "$p" ]] && echo "$p" && return
  done
  return 1
}

"$ROOT/scripts/build-overlay-apktool.sh"

UNSIGNED="$DIST/overlay-unsigned.apk"
ALIGNED="$DIST/overlay-aligned.apk"
SIGNED="$DIST/Flip2LauncherOverlay.apk"

ZIPALIGN="${ZIPALIGN:-$ANDROID_SDK_ROOT/build-tools/34.0.0/zipalign}"
if [[ ! -x "$ZIPALIGN" ]]; then
  ZIPALIGN=$(command -v zipalign || true)
fi
[[ -x "$ZIPALIGN" ]] || { echo "Install zipalign (android-sdk build-tools)"; exit 1; }
"$ZIPALIGN" -p -f 4 "$UNSIGNED" "$ALIGNED"

if [[ ! -f "$KEY" ]]; then
  echo "Creating debug keystore at $KEY"
  mkdir -p "$(dirname "$KEY")"
  keytool -genkey -v -keystore "$KEY" -storepass android -alias androiddebugkey \
    -keypass android -keyalg RSA -keysize 2048 -validity 10000 \
    -dname "CN=Android Debug,O=Android,C=US"
fi

command -v apksigner >/dev/null || { echo "Install apksigner (android-sdk build-tools)"; exit 1; }
apksigner sign --ks "$KEY" --ks-pass pass:android --key-pass pass:android \
  --out "$SIGNED" "$ALIGNED"

echo "Signed: $SIGNED"

if ! adb get-state >/dev/null 2>&1; then
  echo "No adb device — APK ready at $SIGNED"
  exit 0
fi

adb install -r "$SIGNED"
adb shell cmd overlay enable --user current com.tim.flip2.launcheroverlay 2>/dev/null \
  || adb shell cmd overlay enable com.tim.flip2.launcheroverlay 2>/dev/null \
  || echo "Enable manually: cmd overlay enable com.tim.flip2.launcheroverlay"

adb shell cmd overlay list | grep -i flip2 || true
echo "Restart launcher: adb shell am force-stop com.android.launcher3"
