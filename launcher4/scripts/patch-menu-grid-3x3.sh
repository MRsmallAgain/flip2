#!/usr/bin/env bash
# Cap all-apps grid at 3 columns (Flip2 nine-slot menu @ wm size 321x428).
set -euo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "$FLIP2_ROOT/lib/bootstrap.sh"

WORK="${1:?Usage: patch-menu-grid-3x3.sh <decoded-dir>}"
SMALI="$WORK/smali/com/android/launcher3/allapps/AllAppsContainerView.smali"
[[ -f "$SMALI" ]] || { echo "Missing $SMALI" >&2; exit 1; }

python3 - "$SMALI" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()
MARK = "flip2: cap menu grid at 3 columns"

if MARK in t:
    print("patch-menu-grid-3x3: already applied")
    raise SystemExit(0)

old = """    iget v2, v2, Lcom/android/launcher3/InvariantDeviceProfile;->numColumns:I

    iput v2, p0, Lcom/android/launcher3/allapps/AllAppsContainerView;->mNumAppsPerRow:I

    .line 228
    iput v2, p0, Lcom/android/launcher3/allapps/AllAppsContainerView;->mNumPredictedAppsPerRow:I"""

new = """    iget v2, v2, Lcom/android/launcher3/InvariantDeviceProfile;->numColumns:I

    # flip2: cap menu grid at 3 columns
    const/4 v6, 0x3
    invoke-static {v2, v6}, Ljava/lang/Math;->min(II)I
    move-result v2

    iput v2, p0, Lcom/android/launcher3/allapps/AllAppsContainerView;->mNumAppsPerRow:I

    .line 228
    iput v2, p0, Lcom/android/launcher3/allapps/AllAppsContainerView;->mNumPredictedAppsPerRow:I"""

if old not in t:
    print("warn: patch-menu-grid-3x3 anchor not found", file=sys.stderr)
    raise SystemExit(1)

t = t.replace(old, new, 1)
p.write_text(t)
print("patch-menu-grid-3x3: min(numColumns, 3) for all-apps grid")
PY
