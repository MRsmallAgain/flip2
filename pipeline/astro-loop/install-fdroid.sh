#!/usr/bin/env bash
# Download and install Astro Loop from F-Droid (Flip 2 catalog pin).
set -euo pipefail

URL="https://f-droid.org/repo/com.astroloop.game_6.apk"
ASSET="com.astroloop.game_6.apk"
EXPECTED_SHA="79aa83482f64f7ae0bc245aa3550bc0e231fecdc046cb783b818917e418f6cf7"
PKG="com.astroloop.game"

WORK="${WORK:-/tmp/astro-loop-install}"
DO_INSTALL=1

die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*"; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Downloads F-Droid Astro Loop v1.5 (versionCode 6), verifies SHA-256, installs via adb.

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
log "Installed. Use D-pad to steer in combat; OK/Enter to confirm menus. See pipeline/astro-loop/README.md."
