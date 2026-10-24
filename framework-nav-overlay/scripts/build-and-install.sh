#!/usr/bin/env bash
# Flip2 framework-res RRO: navigation_bar_* -> 0 (apps were painting a phantom 30px nav area).
# Requires: aapt2/zipalign/apksigner (SDK build-tools), JDK.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export JAVA_HOME="${JAVA_HOME:-$HOME/.local/opt/jdk17}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/.local/share/android-sdk}"
export PATH="$JAVA_HOME/bin:$ANDROID_SDK_ROOT/build-tools/34.0.0:$PATH"

BT="$ANDROID_SDK_ROOT/build-tools/34.0.0"
CMD="${1:-all}"
DIST="$ROOT/dist"
mkdir -p "$DIST"

sign_apk() {
  local APK="$1"
  "$BT/zipalign" -p -f 4 "$APK" "${APK%.apk}-aligned.apk"
  apksigner sign --ks "$HOME/.android/debug.keystore" --ks-pass pass:android \
    --key-pass pass:android --out "${APK%.apk}-signed.apk" "${APK%.apk}-aligned.apk"
}

build() {
  local FW="$ROOT/stock/framework-res.apk"
  if [[ ! -f "$FW" ]]; then
    mkdir -p "$ROOT/stock"
    adb pull /system/framework/framework-res.apk "$FW" >/dev/null
  fi
  WORK="$ROOT/build"
  rm -rf "$WORK"; mkdir -p "$WORK"
  # Link against framework-res so @*android references (layout/ids) resolve.
  "$BT/aapt2" compile --dir "$ROOT/res" -o "$WORK/res.zip"
  "$BT/aapt2" link -o "$DIST/navoverlay-unsigned.apk" \
    --manifest "$ROOT/AndroidManifest.xml" \
    -I "$FW" \
    --min-sdk-version 26 --target-sdk-version 30 \
    "$WORK/res.zip"
  sign_apk "$DIST/navoverlay-unsigned.apk"
  echo "Built: $DIST/navoverlay-unsigned-signed.apk"
}

install_overlay() {
  adb install -r "$DIST/navoverlay-unsigned-signed.apk"
  adb shell cmd overlay enable --user current com.tim.flip2.navoverlay 2>/dev/null \
    || adb shell cmd overlay enable com.tim.flip2.navoverlay 2>/dev/null \
    || adb shell su -c "cmd overlay enable --user 0 com.tim.flip2.navoverlay"
  adb shell cmd overlay list | grep -E 'flip2.navoverlay|\[x\]' | head -8 || true
}

case "$CMD" in
  build) build ;;
  install) install_overlay ;;
  all|*) build && install_overlay ;;
esac
