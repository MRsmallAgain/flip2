#!/usr/bin/env bash
# On the VPS: load .env, patch Synapse volume, optional break-glass admin (FLIP2_BRIDGE_BREAK_GLASS=1).
# Normal user onboarding uses registration shared secret — not flip2admin. See docs/COMPANION-ONBOARDING.md
set -euo pipefail

ROOT="${FLIP2_BRIDGE_ROOT:-/opt/flip2-bridge}"
ENV_FILE="${1:-$ROOT/.env}"
HS_VOL="${SYNAPSE_DATA_VOLUME:-flip2-bridge_synapse-data}"

deck() { echo "==> $*"; }

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a
source "$ENV_FILE"
set +a

: "${SYNAPSE_REGISTRATION_SHARED_SECRET:?}"
: "${POSTGRES_PASSWORD:?}"
: "${SYNAPSE_SERVER_NAME:?}"

cd "$ROOT"
export SYNAPSE_REGISTRATION_SHARED_SECRET POSTGRES_PASSWORD SYNAPSE_SERVER_NAME

deck "Patch homeserver.yaml in Synapse volume"
docker run --rm -v "${HS_VOL}:/data" \
  -e SYNAPSE_REGISTRATION_SHARED_SECRET -e POSTGRES_PASSWORD -e SYNAPSE_SERVER_NAME \
  -v "$ROOT/scripts/patch-homeserver-volume.py:/patch.py:ro" \
  python:3.11-alpine python3 /patch.py

deck "Compose up (POSTGRES_PASSWORD only applies on fresh postgres volume)"
docker compose -f compose.synapse.yml -f compose.vps.yml -f compose.prod.yml \
  --env-file "$ENV_FILE" \
  --profile synapse --profile bridges up -d

if [[ "${FLIP2_BRIDGE_BREAK_GLASS:-}" == "1" ]] && [[ -n "${MATRIX_ADMIN_LOCALPART:-}" && -n "${MATRIX_ADMIN_PASSWORD:-}" ]]; then
  deck "Break-glass: create Matrix admin via register_new_matrix_user"
  docker compose -f compose.synapse.yml --env-file "$ENV_FILE" \
    --profile synapse exec -T synapse \
    register_new_matrix_user -c /data/homeserver.yaml \
    -u "$MATRIX_ADMIN_LOCALPART" -p "$MATRIX_ADMIN_PASSWORD" -a \
    || deck "Admin may already exist — manual password reset if rotating"
else
  deck "Skipping admin user (set FLIP2_BRIDGE_BREAK_GLASS=1 for VPS recovery only)"
fi

deck "Verify: curl -sS https://${SYNAPSE_SERVER_NAME}/_matrix/client/versions"
