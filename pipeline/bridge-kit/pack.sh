#!/usr/bin/env bash
# Pack flip2-bridge-kit tarball for VPS/homelab deploy (no secrets).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
VERSION="${FLIP2_BRIDGE_KIT_VERSION:-1.0.0-flip2}"
OUT="${1:-$HERE/dist}"

die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*"; }

mkdir -p "$OUT"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

NAME="flip2-bridge-kit-${VERSION}"
DEST="$STAGE/$NAME"

mkdir -p "$DEST/docs" "$DEST/caddy" "$DEST/synapse"
for f in README.md compose.vps.yml compose.synapse.yml compose.prod.yml .env.example bootstrap-ec2.sh; do
  [ -f "$HERE/$f" ] || die "missing $f"
  cp "$HERE/$f" "$DEST/"
done
cp "$HERE/caddy/Caddyfile" "$DEST/caddy/" 2>/dev/null || true
	cp "$HERE/synapse/homeserver.yaml.example" "$DEST/synapse/" 2>/dev/null || true
	if [ -d "$HERE/scripts" ]; then
	  cp -r "$HERE/scripts" "$DEST/"
	fi
cp "$ROOT/docs/BRIDGE-HOSTING.md" "$ROOT/docs/BRIDGES-FLIP2.md" \
  "$ROOT/docs/BRIDGE-FLIP2BURN-ONLINE.md" "$DEST/docs/" 2>/dev/null || true

cat >"$DEST/INSTALL.md" <<'EOF'
# Flip2 bridge kit — VPS or bridge.flip2burn.online

## Public host (recommended)

See `docs/BRIDGE-FLIP2BURN-ONLINE.md`. Deploy stack `flip2burn-bridge`, extract kit to
`/opt/flip2-bridge`, run `sudo bash bootstrap-ec2.sh`.

FluffyChat homeserver: `https://bridge.flip2burn.online`

## Generic VPS

1. Extract tarball on the server; `cp .env.example .env` (secrets on host only).
2. Generate Synapse; merge `synapse/homeserver.yaml.example` into `data/homeserver.yaml`.
3. Register mautrix appservices (upstream docs).
4. Start:
   `docker compose -f compose.synapse.yml -f compose.vps.yml -f compose.prod.yml --profile synapse --profile bridges up -d`
5. Flip2: `flip2 fluffychat release` → Sign in with your public base URL.
EOF

ARCHIVE="$OUT/${NAME}.tar.gz"
tar -C "$STAGE" -czf "$ARCHIVE" "$NAME"
sha256sum "$ARCHIVE" | tee "$OUT/${NAME}.sha256"
log "Packed: $ARCHIVE"
