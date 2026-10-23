#!/usr/bin/env bash
# Apply smali patches to work/decoded.
set -euo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "$FLIP2_ROOT/lib/bootstrap.sh"

WORK="$FLIP2_FORK/work/decoded"
PATCH_SRC="$FLIP2_PATCH/decoded"
[[ -d "$WORK/smali" ]] || { echo "Run extract-from-stock.sh first" >&2; exit 1; }

for rel in \
  smali/com/android/launcher3/FastBitmapDrawable.smali \
  smali/com/android/launcher3/graphics/DrawableFactory.smali; do
  if [[ -f "$PATCH_SRC/$rel" ]]; then
    cp "$PATCH_SRC/$rel" "$WORK/$rel"
    echo "patched: $rel"
  fi
done

LAUNCHER="$WORK/smali/com/android/launcher3/Launcher.smali"
BLOCK='    invoke-virtual {p0}, Landroid/app/Activity;->getResources()Landroid/content/res/Resources;

    move-result-object v3

    const v4, 0x7f10003a

    invoke-virtual {v3, v4}, Landroid/content/res/Resources;->getString(I)Ljava/lang/String;

    move-result-object v3

    const/4 v4, 0x4

    aput-object v3, v2, v4

'
if grep -q 'aput-object v3, v2, v4' "$LAUNCHER"; then
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
if block in t:
    t = t.replace(block, "    # flip2 fork: allapp_list[4] is slot 5\n\n", 1)
    p.write_text(t)
    print("patched: Launcher.smali slot5 overwrite removed")
else:
    print("warn: slot5 block not found")
PY
fi
echo "apply-patches: done"
