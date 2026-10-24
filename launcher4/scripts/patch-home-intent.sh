#!/usr/bin/env bash
# HOME intent: always showWorkspace immediately (fixes clock visible through recents).
set -euo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "$FLIP2_ROOT/lib/bootstrap.sh"

WORK="${1:?Usage: patch-home-intent.sh <decoded-dir>}"
LAUNCHER="$WORK/smali/com/android/launcher3/Launcher.smali"
[[ -f "$LAUNCHER" ]] || { echo "Missing $LAUNCHER" >&2; exit 1; }

python3 - "$LAUNCHER" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()
MARK = "flip2: home intent always showWorkspace"

if MARK in t:
    print("patch-home-intent: already applied")
    raise SystemExit(0)

old = """    if-eqz v0, :cond_6

    .line 2393
    invoke-virtual {p0, v1}, Lcom/android/launcher3/Launcher;->showWorkspace(Z)Z

    goto :goto_3

    .line 2395
    :cond_6
    sget-object v5, Lcom/android/launcher3/Launcher$State;->WORKSPACE:Lcom/android/launcher3/Launcher$State;

    iput-object v5, p0, Lcom/android/launcher3/Launcher;->mOnResumeState:Lcom/android/launcher3/Launcher$State;

    .line 2398
    :goto_3"""

new = """    # flip2: home intent always showWorkspace (no defer when !mHasFocus / recents overlay)
    invoke-virtual {p0, v1}, Lcom/android/launcher3/Launcher;->showWorkspace(Z)Z

    sget-object v5, Lcom/android/launcher3/Launcher$State;->WORKSPACE:Lcom/android/launcher3/Launcher$State;

    iput-object v5, p0, Lcom/android/launcher3/Launcher;->mOnResumeState:Lcom/android/launcher3/Launcher$State;

    .line 2398
    :goto_3"""

if old not in t:
    print("warn: patch-home-intent anchor not found", file=sys.stderr)
    raise SystemExit(1)

t = t.replace(old, new, 1)
p.write_text(t)
print("patch-home-intent: always showWorkspace on MAIN/HOME")
PY
