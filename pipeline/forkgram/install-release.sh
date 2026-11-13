#!/usr/bin/env bash
# Download and install the published Flip 2 Forkgram patch build.
#
# The APK is an unofficial, debug-signed build from F-Droid Forkgram 13.0.2.0,
# patched for the TCL Flip 2 null-keyboard setup. See README.md.
#
# It is served from the project's package mirror. The GitHub fork that used to
# host it is unreachable (the account is suspended), and the mirror has no
# per-release SHA256SUMS file — so, like astro-loop/install-fdroid.sh, this
# verifies against the SHA-256 pinned in wizard/catalog.json instead.
set -euo pipefail

TAG="flip2-13.0.2.0-r1"
ASSET="forkgram-13.0.2.0-flip2-patched.apk"
URL="https://flip2burn.online/packages/$ASSET"
EXPECTED_SHA="bc378c74c378c23c2115ca1755b5322b15d30132098bcc8136ef1f13a817ce38"
PKG="org.forkgram.classic"

WORK="${WORK:-/tmp/forkgram-release}"
DO_INSTALL=1
UNINSTALL=0

die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*"; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Downloads the hosted Flip 2 patch build ($TAG), verifies its SHA-256 against the
catalog pin, and installs it with adb.

Options:
  --work DIR     Download directory (default: $WORK)
  --no-install   Download and verify only
  --uninstall    Uninstall $PKG first (wipes app data; needed once when
                 switching from the F-Droid signature to the debug signature)
  -h, --help     Show this help

Download: $URL
SHA-256:  $EXPECTED_SHA
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
curl -fsSL "$URL" -o "$SIGNED" || die "download failed: $URL"

log "Verifying SHA-256"
actual="$(sha256sum "$SIGNED" | awk '{print $1}')"
[ "$actual" = "$EXPECTED_SHA" ] || die "checksum mismatch (got $actual, expected $EXPECTED_SHA)"

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
