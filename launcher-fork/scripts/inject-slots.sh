#!/usr/bin/env bash
# Bake slots.json into fork work/decoded/res — merge allapp_list only.
set -euo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "$FLIP2_ROOT/lib/bootstrap.sh"
exec "$FLIP2_FORK/scripts/inject-slots-to.sh" "$FLIP2_FORK/work/decoded"
