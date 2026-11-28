#!/usr/bin/env bash
# Push pipeline/bridge-kit/.env values to AWS SSM (SecureString). Requires aws CLI + IAM.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${1:-$ROOT/.env}"
PREFIX="${FLIP2_BRIDGE_SSM_PREFIX:-/flip2/bridge}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE — run rotate-bridge-creds.sh first." >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a
source "$ENV_FILE"
set +a

put() {
  local name=$1 value=$2
  [[ -n "$value" ]] || return 0
  aws ssm put-parameter \
    --name "${PREFIX}/${name}" \
    --type SecureString \
    --value "$value" \
    --overwrite \
    --description "Flip2 bridge (generated $(date -u +%Y-%m-%d))" \
    >/dev/null
  echo "SSM ${PREFIX}/${name}"
}

put SYNAPSE_REGISTRATION_SHARED_SECRET "${SYNAPSE_REGISTRATION_SHARED_SECRET:-}"
put POSTGRES_PASSWORD "${POSTGRES_PASSWORD:-}"
put MATRIX_ADMIN_PASSWORD "${MATRIX_ADMIN_PASSWORD:-}"
put SYNAPSE_SERVER_NAME "${SYNAPSE_SERVER_NAME:-}"
put MATRIX_ADMIN_MXID "${MATRIX_ADMIN_MXID:-}"

echo "Done. Fetch on EC2 via SSM or merge into /opt/flip2-bridge/.env"
