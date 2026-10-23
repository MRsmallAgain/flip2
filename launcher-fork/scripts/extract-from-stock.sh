#!/usr/bin/env bash
set -euo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "$FLIP2_ROOT/lib/bootstrap.sh"
flip2_env_init
flip2_require_cmd apktool

STOCK="$FLIP2_FORK/stock/Launcher3.apk"
WORK="$FLIP2_FORK/work/decoded"
[[ -f "$STOCK" ]] || { echo "Missing $STOCK" >&2; exit 1; }

rm -rf "$WORK"
mkdir -p "$FLIP2_FORK/work"
apktool d -f "$STOCK" -o "$WORK"
echo "Decoded: $WORK"
