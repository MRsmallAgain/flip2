#!/usr/bin/env bash
set -euo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "$FLIP2_ROOT/lib/bootstrap.sh"
flip2_env_init

APK="${1:?Usage: verify-apk.sh <apk>}"
[[ -f "$APK" ]] || { echo "Missing $APK" >&2; exit 1; }

SIZE=$(wc -c <"$APK" | tr -d ' ')
echo "APK size: $SIZE bytes"

AAPT="${AAPT:-$ANDROID_SDK_ROOT/build-tools/34.0.0/aapt}"
if [[ -x "$AAPT" ]]; then
  "$AAPT" dump badging "$APK" | grep -E 'package:|launchable-activity' || true
  PKG=$("$AAPT" dump badging "$APK" | sed -n "s/^package: name='\\([^']*\\)'.*/\\1/p" | head -1)
  EXPECT="${FLIP2_LAUNCHER4_PKG:-com.tim.flip2.launcher4}"
  if [[ -n "$PKG" && "$PKG" != "$EXPECT" ]]; then
    echo "warn: package is $PKG (expected $EXPECT)" >&2
  fi
fi
echo "verify-apk: ok"
