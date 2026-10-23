#!/usr/bin/env bash
set -euo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$FLIP2_ROOT/lib/bootstrap.sh"

APK="$FLIP2_FORK/dist/Launcher3-fork.apk"
MOD="$FLIP2_FORK/magisk-module"
ZIP="$FLIP2_FORK/dist/flip2_launcher3_fork-magisk.zip"

[[ -f "$APK" ]] || { echo "Run build.sh first" >&2; exit 1; }

mkdir -p "$MOD/system/priv-app/Launcher3"
cp "$APK" "$MOD/system/priv-app/Launcher3/Launcher3.apk"
rm -f "$ZIP"
(cd "$MOD" && zip -r "$ZIP" module.prop service.sh system)
echo "Magisk module: $ZIP"
