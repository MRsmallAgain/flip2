#!/usr/bin/env bash
# Bake slots.json into fork work/decoded/res — merge allapp_list only.
set -euo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "$FLIP2_ROOT/lib/bootstrap.sh"

WORK="$FLIP2_FORK/work/decoded"
SLOTS="$FLIP2_OVERLAY/slots.json"
[[ -d "$WORK/res" ]] || { echo "Run extract first" >&2; exit 1; }
[[ -f "$SLOTS" ]] || { echo "Missing $SLOTS" >&2; exit 1; }

python3 <<PY
import json
import re
from pathlib import Path

slots_path = Path("$SLOTS")
work_vals = Path("$WORK/res/values")
arrays_path = work_vals / "arrays.xml"
strings_path = work_vals / "strings.xml"

data = json.loads(slots_path.read_text())
items = []
for i in range(1, 10):
    v = (data.get(str(i)) or "").strip()
    if not v:
        continue
    if v in ("@tools", "tools", "@string/tools_key"):
        items.append("@string/tools_key")
    else:
        items.append(v)

WHITELIST = {"com.android.music", "myLatam", "myATT", "Media center"}
DEFAULT5 = "com.android.music"
slot5 = (data.get("5") or "").strip()
def5 = slot5 if slot5 in WHITELIST else DEFAULT5

if strings_path.is_file():
    s = strings_path.read_text(encoding="utf-8")
    line = f'    <string name="def_appmenu_position_five">{def5}</string>'
    if re.search(r'name="def_appmenu_position_five"', s):
        s = re.sub(
            r'\s*<string name="def_appmenu_position_five"[^>]*>[^<]*</string>\s*',
            "\n" + line + "\n",
            s,
        )
    else:
        s = s.replace("</resources>", "    " + line + "\n</resources>\n")
    strings_path.write_text(s, encoding="utf-8")

if not arrays_path.is_file():
    raise SystemExit(f"Missing {arrays_path} — extract stock first")

text = arrays_path.read_text(encoding="utf-8")
new_block_lines = ['    <string-array name="allapp_list">']
for it in items:
    esc = it.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    new_block_lines.append(f"        <item>{esc}</item>")
new_block_lines.append("    </string-array>")
new_block = "\n".join(new_block_lines)

pat = r'<string-array name="allapp_list">.*?</string-array>'
if re.search(pat, text, re.DOTALL):
    text = re.sub(pat, new_block, text, count=1, flags=re.DOTALL)
else:
    text = text.replace("<resources>", "<resources>\n" + new_block + "\n", 1)

arrays_path.write_text(text, encoding="utf-8")
print("inject-slots: merged allapp_list", len(items), "items")
PY
