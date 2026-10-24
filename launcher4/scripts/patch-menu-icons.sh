#!/usr/bin/env bash
# Register menu grid icons for packages not in stock initAllAppIconList.
set -euo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "$FLIP2_ROOT/lib/bootstrap.sh"

WORK="${1:?Usage: patch-menu-icons.sh <decoded-dir>}"
LAUNCHER="$WORK/smali/com/android/launcher3/Launcher.smali"
[[ -f "$LAUNCHER" ]] || { echo "Missing $LAUNCHER" >&2; exit 1; }

python3 - "$LAUNCHER" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()
changed = []

EXTRA = [
    ("com.android.calculator2", "0x7f080091"),
    ("dev.skye.intertune", "0x7f08001d"),
    ("com.dozingcatsoftware.bouncy", "0x7f08001a"),
]

def smali_put(pkg: str, drawable: str) -> str:
    return f"""
    iget-object v0, p0, Lcom/android/launcher3/Launcher;->mAllAppIconMap:Ljava/util/HashMap;

    invoke-virtual {{p0}}, Landroid/app/Activity;->getResources()Landroid/content/res/Resources;

    move-result-object v1

    const v2, {drawable}

    invoke-virtual {{v1, v2}}, Landroid/content/res/Resources;->getDrawable(I)Landroid/graphics/drawable/Drawable;

    move-result-object v1

    const-string v2, "{pkg}"

    invoke-virtual {{v0, v2, v1}}, Ljava/util/HashMap;->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;
"""

marker = "flip2: extra menu icons block"
if marker in t:
    print("patch-menu-icons: already applied")
    raise SystemExit(0)

anchor_fresh = """    .line 5147
    :goto_a
    iget-object v0, p0, Lcom/android/launcher3/Launcher;->mAllAppIconMap:Ljava/util/HashMap;

    invoke-virtual {p0}, Landroid/app/Activity;->getResources()Landroid/content/res/Resources;

    move-result-object v1

    const v2, 0x7f08000d
"""

anchor_after_calc = """    const-string v2, "com.android.calculator2"

    invoke-virtual {v0, v2, v1}, Ljava/util/HashMap;->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;

    iget-object v0, p0, Lcom/android/launcher3/Launcher;->mAllAppIconMap:Ljava/util/HashMap;

    invoke-virtual {p0}, Landroid/app/Activity;->getResources()Landroid/content/res/Resources;

    move-result-object v1

    const v2, 0x7f08000d
"""

block = "    # flip2: extra menu icons block\n" + "".join(smali_put(pkg, did) for pkg, did in EXTRA)

tail = """
    iget-object v0, p0, Lcom/android/launcher3/Launcher;->mAllAppIconMap:Ljava/util/HashMap;

    invoke-virtual {p0}, Landroid/app/Activity;->getResources()Landroid/content/res/Resources;

    move-result-object v1

    const v2, 0x7f08000d
"""

if anchor_fresh in t:
    insert = """    .line 5147
    :goto_a
""" + block + tail
    t = t.replace(anchor_fresh, insert, 1)
    changed.append("calculator + intertune + telegram")
elif anchor_after_calc in t:
    head = """    const-string v2, "com.android.calculator2"

    invoke-virtual {v0, v2, v1}, Ljava/util/HashMap;->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;
"""
    t = t.replace(anchor_after_calc, head + block + tail, 1)
    changed.append("intertune + telegram (after calculator)")
else:
    calc_only = """    # flip2: calculator menu icon (tool_calculator)
    iget-object v0, p0, Lcom/android/launcher3/Launcher;->mAllAppIconMap:Ljava/util/HashMap;

    invoke-virtual {p0}, Landroid/app/Activity;->getResources()Landroid/content/res/Resources;

    move-result-object v1

    const v2, 0x7f080091

    invoke-virtual {v1, v2}, Landroid/content/res/Resources;->getDrawable(I)Landroid/graphics/drawable/Drawable;

    move-result-object v1

    const-string v2, "com.android.calculator2"

    invoke-virtual {v0, v2, v1}, Ljava/util/HashMap;->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;
"""
    if calc_only in t and "dev.skye.intertune" not in t:
        t = t.replace(calc_only, calc_only + block, 1)
        changed.append("intertune + telegram appended")
    else:
        print("warn: patch-menu-icons anchor not found", file=sys.stderr)
        raise SystemExit(0)

p.write_text(t)
for c in changed:
    print(f"patch-menu-icons: {c}")
PY
