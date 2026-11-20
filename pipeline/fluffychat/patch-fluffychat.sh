#!/usr/bin/env bash
# Patch FluffyChat for TCL Flip 2 (BACK-delete, D-pad focus) — stub until Phase 0 spike.
# See pipeline/fluffychat/README.md and pipeline/forkgram/patch-forkgram.sh.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="chat.fluffy.fluffychat"

die() { echo "error: $*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Phase 1 stub: no patches applied yet. Device spike required for Flutter APK.

Options:
  --apk PATH     Source APK
  --no-install   Build/sign only (no-op until patches exist)
  -h, --help

Use: flip2 fluffychat release --fdroid
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    *) shift ;;
  esac
done

die "FluffyChat Flip2 patches not shipped yet. Install stock with: flip2 fluffychat release --fdroid"
