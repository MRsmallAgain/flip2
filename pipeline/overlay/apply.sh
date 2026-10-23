#!/usr/bin/env bash
# Pipeline: sync slots → build → sign → install → root enable
set -euo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "$FLIP2_ROOT/lib/bootstrap.sh"

flip2_env_init
flip2_require_cmd python3 apktool zipalign apksigner adb

"$FLIP2_PIPELINE/overlay/sync-slots.sh"
"$FLIP2_OVERLAY/scripts/sign-and-install.sh"
"$FLIP2_OVERLAY/scripts/after-root-enable.sh"

echo "Pipeline overlay apply: done. Press Home on phone."
