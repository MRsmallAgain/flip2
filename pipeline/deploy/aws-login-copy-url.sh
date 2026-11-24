#!/usr/bin/env bash
# Zorin: no Chromium auto-open (zygote). Uses aws login --remote only.
# Saves full v1/authorize URL — never open bare .../oauth (400).
#
#   bash aws-login-copy-url.sh          # leave running; copy URL from file
#   bash aws-login-with-code.sh CODE    # other terminal
#   bash site-deploy-safe.sh
set -euo pipefail
export PATH="${HOME}/.local/bin:${PATH}"
SELF="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SELF/../.." && pwd)"
RUN_DIR="${AWS_LOGIN_RUN_DIR:-/tmp/flip2-aws-login}"
FIFO="${RUN_DIR}/code.fifo"
OUT="${RUN_DIR}/login.out"
PID_FILE="${RUN_DIR}/login.pid"
URL_FILE="${RUN_DIR}/authorize.url"
DESKTOP_URL="${HOME}/Desktop/aws-authorize.url.txt"

mkdir -p "$RUN_DIR" && chmod 700 "$RUN_DIR"
pkill -f 'aws login --remote' 2>/dev/null || true
sleep 1
rm -f "$FIFO" "$OUT" "$PID_FILE" "$URL_FILE"
mkfifo "$FIFO" && chmod 600 "$FIFO"
exec 3<>"$FIFO"
aws login --remote 0<&3 >"$OUT" 2>&1 &
LOGIN_PID=$!
echo "$LOGIN_PID" >"$PID_FILE"

for i in $(seq 1 30); do
  if [[ -s "$OUT" ]] && grep -q 'Please visit' "$OUT" 2>/dev/null; then break; fi
  if ! kill -0 "$LOGIN_PID" 2>/dev/null; then break; fi
  sleep 1
done

url="$(grep -oE 'https://us-east-1.signin.aws.amazon.com/v1/authorize[^[:space:]]+' "$OUT" | head -1 || true)"
if [[ -z "$url" ]]; then
  echo "Did not get authorize URL:" >&2
  cat "$OUT" >&2
  exit 1
fi

printf '%s\n' "$url" >"$URL_FILE"
chmod 600 "$URL_FILE"
mkdir -p "$(dirname "$DESKTOP_URL")" 2>/dev/null || true
printf '%s\n' "$url" >"$DESKTOP_URL" 2>/dev/null || true

# Open full v1/authorize URL (not bare /oauth)
export DISPLAY="${DISPLAY:-:0}"
if command -v xdg-open >/dev/null 2>&1; then
  nohup xdg-open "$url" >>"${RUN_DIR}/open.log" 2>&1 &
elif command -v vivaldi >/dev/null 2>&1; then
  nohup vivaldi "$url" >>"${RUN_DIR}/open.log" 2>&1 &
fi

cat <<EOF

=== AWS login waiting (pid $LOGIN_PID) ===

STOP using: aws login  (opens browser → zygote error on Zorin)
STOP opening: https://us-east-1.signin.aws.amazon.com/oauth  (400)

1. Open file and copy the ONE long line (Ctrl+A, Ctrl+C):
   $URL_FILE
$( [[ -f "$DESKTOP_URL" ]] && echo "   Also: $DESKTOP_URL" )

2. Browser: Ctrl+L → paste entire line → Enter
   Must contain: v1/authorize and cross-device and sessions/confirmation

3. Sign in → copy AUTHORIZATION CODE from confirmation page.

4. Another terminal (while this one still runs):
   bash $SELF/aws-login-with-code.sh 'CODE'

5. bash $SELF/site-deploy-safe.sh

EOF

wait "$LOGIN_PID" || true
