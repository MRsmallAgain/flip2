#!/usr/bin/env bash
set -euo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$FLIP2_ROOT/lib/bootstrap.sh"
STOCK="$FLIP2_ROOT/vmouse/stock"
BIN="$STOCK/mouse"
URL="${FLIP2_SIMPLE_MOUSE_URL:-https://github.com/neutronscott/flip2/releases/download/simple-release1/mouse}"
mkdir -p "$STOCK"
if [[ -f "$BIN" ]] && [[ "${FLIP2_SIMPLE_MOUSE_FORCE_FETCH:-0}" != "1" ]]; then
  echo "Simple mouse binary present: $BIN ($(wc -c <"$BIN" | tr -d ' ') bytes)"
  exit 0
fi
curl -sL -o "$BIN" "$URL"
chmod +x "$BIN"
file "$BIN"
echo "Fetched: $BIN"
