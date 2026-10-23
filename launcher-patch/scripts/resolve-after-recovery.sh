#!/usr/bin/env bash
# Delegates to recovery pipeline. Prefer: flip2 recovery
set -euo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec "$FLIP2_ROOT/pipeline/recovery/resolve.sh"
