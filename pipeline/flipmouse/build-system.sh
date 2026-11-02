#!/usr/bin/env bash
# Stage system-domain FlipMouse artifacts for Tier A build-tree:
#   pipeline/flipmouse/system/bin/flip2-mouse
#   pipeline/flipmouse/system/etc/init/flip2-mouse.rc (already in repo)
# Run `flip2 flipmouse build` first (or this script invokes it).
set -euo pipefail
FM="$(cd "$(dirname "$0")" && pwd)"
"$FM/build.sh"
mkdir -p "$FM/system/bin"
cp "$FM/build/mouse" "$FM/system/bin/flip2-mouse"
chmod 755 "$FM/system/bin/flip2-mouse"
echo "Staged: $FM/system/bin/flip2-mouse ($(wc -c <"$FM/system/bin/flip2-mouse" | tr -d ' ') bytes)"
echo "Merge via: flip2 image build-tree"
