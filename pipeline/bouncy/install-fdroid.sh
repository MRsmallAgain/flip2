#!/usr/bin/env bash
# Download and install stock Bouncy from F-Droid (Flip 2 catalog pin).
set -euo pipefail

URL="https://f-droid.org/repo/com.dozingcatsoftware.bouncy_43.apk"
ASSET="com.dozingcatsoftware.bouncy_43.apk"
EXPECTED_SHA="ffda0d9cb0b1b2aa58be9559dda891c4fa24391bc481d297a8e3d96c31f62721"
PKG="com.dozingcatsoftware.bouncy"

WORK="${WORK:-/tmp/bouncy-install}"
DO_INSTALL=1

die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*"; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Downloads F-Droid Bouncy v43 (1.16.0), verifies SHA-256, installs via adb.

Options:
  --work DIR       Download directory (default: $WORK)
  --no-install     Download and verify only
  -h, --help       Show this help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --work) WORK="${2:-}"; [ -n "$WORK" ] || die "--work needs a path"; shift 2 ;;
    --no-install) DO_INSTALL=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (try --help)" ;;
  esac
done

command -v curl >/dev/null 2>&1 || die "curl not found"
command -v sha256sum >/dev/null 2>&1 || die "sha256sum not found"

mkdir -p "$WORK"
APK="$WORK/$ASSET"

log "Downloading $ASSET"
curl -fsSL "$URL" -o "$APK" || die "download failed: $URL"

log "Verifying SHA-256"
actual="$(sha256sum "$APK" | awk '{print $1}')"
[ "$actual" = "$EXPECTED_SHA" ] || die "checksum mismatch (got $actual)"

if [ "$DO_INSTALL" -eq 0 ]; then
  log "OK: $APK"
  exit 0
fi

adb get-state >/dev/null 2>&1 || die "no adb device"
if ! adb install -r "$APK"; then
  die "install failed"
fi
log "Installed stock build. For Flip 2 flippers use: flip2 bouncy install"
