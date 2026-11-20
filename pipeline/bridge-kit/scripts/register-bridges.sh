#!/usr/bin/env bash
# Generate mautrix configs + appservice YAMLs and register with Synapse.
set -euo pipefail

ROOT="${FLIP2_BRIDGE_ROOT:-/opt/flip2-bridge}"
cd "$ROOT"

SYNAPSE_SERVER_NAME="${SYNAPSE_SERVER_NAME:-bridge.flip2burn.online}"
MAUTRIX_HOMESERVER_URL="${MAUTRIX_HOMESERVER_URL:-http://synapse:8008}"
MAUTRIX_ADMIN_MXID="${MAUTRIX_ADMIN_MXID:-@flip2admin:${SYNAPSE_SERVER_NAME}}"
PATCH_PY="${ROOT}/scripts/patch-mautrix-config.py"
HS_VOL="flip2-bridge_synapse-data"

log() { echo "==> $*"; }

register_one() {
  local name=$1 bin=$2 image=$3 url=$4
  local vol="flip2-bridge_mautrix-${name}-data"

  if ! docker run --rm -v "${vol}:/data" --entrypoint test "$image" -f /data/config.yaml 2>/dev/null; then
    log "$name: example config"
    docker run --rm -v "${vol}:/data" -u 0:0 --entrypoint "$bin" "$image" -e
  else
    log "$name: config exists, patching"
  fi

  if [[ -f "$PATCH_PY" ]]; then
    docker run --rm -v "${vol}:/data" \
      -e MAUTRIX_HOMESERVER_URL -e SYNAPSE_SERVER_NAME -e MAUTRIX_ADMIN_MXID \
      -v "$PATCH_PY:/patch.py:ro" python:3.11-alpine python3 /patch.py
  fi

  log "$name: registration"
  docker run --rm -v "${vol}:/data" -u 0:0 --entrypoint "$bin" "$image" \
    -g -c /data/config.yaml -r /data/registration.yaml

  mkdir -p appservices
  docker run --rm -v "${vol}:/data" --entrypoint cat "$image" /data/registration.yaml \
    > "appservices/${name}.yaml"

  docker run --rm -v "$(pwd)/appservices:/appservices" \
    -e "REG_PATH=/appservices/${name}.yaml" -e "APPSERVICE_URL=${url}" \
    -v "${ROOT}/scripts/patch-registration-urls.py:/patch.py:ro" \
    python:3.11-alpine python3 /patch.py

  docker run --rm -v "${HS_VOL}:/data" -u 0:0 -v "$(pwd)/appservices:/host:ro" alpine \
    sh -c "mkdir -p /data/appservices && cp /host/${name}.yaml /data/appservices/${name}.yaml"

  echo "$name" >> /tmp/registered-bridges.list
}

export MAUTRIX_HOMESERVER_URL SYNAPSE_SERVER_NAME MAUTRIX_ADMIN_MXID
: > /tmp/registered-bridges.list

register_one whatsapp /usr/bin/mautrix-whatsapp dock.mau.dev/mautrix/whatsapp:latest http://mautrix-whatsapp:29318 || true
register_one signal /usr/bin/mautrix-signal dock.mau.dev/mautrix/signal:latest http://mautrix-signal:29328 || true
register_one gvoice /usr/bin/mautrix-gvoice dock.mau.dev/mautrix/gvoice:latest http://mautrix-gvoice:29338 || true

log "Patch homeserver app_service_config_files"
if [[ ! -s /tmp/registered-bridges.list ]]; then
  log "no bridges registered; skipping synapse patch"
  exit 1
fi
docker run --rm -v "${HS_VOL}:/data" -v /tmp/registered-bridges.list:/tmp/list:ro \
  -v "${ROOT}/scripts/patch-synapse-appservices.py:/patch.py:ro" \
  python:3.11-alpine python3 /patch.py

log "Restart synapse + start bridges"
docker compose -f compose.synapse.yml -f compose.vps.yml -f compose.prod.yml \
  --profile synapse --profile bridges up -d
