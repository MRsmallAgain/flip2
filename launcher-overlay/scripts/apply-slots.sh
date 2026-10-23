#!/usr/bin/env bash
# Delegates to pipeline. Prefer: flip2 apply
set -euo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec "$FLIP2_ROOT/pipeline/overlay/apply.sh"
