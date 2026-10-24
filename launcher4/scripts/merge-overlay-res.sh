#!/usr/bin/env bash
# Bake launcher-overlay menu/strings/bools into decoded APK (RRO only affects stock Launcher3).
set -euo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "$FLIP2_ROOT/lib/bootstrap.sh"

WORK="${1:?Usage: merge-overlay-res.sh <decoded-dir>}"
OVERLAY_RES="$FLIP2_OVERLAY/res"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

[[ -d "$WORK/res" ]] || { echo "No res in $WORK" >&2; exit 1; }

"$FLIP2_PIPELINE/overlay/sync-slots.sh"
python3 "$SCRIPT_DIR/merge_overlay_res.py" "$WORK" "$OVERLAY_RES"
echo "merge-overlay-res: done (edit slots.json → rebuild launcher4 to change menu)"
