#!/usr/bin/env bash
# Stage: slots.json → res/values/arrays.xml + def_appmenu_position_five
set -euo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "$FLIP2_ROOT/lib/bootstrap.sh"

ROOT="$FLIP2_OVERLAY"
SLOTS="$ROOT/slots.json"
[[ -f "$SLOTS" ]] || { echo "Missing $SLOTS" >&2; exit 1; }

python3 <<PY
import json
import re
from pathlib import Path

root = Path("$ROOT")
slots_path = root / "slots.json"
arrays_path = root / "res/values/arrays.xml"
strings_path = root / "res/values/strings.xml"

data = json.loads(slots_path.read_text())
items = []
for i in range(1, 10):
    key = str(i)
    v = (data.get(key) or "").strip()
    if not v:
        continue
    if v in ("@tools", "tools", "@string/tools_key"):
        # Literal "Tools" matches tools_key + mAllAppIconMap (not unresolved @string in array)
        items.append("Tools")
    else:
        items.append(v)

if not items:
    raise SystemExit("No slots 1-9 set in slots.json")

INTERTUNE = "dev.skye.intertune"
for i in range(1, 10):
    v = (data.get(str(i)) or "").strip()
    if v == INTERTUNE:
        print(
            f"flip2: slot {i} is {INTERTUNE} — menu often fails to show it; "
            "use home-keys.json left + com.android.music (or stock-safe) in slot 5 instead."
        )

slot5 = (data.get("5") or "").strip()
WHITELIST = {"com.android.music", "myLatam", "myATT", "Media center"}
DEFAULT5 = "com.android.music"
if slot5 and slot5 not in ("@tools", "tools", "@string/tools_key"):
    def5 = slot5 if slot5 in WHITELIST else DEFAULT5
    if slot5 not in WHITELIST:
        print(f"slot 5: {slot5} not safe for stock launcher — def_appmenu_position_five -> {def5}")
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

tools_block = ""
if arrays_path.is_file():
    text = arrays_path.read_text(encoding="utf-8")
    for name in ("tools_list", "tools_hasmusic_list"):
        m = re.search(
            rf'<string-array name="{name}">(.*?)</string-array>',
            text,
            re.DOTALL,
        )
        if m:
            tools_block += f'    <string-array name="{name}">{m.group(1)}    </string-array>\n\n'

lines = [
    '<?xml version="1.0" encoding="utf-8"?>',
    "<resources>",
    "    <!-- Menu grid from slots.json (1-9) -->",
    '    <string-array name="allapp_list">',
]
for it in items:
    esc = it.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    lines.append(f"        <item>{esc}</item>")
lines.append("    </string-array>")
lines.append("")
if not tools_block.strip():
    tools_block = """    <string-array name="tools_list">
        <item>com.android.soundrecorder</item>
        <item>com.android.calendar</item>
        <item>com.android.deskclock</item>
        <item>com.android.note</item>
        <item>com.android.calculator2</item>
        <item>com.android.email</item>
        <item>com.jrdcom.filemanager</item>
        <item>com.android.stk</item>
        <item>com.tcl.tct.weather</item>
        <item>com.android.dialer</item>
        <item>com.tcl.logger</item>
    </string-array>

"""
lines.append(tools_block.rstrip())
lines.append("</resources>")
lines.append("")
arrays_path.write_text("\n".join(lines), encoding="utf-8")
print("allapp_list:", len(items), "items from slots 1-9")
PY
