#!/usr/bin/env bash
# Build Flip 2 patched Bouncy and install via adb.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec "$HERE/patch-bouncy.sh" "$@"
