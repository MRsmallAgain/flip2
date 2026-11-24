#!/usr/bin/env bash
# Start same-device aws login in background (agent-friendly).
# Callback: http://127.0.0.1:45876/oauth/callback — NOT cross-device (400 after account pick).
#
#   bash aws-login-same-device-bg.sh
#   Sign in → browser should hit 127.0.0.1 briefly, then "Login successful"
#   aws sts get-caller-identity
#   bash site-deploy-safe.sh
set -euo pipefail
export PATH="${HOME}/.local/share/flip2/bin:${HOME}/.local/bin:${PATH}"
SELF="$(cd "$(dirname "$0")" && pwd)"
RUN_DIR="${AWS_LOGIN_RUN_DIR:-/tmp/flip2-aws-login}"
PORT="${AWS_LOGIN_REDIRECT_PORT:-45876}"
OUT="${RUN_DIR}/same-device.out"
URL_FILE="${RUN_DIR}/authorize-same-device.url"
READY="${RUN_DIR}/READY.txt"

mkdir -p "$RUN_DIR" && chmod 700 "$RUN_DIR"
pkill -f 'aws login --redirect-port' 2>/dev/null || true
sleep 2

export BROWSER=/bin/true
: >"$OUT"
nohup env BROWSER=/bin/true aws login --redirect-port "$PORT" < /dev/null >>"$OUT" 2>&1 &

for _ in $(seq 1 35); do
  if grep -q 'v1/authorize' "$OUT" 2>/dev/null; then break; fi
  sleep 1
done

url="$(grep -oE 'https://us-east-1.signin.aws.amazon.com/v1/authorize[^[:space:]]+' "$OUT" | tail -1)"
printf '%s\n' "$url" >"$URL_FILE"
pid="$(pgrep -f "aws login --redirect-port $PORT" | head -1)"
{
  echo "aws_pid=$pid"
  kill -0 "$pid" 2>/dev/null && echo alive=yes || echo alive=no
  ss -tlnp 2>/dev/null | grep ":$PORT" || echo NO_LISTEN
  echo "state=$(echo "$url" | grep -oE 'state=[^&]+' || echo none)"
} >"$READY"

export DISPLAY="${DISPLAY:-:0}"
if [[ -n "$url" ]] && echo "$url" | grep -q 'same-device' && [[ -n "$pid" ]]; then
  if command -v vivaldi >/dev/null 2>&1; then
    vivaldi --new-window "$url" &
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url" &
  fi
fi

cat "$READY"
echo ""
echo "URL file: $URL_FILE"
echo "After sign-in: bash $SELF/site-deploy-safe.sh"
