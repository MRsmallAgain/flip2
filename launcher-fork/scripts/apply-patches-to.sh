#!/usr/bin/env bash
# Apply fork smali patches to any decoded tree (fork work/ or launcher4 work/).
set -euo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "$FLIP2_ROOT/lib/bootstrap.sh"

WORK="${1:?Usage: apply-patches-to.sh <decoded-dir>}"
PATCH_SRC="$FLIP2_PATCH/decoded"
[[ -d "$WORK/smali" ]] || { echo "No smali in $WORK" >&2; exit 1; }

for rel in \
  smali/com/android/launcher3/FastBitmapDrawable.smali \
  smali/com/android/launcher3/graphics/DrawableFactory.smali; do
  if [[ -f "$PATCH_SRC/$rel" ]]; then
    cp "$PATCH_SRC/$rel" "$WORK/$rel"
    echo "patched: $rel"
  fi
done

LAUNCHER="$WORK/smali/com/android/launcher3/Launcher.smali"
python3 - "$LAUNCHER" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
t = p.read_text()
block = """    invoke-virtual {p0}, Landroid/app/Activity;->getResources()Landroid/content/res/Resources;

    move-result-object v3

    const v4, 0x7f10003a

    invoke-virtual {v3, v4}, Landroid/content/res/Resources;->getString(I)Ljava/lang/String;

    move-result-object v3

    const/4 v4, 0x4

    aput-object v3, v2, v4

"""
# v4 must stay 4 for if-lt p1, v4 later in bindAllApplications
replacement = """    # flip2: allapp_list[4] from arrays only (no def_appmenu overwrite)

    const/4 v4, 0x4

"""
if block in t:
    t = t.replace(block, replacement, 1)
    p.write_text(t)
    print("patched: Launcher.smali slot5 overwrite removed (v4 preserved)")
elif "flip2: allapp_list[4]" in t:
    print("patched: Launcher.smali slot5 already removed")
else:
    print("warn: slot5 block not found in Launcher.smali")
PY
echo "apply-patches-to: done"
