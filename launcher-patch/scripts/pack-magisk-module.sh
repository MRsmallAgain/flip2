#!/usr/bin/env bash
# Build patched Launcher3 and zip Magisk system overlay module.
set -euo pipefail
PATCH_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MOD="$PATCH_ROOT/magisk-module"
OUT="$PATCH_ROOT/dist"

"$PATCH_ROOT/scripts/build-patched-launcher.sh"

mkdir -p "$MOD/system/priv-app/Launcher3"
cp "$OUT/Launcher3-patched.apk" "$MOD/system/priv-app/Launcher3/Launcher3.apk"

ZIP="$OUT/flip2_launcher3_icon_fix-magisk.zip"
rm -f "$ZIP"
(cd "$MOD" && zip -r "$ZIP" module.prop service.sh system)

echo "Magisk module: $ZIP"
echo "Install: Magisk → Modules → Install from storage → reboot"
echo "Then: ~/.local/share/flip2/launcher-overlay/scripts/edit-slot.sh 5 com.dozingcatsoftware.bouncy"
