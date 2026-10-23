#!/usr/bin/env bash
# Build signed overlay APK and zip Magisk module for /product/overlay/ after root.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MOD="$ROOT/magisk-module"
OUT="$ROOT/dist"

export JAVA_HOME="${JAVA_HOME:-$HOME/.local/opt/jdk}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/.local/share/android-sdk}"
export PATH="$JAVA_HOME/bin:$ANDROID_SDK_ROOT/build-tools/34.0.0:$HOME/.local/bin:$PATH"

"$ROOT/scripts/sign-and-install.sh" || true
APK="$OUT/Flip2LauncherOverlay.apk"
[[ -f "$APK" ]] || { echo "Missing $APK — run sign-and-install.sh first"; exit 1; }

mkdir -p "$MOD/product/overlay"
cp "$APK" "$MOD/product/overlay/Flip2LauncherOverlay.apk"
ZIP="$OUT/flip2_launcher_overlay-magisk.zip"
rm -f "$ZIP"
(cd "$MOD" && zip -r "$ZIP" module.prop product)
echo "Magisk module: $ZIP"
echo "Install in Magisk → Modules → Install from storage → reboot"
