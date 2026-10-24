#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MOD="$ROOT/magisk-module"
ZIP="$ROOT/dist/flip2_nav_overlay-magisk.zip"
APK="$ROOT/dist/navoverlay-unsigned-signed.apk"
[[ -f "$APK" ]] || { echo "Missing $APK — run build-and-install.sh build first" >&2; exit 1; }
mkdir -p "$MOD/system/product/overlay"
cp "$APK" "$MOD/system/product/overlay/Flip2NavOverlay.apk"
rm -f "$ZIP"
(cd "$MOD" && zip -r "$ZIP" module.prop service.sh system >/dev/null)
echo "Magisk module: $ZIP"
