#!/usr/bin/env bash
# Quick CLI: edit one menu slot then apply. Example: edit-slot.sh 3 org.mozilla.firefox
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SLOTS="$ROOT/slots.json"

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <1-9> <package-or-@tools>"
  echo "Example: $0 7 org.chromium.chrome"
  exit 1
fi

SLOT="$1"
PKG="$2"

python3 <<PY
import json
from pathlib import Path
p = Path("$SLOTS")
data = json.loads(p.read_text()) if p.is_file() else {}
data[str("$SLOT")] = "$PKG"
if "_comment" not in data:
    data = {"_comment": "Menu grid: 1-9 = icon order. @tools = Tools folder entry.", **data}
p.write_text(json.dumps(data, indent=2) + "\n")
print("slot", "$SLOT", "->", "$PKG")
PY

exec "$ROOT/scripts/apply-slots.sh"
