#!/usr/bin/env bash
# Download and install the published Flip 2 Forkgram patch build.
#
# The release is an unofficial, debug-signed APK built from F-Droid Forkgram
# 13.0.2.0 and patched for the TCL Flip 2 null-keyboard setup. See README.md.
set -euo pipefail

TAG="flip2-13.0.2.0-r1"
ASSET="forkgram-13.0.2.0-flip2-patched.apk"
BASE_URL="https://github.com/MRsmallAgain/TelegramAndroid/releases/download/$TAG"
PKG="org.forkgram.classic"

WORK="${WORK:-/tmp/forkgram-release}"
DO_INSTALL=1
UNINSTALL=0

die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*"; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Downloads the hosted Flip 2 patch build ($TAG), verifies its SHA-256, and
installs it with adb.

Options:
  --work DIR     Download directory (default: $WORK)
  --no-install   Download and verify only
  --uninstall    Uninstall $PKG first (wipes app data; needed once when
                 switching from the F-Droid signature to the debug signature)
  -h, --help     Show this help

Release: $BASE_URL
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --work) WORK="${2:-}"; [ -n "$WORK" ] || die "--work needs a path"; shift 2 ;;
    --no-install) DO_INSTALL=0; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (try --help)" ;;
  esac
done

command -v curl >/dev/null 2>&1 || die "curl not found"
command -v sha256sum >/dev/null 2>&1 || die "sha256sum not found"

mkdir -p "$WORK"
SIGNED="$WORK/$ASSET"

log "Downloading $TAG/$ASSET"
curl -fsSL "$BASE_URL/$ASSET" -o "$SIGNED" \
  || die "download failed: $BASE_URL/$ASSET"
curl -fsSL "$BASE_URL/SHA256SUMS" -o "$WORK/SHA256SUMS" \
  || die "checksum download failed: $BASE_URL/SHA256SUMS"

log "Verifying SHA-256"
( cd "$WORK" && sha256sum -c SHA256SUMS ) || die "checksum verification failed"

if [ "$DO_INSTALL" -eq 0 ]; then
  log "OK: $SIGNED"
  exit 0
fi

adb get-state >/dev/null 2>&1 || die "no adb device"
if [ "$UNINSTALL" -eq 1 ]; then
  log "Uninstalling $PKG (app data will be lost)"
  adb uninstall "$PKG" >/dev/null || true
fi
if ! adb install -r "$SIGNED"; then
  die "install failed. If it reported INSTALL_FAILED_UPDATE_INCOMPATIBLE, rerun with --uninstall (wipes app data)."
fi
log "Installed. BACK deletes in focused text fields; empty fields navigate normally."
