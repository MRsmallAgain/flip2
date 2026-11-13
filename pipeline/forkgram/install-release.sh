#!/usr/bin/env bash
# Download and install the published Flip 2 Forkgram patch build.
#
# The APK is an unofficial, debug-signed build from F-Droid Forkgram 13.0.2.0,
# patched for the TCL Flip 2 null-keyboard setup. See README.md.
#
# It is served from the project's package mirror. The GitHub fork that used to
# host it is unreachable (the account is suspended), and the mirror has no
# per-release SHA256SUMS file — so this verifies, like the wizard does, against
# the sha256/size pinned in wizard/catalog.json.
#
# That pin is READ, not copied. A duplicated hash is exactly what drifted in
# v1.4.0-alpha.2: the release's SHA256SUMS listed installers from 2026-11-11
# while catalog.json pinned the 2026-11-13 rebuilds, so `sha256sum -c` failed
# against the release that published it. One source of truth for the number.
set -euo pipefail

ID="forkgram"
TAG="flip2-13.0.2.0-r1"
PKG="org.forkgram.classic"

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CATALOG="${FLIP2_CATALOG:-$ROOT/wizard/catalog.json}"

WORK="${WORK:-/tmp/forkgram-release}"
DO_INSTALL=1
UNINSTALL=0

die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*"; }

[ -f "$CATALOG" ] || die "catalog not found: $CATALOG (set FLIP2_CATALOG)"
command -v jq >/dev/null 2>&1 || die "jq not found (needed to read the pin from catalog.json)"

# One catalog lookup per field, so a missing id or an empty field fails here
# rather than becoming an empty URL or a blank hash that matches nothing.
pin() {
  local v
  v="$(jq -r --arg id "$ID" --arg f "$1" '.files[] | select(.id == $id) | .[$f] // empty' "$CATALOG")"
  [ -n "$v" ] || die "catalog.json: no .$1 for id '$ID'"
  printf '%s' "$v"
}

ASSET="$(pin file)"
URL="$(pin url)"
EXPECTED_SHA="$(pin sha256)"
EXPECTED_SIZE="$(pin size)"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Downloads the hosted Flip 2 patch build ($TAG), verifies it against the
catalog pin, and installs it with adb.

Options:
  --work DIR     Download directory (default: $WORK)
  --no-install   Download and verify only
  --uninstall    Uninstall $PKG first (wipes app data; needed once when
                 switching from the F-Droid signature to the debug signature)
  -h, --help     Show this help

Pinned in: $CATALOG
Download:  $URL
SHA-256:   $EXPECTED_SHA
Size:      $EXPECTED_SIZE bytes
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

log "Verifying against the catalog pin"
actual_sha="$(sha256sum "$SIGNED" | awk '{print $1}')"
actual_size="$(stat -c%s "$SIGNED")"
[ "$actual_size" = "$EXPECTED_SIZE" ] \
  || die "size mismatch (got $actual_size, expected $EXPECTED_SIZE)"
[ "$actual_sha" = "$EXPECTED_SHA" ] \
  || die "checksum mismatch (got $actual_sha, expected $EXPECTED_SHA)"

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
