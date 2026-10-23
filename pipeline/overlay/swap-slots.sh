#!/usr/bin/env bash
# Swap two menu slots in slots.json, then apply overlay pipeline.
set -euo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "$FLIP2_ROOT/lib/bootstrap.sh"

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <1-9> <1-9>" >&2
  exit 1
fi

A="$1"
B="$2"
if ! [[ "$A" =~ ^[1-9]$ && "$B" =~ ^[1-9]$ ]]; then
  echo "Slots must be 1–9" >&2
  exit 1
fi
if [[ "$A" == "$B" ]]; then
  echo "Slots are the same — nothing to swap" >&2
  exit 1
fi

SLOTS="$FLIP2_OVERLAY/slots.json"
[[ -f "$SLOTS" ]] || { echo "Missing $SLOTS" >&2; exit 1; }

if [[ "$A" == "5" || "$B" == "5" ]]; then
  if [[ "$A" == "5" ]]; then moving_into_5=$(python3 -c "import json; d=json.load(open('$SLOTS')); print(d.get('$B',''))")
  else moving_into_5=$(python3 -c "import json; d=json.load(open('$SLOTS')); print(d.get('$A',''))"); fi
  if [[ -n "$moving_into_5" ]] && ! flip2_slot5_can_hold "$moving_into_5"; then
    echo "Cannot swap: '$moving_into_5' into slot 5 crashes stock Menu." >&2
    echo "Install flip2 fork first, or swap other slots (e.g. flip2 swap 4 7)." >&2
    exit 1
  fi
fi

python3 <<PY
import json
from pathlib import Path
p = Path("$SLOTS")
data = json.loads(p.read_text())
a, b = "$A", "$B"
va, vb = data.get(a), data.get(b)
if va is None or vb is None:
    raise SystemExit(f"Missing slot {a} or {b} in slots.json")
data[a], data[b] = vb, va
p.write_text(json.dumps(data, indent=2) + "\n")
print(f"swapped {a} ({va}) ↔ {b} ({vb})")
PY

exec "$FLIP2_PIPELINE/overlay/apply.sh"
