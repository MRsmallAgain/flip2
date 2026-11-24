#!/usr/bin/env bash
# Start ONE aws login --remote session; print URL; wait for code on FIFO.
# Do NOT open https://us-east-1.signin.aws.amazon.com/oauth (bare) — that is 400.
set -euo pipefail
export PATH="${HOME}/.local/bin:${PATH}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUN_DIR="${AWS_LOGIN_RUN_DIR:-/tmp/flip2-aws-login}"
FIFO="${RUN_DIR}/code.fifo"
OUT="${RUN_DIR}/login.out"
PID_FILE="${RUN_DIR}/login.pid"
URL_FILE="${RUN_DIR}/authorize.url"
mkdir -p "$RUN_DIR" && chmod 700 "$RUN_DIR"
if pgrep -f 'aws login --remote' >/dev/null 2>&1; then
  pkill -f 'aws login --remote' 2>/dev/null || true
  sleep 1
fi
rm -f "$FIFO" "$OUT" "$PID_FILE" "$URL_FILE"
mkfifo "$FIFO" && chmod 600 "$FIFO"
# Read-only redirect < fifo blocks until a writer — aws never starts. Open RW instead.
exec 3<>"$FIFO"
aws login --remote 0<&3 >"$OUT" 2>&1 &
LOGIN_PID=$!
echo "$LOGIN_PID" >"$PID_FILE"
for i in $(seq 1 25); do
  if [[ -s "$OUT" ]] && grep -q 'Please visit' "$OUT" 2>/dev/null; then break; fi
  if ! kill -0 "$LOGIN_PID" 2>/dev/null; then break; fi
  sleep 1
done
url="$(grep -oE 'https://us-east-1.signin.aws.amazon.com/v1/authorize[^[:space:]]+' "$OUT" | head -1 || true)"
if [[ -z "$url" ]]; then cat "$OUT" >&2; exit 1; fi
printf '%s\n' "$url" >"$URL_FILE"
echo "=== AWS remote login (pid $LOGIN_PID) ==="
echo ""
echo "Open THIS full URL (v1/authorize + cross-device — NOT bare /oauth):"
echo "$url"
echo ""
echo "Then: bash $ROOT/pipeline/deploy/aws-login-with-code.sh 'CODE'"
wait "$LOGIN_PID" || true
