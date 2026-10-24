#!/usr/bin/env bash
# Tools folder icons: map entries + apply mToolsIconMap for non-package tools_list rows.
set -euo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "$FLIP2_ROOT/lib/bootstrap.sh"

WORK="${1:?Usage: patch-tools-icons.sh <decoded-dir>}"
TOOLS="$WORK/smali/com/android/launcher3/allapps/ToolsNewActivity.smali"
[[ -f "$TOOLS" ]] || { echo "Missing $TOOLS" >&2; exit 1; }

python3 - "$TOOLS" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()
changed = []

MARK_INIT = "flip2: tools settings icon map"
MARK_STR = "flip2: tools string-key icon from map"

if MARK_INIT in t and MARK_STR in t:
    print("patch-tools-icons: already applied")
    raise SystemExit(0)

init_anchor = """    const-string v2, "com.tcl.logger"

    invoke-virtual {v0, v2, v1}, Ljava/util/HashMap;->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;

    return-void
.end method

.method public onAttachedToWindow()V"""

init_block = """    const-string v2, "com.tcl.logger"

    invoke-virtual {v0, v2, v1}, Ljava/util/HashMap;->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;

    # flip2: tools settings icon map
    iget-object v0, p0, Lcom/android/launcher3/allapps/ToolsNewActivity;->mToolsIconMap:Ljava/util/HashMap;

    invoke-virtual {p0}, Landroid/app/Activity;->getResources()Landroid/content/res/Resources;

    move-result-object v1

    const v2, 0x7f080021

    invoke-virtual {v1, v2}, Landroid/content/res/Resources;->getDrawable(I)Landroid/graphics/drawable/Drawable;

    move-result-object v1

    const-string v2, "com.android.settings"

    invoke-virtual {v0, v2, v1}, Ljava/util/HashMap;->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;

    const-string v2, "Media center"

    invoke-virtual {p0}, Landroid/app/Activity;->getResources()Landroid/content/res/Resources;

    move-result-object v1

    const v3, 0x7f08001a

    invoke-virtual {v1, v3}, Landroid/content/res/Resources;->getDrawable(I)Landroid/graphics/drawable/Drawable;

    move-result-object v1

    invoke-virtual {v0, v2, v1}, Ljava/util/HashMap;->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;

    return-void
.end method

.method public onAttachedToWindow()V"""

if MARK_INIT not in t:
    if init_anchor not in t:
        print("warn: patch-tools-icons init anchor not found", file=sys.stderr)
        raise SystemExit(1)
    t = t.replace(init_anchor, init_block, 1)
    changed.append("initToolsAppIconList settings + Media center")

str_anchor = """    .line 209
    new-instance v7, Lcom/android/launcher3/AppInfo;

    invoke-direct {v7, v6, v6}, Lcom/android/launcher3/AppInfo;-><init>(Ljava/lang/String;Ljava/lang/String;)V

    .line 210
    iget-object v6, p0, Lcom/android/launcher3/allapps/ToolsNewActivity;->mToolsApps:Ljava/util/List;

    invoke-interface {v6, v7}, Ljava/util/List;->add(Ljava/lang/Object;)Z

    goto/16 :goto_3"""

str_block = """    .line 209
    new-instance v7, Lcom/android/launcher3/AppInfo;

    invoke-direct {v7, v6, v6}, Lcom/android/launcher3/AppInfo;-><init>(Ljava/lang/String;Ljava/lang/String;)V

    # flip2: tools string-key icon from map
    iget-object v8, p0, Lcom/android/launcher3/allapps/ToolsNewActivity;->mToolsIconMap:Ljava/util/HashMap;

    invoke-virtual {v8, v6}, Ljava/util/HashMap;->get(Ljava/lang/Object;)Ljava/lang/Object;

    move-result-object v8

    check-cast v8, Landroid/graphics/drawable/Drawable;

    if-eqz v8, :cond_flip2_tools_stricon

    check-cast v8, Landroid/graphics/drawable/BitmapDrawable;

    invoke-virtual {v8}, Landroid/graphics/drawable/BitmapDrawable;->getBitmap()Landroid/graphics/Bitmap;

    move-result-object v8

    iput-object v8, v7, Lcom/android/launcher3/ItemInfoWithIcon;->iconBitmap:Landroid/graphics/Bitmap;

    :cond_flip2_tools_stricon
    .line 210
    iget-object v6, p0, Lcom/android/launcher3/allapps/ToolsNewActivity;->mToolsApps:Ljava/util/List;

    invoke-interface {v6, v7}, Ljava/util/List;->add(Ljava/lang/Object;)Z

    goto/16 :goto_3"""

if MARK_STR not in t:
    if str_anchor not in t:
        print("warn: patch-tools-icons setupAppsList anchor not found", file=sys.stderr)
        raise SystemExit(1)
    t = t.replace(str_anchor, str_block, 1)
    changed.append("setupAppsList string-key icon lookup")

p.write_text(t)
for c in changed:
    print(f"patch-tools-icons: {c}")
PY
