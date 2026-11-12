#!/usr/bin/env bash
# Copy signed Flip2 Bouncy build into deploy/sources for wizard/installer pins.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLIP2_ROOT="$(cd "$HERE/../.." && pwd)"

DEPLOY_APK="$FLIP2_ROOT/pipeline/deploy/sources/com.dozingcatsoftware.bouncy_43.apk"
WORK="${WORK:-/tmp/bouncy-patch}"
SIGNED="$WORK/com.dozingcatsoftware.bouncy_43-flip2-signed.apk"

die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*"; }

if [ ! -f "$SIGNED" ]; then
  log "No signed build at $SIGNED — running patch --no-install"
  "$HERE/patch-bouncy.sh" --no-install
fi
[ -f "$SIGNED" ] || die "missing signed APK: $SIGNED"

sha="$(sha256sum "$SIGNED" | awk '{print $1}')"
size="$(stat -c '%s' "$SIGNED")"

mkdir -p "$(dirname "$DEPLOY_APK")"
cp -f "$SIGNED" "$DEPLOY_APK"
log "Deploy pin: $DEPLOY_APK"
log "SHA-256: $sha"
log "Size: $size bytes"
log "Refresh catalog/pins if needed; run: pipeline/wizard/gen-pipeline-js.sh"
