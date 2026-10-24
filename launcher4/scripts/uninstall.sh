#!/usr/bin/env bash
set -euo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "$FLIP2_ROOT/lib/bootstrap.sh"

PKG="${FLIP2_LAUNCHER4_PKG:-com.tim.flip2.launcher4}"
flip2_adb_require_device || exit 1
adb uninstall "$PKG" 2>/dev/null || echo "Package $PKG not installed (ok)"
echo "Then set Home to stock Launcher3 in Settings if needed."
