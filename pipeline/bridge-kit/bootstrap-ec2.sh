#!/usr/bin/env bash
# First-boot helper on bridge EC2 (after CloudFormation). Run as root or ec2-user.
set -euo pipefail

INSTALL_ROOT="${FLIP2_BRIDGE_ROOT:-/opt/flip2-bridge}"

die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*"; }

[ "$(id -u)" -eq 0 ] || die "run with sudo"

log "Docker status"
systemctl is-active docker >/dev/null || {
  dnf install -y docker
  systemctl enable --now docker
}
if ! docker compose version 2>/dev/null; then
  mkdir -p /usr/local/lib/docker/cli-plugins
  curl -fsSL https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-x86_64 \
    -o /usr/local/lib/docker/cli-plugins/docker-compose
  chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
fi

usermod -aG docker ec2-user 2>/dev/null || true
mkdir -p "$INSTALL_ROOT"
cd "$INSTALL_ROOT"

if [ ! -f compose.synapse.yml ]; then
  log "Extract flip2-bridge-kit tarball into $INSTALL_ROOT first"
  exit 1
fi

if [ ! -f .env ]; then
  cp .env.example .env
  log "Edit .env — set SYNAPSE_SERVER_NAME=bridge.flip2burn.online and secrets (SSM)"
  exit 1
fi

# shellcheck source=/dev/null
set -a && source .env && set +a

if ! docker compose -f compose.synapse.yml --profile synapse run --rm --no-deps --entrypoint test synapse -f /data/homeserver.yaml 2>/dev/null; then
  log "Generate Synapse config (one-time; config lives in Docker volume synapse-data)"
  docker compose -f compose.synapse.yml --profile synapse run --rm \
    -e SYNAPSE_SERVER_NAME="${SYNAPSE_SERVER_NAME:-bridge.flip2burn.online}" \
    synapse generate
fi
if [ -f scripts/patch-homeserver-volume.py ]; then
  log "Patch homeserver.yaml in volume (Postgres, public_baseurl, registration off)"
  docker run --rm -v flip2-bridge_synapse-data:/data \
    -e SYNAPSE_REGISTRATION_SHARED_SECRET \
    -e POSTGRES_PASSWORD \
    -v "$INSTALL_ROOT/scripts/patch-homeserver-volume.py:/patch.py:ro" \
    python:3.11-alpine python3 /patch.py
fi

log "Starting Synapse + bridges + Caddy :8080"
docker compose \
  -f compose.synapse.yml \
  -f compose.vps.yml \
  -f compose.prod.yml \
  --profile synapse \
  --profile bridges \
  up -d

log "Health: curl -sS http://127.0.0.1:8080/_matrix/client/versions"
