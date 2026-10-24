#!/usr/bin/env bash
# Push home-keys.json → Settings.Global keyshortcut_* (left/right/up/down on workspace).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JSON="$ROOT/home-keys.json"

if [[ ! -f "$JSON" ]]; then
  echo "Missing $JSON"
  exit 1
fi

python3 <<PY
import json
import shlex
import subprocess
from pathlib import Path

data = json.loads(Path("$JSON").read_text())
keys = {
    "left": "keyshortcut_leftkey",
    "right": "keyshortcut_rightkey",
    "up": "keyshortcut_upkey",
    "down": "keyshortcut_downkey",
    "shortcuts_bar": "keyshortcut_shortcutsbar",
}
for slot, setting in keys.items():
    v = data.get(slot)
    if v is None or (isinstance(v, str) and not v.strip()):
        continue
    v = str(v).strip()
    # Quote for device sh: & and $ in Label-package-component break unquoted args
    shell_cmd = f"settings put global {setting} {shlex.quote(v)}"
    r = subprocess.run(
        ["adb", "shell", shell_cmd],
        capture_output=True,
        text=True,
    )
    if r.returncode != 0:
        raise SystemExit(f"Failed {setting}: {r.stderr or r.stdout}")
    print(f"{setting} = {v[:60]}{'…' if len(v) > 60 else ''}")
PY

echo "Done. Press Home and try the right soft key (Shortcuts label)."
