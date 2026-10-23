#!/usr/bin/env bash
# Build patched Launcher3 (null icon bitmap fix) with apktool.
set -euo pipefail
PATCH_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DECODED="$PATCH_ROOT/decoded"
DIST="$PATCH_ROOT/dist"
mkdir -p "$DIST"

export JAVA_HOME="${JAVA_HOME:-$HOME/.local/opt/jdk}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/.local/share/android-sdk}"
export PATH="$JAVA_HOME/bin:$ANDROID_SDK_ROOT/build-tools/34.0.0:$HOME/.local/bin:$PATH"
command -v apktool >/dev/null || { echo "Install apktool"; exit 1; }

echo "Building patched Launcher3…"
apktool b "$DECODED" -o "$DIST/Launcher3-patched-unsigned.apk"

ZIPALIGN="${ZIPALIGN:-$HOME/.local/share/android-sdk/build-tools/34.0.0/zipalign}"
[[ -x "$ZIPALIGN" ]] || ZIPALIGN=$(command -v zipalign || true)
[[ -x "$ZIPALIGN" ]] || { echo "Need zipalign"; exit 1; }
"$ZIPALIGN" -p -f 4 "$DIST/Launcher3-patched-unsigned.apk" "$DIST/Launcher3-patched-aligned.apk"

KEY="${ANDROID_DEBUG_KEY:-$HOME/.android/debug.keystore}"
if [[ ! -f "$KEY" ]]; then
  mkdir -p "$(dirname "$KEY")"
  keytool -genkey -v -keystore "$KEY" -storepass android -alias androiddebugkey \
    -keypass android -keyalg RSA -keysize 2048 -validity 10000 \
    -dname "CN=Android Debug,O=Android,C=US" 2>/dev/null
fi
apksigner sign --ks "$KEY" --ks-pass pass:android --key-pass pass:android \
  --out "$DIST/Launcher3-patched.apk" "$DIST/Launcher3-patched-aligned.apk"

echo "Built: $DIST/Launcher3-patched.apk"
echo "System launcher is platform-signed — use install-magisk.sh or adb root push to /system."
