#!/usr/bin/env bash
# Replace hardcoded com.android.launcher3 string literals in smali (provider, prefs, package checks).
set -euo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "$FLIP2_ROOT/lib/bootstrap.sh"

WORK="${1:?Usage: retarget-smali.sh <decoded-dir>}"
OLD="com.android.launcher3"
NEW="${FLIP2_LAUNCHER4_PKG:-com.tim.flip2.launcher4}"

[[ -d "$WORK/smali" ]] || { echo "No smali in $WORK" >&2; exit 1; }

python3 - "$WORK" "$OLD" "$NEW" <<'PY'
import sys
from pathlib import Path

work = Path(sys.argv[1])
old = sys.argv[2]
new = sys.argv[3]
count_files = 0
count_repl = 0

for smali in work.rglob("*.smali"):
    text = smali.read_text(encoding="utf-8")
    if old not in text:
        continue
    new_text = text.replace(old, new)
    if new_text != text:
        smali.write_text(new_text, encoding="utf-8")
        count_files += 1
        count_repl += text.count(old)

print(f"retarget-smali: {old} -> {new} in {count_files} files ({count_repl} substitutions)")
PY
