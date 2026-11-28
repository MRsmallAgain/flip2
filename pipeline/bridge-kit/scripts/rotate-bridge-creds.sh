#!/usr/bin/env bash
# Generate fresh bridge/VPS secrets and write pipeline/bridge-kit/.env (never commit).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/.env}"
SERVER_NAME="${SYNAPSE_SERVER_NAME:-bridge.flip2burn.online}"
ADMIN_LOCAL="${MATRIX_ADMIN_LOCALPART:-flip2admin}"
ADMIN_MXID="@${ADMIN_LOCAL}:${SERVER_NAME}"

rand() {
  local nbytes="${1:-32}"
  openssl rand -hex "$nbytes"
}

umask 077
mkdir -p "$(dirname "$OUT")"

if [[ -f "$OUT" && "${FLIP2_BRIDGE_ROTATE_FORCE:-}" != "1" ]]; then
  echo "Refusing to overwrite $OUT (set FLIP2_BRIDGE_ROTATE_FORCE=1 to replace)." >&2
  exit 1
fi

REG_SECRET="$(rand 32)"
PG_PASS="$(rand 24)"
ADMIN_PASS="$(openssl rand -base64 24 | tr -d '/+=' | head -c 20)"

cat >"$OUT" <<EOF
# Generated $(date -u +%Y-%m-%dT%H:%M:%SZ) by rotate-bridge-creds.sh — DO NOT COMMIT
# After rotation on a live host: patch homeserver volume, restart postgres+synapse, reset admin login.

SYNAPSE_SERVER_NAME=${SERVER_NAME}
HOMESERVER_URL=https://${SERVER_NAME}
SYNAPSE_REGISTRATION_SHARED_SECRET=${REG_SECRET}
POSTGRES_PASSWORD=${PG_PASS}

# Break-glass admin only — apply with FLIP2_BRIDGE_BREAK_GLASS=1 on VPS; not for daily onboarding
MATRIX_ADMIN_LOCALPART=${ADMIN_LOCAL}
MATRIX_ADMIN_MXID=${ADMIN_MXID}
MATRIX_ADMIN_PASSWORD=${ADMIN_PASS}
MAUTRIX_ADMIN_MXID=${ADMIN_MXID}

# mautrix appservice tokens are generated inside bridge volumes (register-bridges.sh).

SYNAPSE_HTTP_PORT=8008
EOF

chmod 600 "$OUT"
echo "Wrote secrets to: $OUT"
echo "Admin MXID: ${ADMIN_MXID}"
echo "Next on VPS: source .env → patch homeserver → register_new_matrix_user → restart stack."
