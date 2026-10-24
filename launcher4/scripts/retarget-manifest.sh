#!/usr/bin/env bash
# Rename installable package to com.tim.flip2.launcher4 (no Magisk /system replace).
set -euo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "$FLIP2_ROOT/lib/bootstrap.sh"

WORK="${1:?Usage: retarget-manifest.sh <decoded-dir>}"
OLD_PKG="com.android.launcher3"
NEW_PKG="${FLIP2_LAUNCHER4_PKG:-com.tim.flip2.launcher4}"
MANIFEST="$WORK/AndroidManifest.xml"

[[ -f "$MANIFEST" ]] || { echo "Missing $MANIFEST" >&2; exit 1; }

python3 - "$MANIFEST" "$OLD_PKG" "$NEW_PKG" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
old = sys.argv[2]
new = sys.argv[3]
t = path.read_text(encoding="utf-8")

t = re.sub(
    rf'package="{re.escape(old)}"',
    f'package="{new}"',
    t,
    count=1,
)
t = t.replace(f"{old}.permission.", f"{new}.permission.")
t = t.replace(f'{old}.settings', f'{new}.settings')

DROP = (
    "android.permission.BLUETOOTH_PRIVILEGED",
    "android.permission.READ_PRIVILEGED_PHONE_STATE",
    "android.permission.OVERRIDE_WIFI_CONFIG",
    "android.permission.MANAGE_NETWORK_POLICY",
    "android.permission.CONNECTIVITY_INTERNAL",
    "android.permission.NETWORK_SETTINGS",
    "android.permission.NETWORK_STACK",
    "android.permission.MODIFY_PHONE_STATE",
    "android.permission.STATUS_BAR_SERVICE",
    "android.permission.WRITE_SECURE_SETTINGS",
)
for perm in DROP:
    t = re.sub(
        rf'\s*<uses-permission android:name="{re.escape(perm)}"[^/]*/>\s*',
        "\n",
        t,
    )

path.write_text(t, encoding="utf-8")
print(f"retarget-manifest: {old} -> {new}")
PY

# Distinct label in picker / recents (manifest still says Launcher3 in activity class)
STRINGS="$WORK/res/values/strings.xml"
if [[ -f "$STRINGS" ]]; then
  python3 - "$STRINGS" <<'PY2'
import re
import sys
from pathlib import Path
p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8")
s = re.sub(
    r'(<string name="app_name">)[^<]*(</string>)',
    r'\1Flip2 Launcher4\2',
    s,
    count=1,
)
p.write_text(s, encoding="utf-8")
print("retarget-manifest: app_name -> Flip2 Launcher4")
PY2
fi
