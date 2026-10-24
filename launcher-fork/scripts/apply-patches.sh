#!/usr/bin/env bash
# Apply smali patches to work/decoded.
set -euo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "$FLIP2_ROOT/lib/bootstrap.sh"
exec "$FLIP2_FORK/scripts/apply-patches-to.sh" "$FLIP2_FORK/work/decoded"
