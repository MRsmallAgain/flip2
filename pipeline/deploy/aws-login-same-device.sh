#!/usr/bin/env bash
# Same-device aws login: callback to localhost (avoids cross-device confirmation 400).
# Run in THIS terminal and leave it open until login finishes.
#
#   bash aws-login-same-device.sh
#   (browser opens / sign in → redirect to 127.0.0.1 → terminal completes)
#   bash site-deploy-safe.sh
set -euo pipefail
export PATH="${HOME}/.local/share/flip2/bin:${HOME}/.local/bin:${PATH}"
SELF="$(cd "$(dirname "$0")" && pwd)"
RUN_DIR="${AWS_LOGIN_RUN_DIR:-/tmp/flip2-aws-login}"
PORT="${AWS_LOGIN_REDIRECT_PORT:-45876}"
OUT="${RUN_DIR}/same-device.out"
URL_FILE="${RUN_DIR}/authorize-same-device.url"

mkdir -p "$RUN_DIR" && chmod 700 "$RUN_DIR"
pkill -f 'aws login' 2>/dev/null || true
sleep 1

export BROWSER=/bin/true
rm -f "$OUT" "$URL_FILE"

(
  for _ in $(seq 1 30); do
    if [[ -s "$OUT" ]] && grep -q 'v1/authorize' "$OUT" 2>/dev/null; then
      url="$(grep -oE 'https://us-east-1.signin.aws.amazon.com/v1/authorize[^[:space:]]+' "$OUT" | head -1)"
      if [[ -n "$url" ]] && echo "$url" | grep -q 'same-device'; then
        printf '%s\n' "$url" >"$URL_FILE"
        export DISPLAY="${DISPLAY:-:0}"
        if command -v vivaldi >/dev/null 2>&1; then
          vivaldi --new-window "$url" &
        elif command -v xdg-open >/dev/null 2>&1; then
          xdg-open "$url" &
        fi
        break
      fi
    fi
    sleep 1
  done
) &

cat <<EOF

=== Same-device AWS login (port $PORT) ===

If you get 400 after account pick on cross-device, use this flow instead.
URL must contain: devtools/same-device and redirect_uri=127.0.0.1

If browser does not open, paste ONE line from: $URL_FILE

Leave this terminal running until login completes.

EOF

aws login --redirect-port "$PORT" 2>&1 | tee "$OUT"

if aws sts get-caller-identity >/dev/null 2>&1; then
  echo ""
  echo "==> AWS OK"
  aws sts get-caller-identity
  echo "Next: bash $SELF/site-deploy-safe.sh"
else
  echo "Login did not complete." >&2
  exit 1
fi
