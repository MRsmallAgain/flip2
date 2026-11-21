#!/usr/bin/env bash
# Every component id emitted by profiles.json must appear in companion PROFILE_IDS,
# or Apply fails with "profile.list rejected" (see docs/WIZARD-FAILURES.md).
# install.sh optional components (astro_loop, etc.) are allowed outside profiles.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

PROFILES="$ROOT/wizard/profiles.json"
MAIN="$ROOT/companion/main.js"

[[ -f "$PROFILES" ]] || { echo "missing $PROFILES" >&2; exit 2; }
[[ -f "$MAIN" ]] || { echo "missing $MAIN" >&2; exit 2; }

python3 <<'PY'
import json, re, sys
from pathlib import Path

root = Path(".")
profiles = json.loads((root / "wizard/profiles.json").read_text())
deploy = root / "pipeline/deploy/profiles.json"
if deploy.is_file():
    if deploy.read_text() != (root / "wizard/profiles.json").read_text():
        print("FAIL  wizard/profiles.json and pipeline/deploy/profiles.json differ", file=sys.stderr)
        sys.exit(1)

ids = set()
for p in profiles["profiles"]:
    ids.update(p.get("components", []))
    ids.update(p.get("adds", []))
    for f in p.get("flags", []):
        ids.add(f["id"])
ids.add("enable_camera")
ids.add("enable_browser")

main = (root / "companion/main.js").read_text()
m = re.search(r"const PROFILE_IDS = \{([^}]+)\}", main, re.S)
if not m:
    print("FAIL  could not parse PROFILE_IDS in companion/main.js", file=sys.stderr)
    sys.exit(1)
profile_ids = set()
for quoted, bare in re.findall(r"(?:'([\w-]+)'|(\w+)):\s*true", m.group(1)):
    profile_ids.add(quoted or bare)

missing = sorted(ids - profile_ids)
if missing:
    print("FAIL  profile component ids missing from companion PROFILE_IDS:", ", ".join(missing), file=sys.stderr)
    print("      Apply will reject profile.list — add them to PROFILE_IDS in companion/main.js", file=sys.stderr)
    sys.exit(1)

legacy = {"flipmouse_arcade"}
unused = sorted(profile_ids - ids - legacy)
if unused:
    print("FAIL  PROFILE_IDS keys not used by any profile (typo?):", ", ".join(unused), file=sys.stderr)
    sys.exit(1)

print("OK: profiles.json component ids ⊆ PROFILE_IDS (%d ids)" % len(ids))
PY
