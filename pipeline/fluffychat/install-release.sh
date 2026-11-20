#!/usr/bin/env bash
# Download and install FluffyChat for Flip 2 (catalog pin or --fdroid stock).
#
# Patched builds verify against wizard/catalog.json like Forkgram.
# See pipeline/fluffychat/README.md.
set -euo pipefail

ID="fluffychat"
PKG="chat.fluffy.fluffychat"

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CATALOG="${FLIP2_CATALOG:-$ROOT/wizard/catalog.json}"

WORK="${WORK:-/tmp/fluffychat-release}"
DO_INSTALL=1
UNINSTALL=0
USE_FDROID=0

die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*"; }

pin() {
  local v
  v="$(jq -r --arg id "$ID" --arg f "$1" '.files[] | select(.id == $id) | .[$f] // empty' "$CATALOG")"
  [ -n "$v" ] || return 1
  printf '%s' "$v"
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Download FluffyChat, verify when catalog pin exists, install with adb.

Options:
  --work DIR       Download directory (default: $WORK)
  --no-install     Download and verify only
  --uninstall      Uninstall $PKG first
  --fdroid         Install stock from F-Droid API (Phase 0; no patch)
  -h, --help       Show this help

Catalog: $CATALOG (id: $ID)
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --work) WORK="${2:-}"; [ -n "$WORK" ] || die "--work needs a path"; shift 2 ;;
    --no-install) DO_INSTALL=0; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    --fdroid) USE_FDROID=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (try --help)" ;;
  esac
done

mkdir -p "$WORK"
SIGNED=""

if [ "$USE_FDROID" -eq 1 ]; then
  command -v curl >/dev/null 2>&1 || die "curl not found"
  command -v jq >/dev/null 2>&1 || die "jq not found"
  log "Resolving F-Droid chat.fluffy.fluffychat"
  meta="$(curl -fsSL 'https://f-droid.org/api/v1/packages/chat.fluffy.fluffychat')"
  vc="$(echo "$meta" | jq -r '.suggestedVersionCode // empty')"
  [ -n "$vc" ] || die "F-Droid: no suggestedVersionCode for chat.fluffy.fluffychat"
  file_name="chat.fluffy.fluffychat_${vc}.apk"
  SIGNED="$WORK/$file_name"
  log "Downloading $file_name"
  curl -fsSL "https://f-droid.org/repo/$file_name" -o "$SIGNED" || die "download failed"
  actual_sha="$(sha256sum "$SIGNED" | awk '{print $1}')"
  log "F-Droid build SHA-256: $actual_sha (add to catalog when pinning mirror)"
else
  [ -f "$CATALOG" ] || die "catalog not found: $CATALOG (use --fdroid for Phase 0)"
  command -v jq >/dev/null 2>&1 || die "jq not found"
  ASSET="$(pin file)" || die "catalog.json: no entry id '$ID' — use --fdroid or add catalog pin"
  URL="$(pin url)" || die "catalog: no url for $ID"
  EXPECTED_SHA="$(pin sha256)"
  EXPECTED_SIZE="$(pin size)"
  command -v curl >/dev/null 2>&1 || die "curl not found"
  SIGNED="$WORK/$ASSET"
  log "Downloading $ASSET"
  curl -fsSL "$URL" -o "$SIGNED" || die "download failed: $URL"
  actual_sha="$(sha256sum "$SIGNED" | awk '{print $1}')"
  actual_size="$(stat -c%s "$SIGNED")"
  [ "$actual_size" = "$EXPECTED_SIZE" ] \
    || die "size mismatch (got $actual_size, expected $EXPECTED_SIZE)"
  [ "$actual_sha" = "$EXPECTED_SHA" ] \
    || die "checksum mismatch (got $actual_sha, expected $EXPECTED_SHA)"
  log "Verified against catalog pin"
fi

if [ "$DO_INSTALL" -eq 0 ]; then
  log "OK: $SIGNED"
  exit 0
fi

adb get-state >/dev/null 2>&1 || die "no adb device"
if [ "$UNINSTALL" -eq 1 ]; then
  log "Uninstalling $PKG"
  adb uninstall "$PKG" >/dev/null || true
fi
if ! adb install -r "$SIGNED"; then
  die "install failed"
fi
log "Installed $PKG. See docs/BRIDGES-FLIP2.md"
