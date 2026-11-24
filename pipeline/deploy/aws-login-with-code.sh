#!/usr/bin/env bash
# Send authorization code to an IN-FLIGHT aws login --remote (started by aws-remote-login-start.sh).
# Usage: aws-remote-login-start.sh   (in one terminal — it waits for you)
#        aws-login-with-code.sh CODE   (in another terminal, while start is waiting)
set -euo pipefail
export PATH="${HOME}/.local/bin:${PATH}"
RUN_DIR="${AWS_LOGIN_RUN_DIR:-/tmp/flip2-aws-login}"
FIFO="${RUN_DIR}/code.fifo"
PID_FILE="${RUN_DIR}/login.pid"
OUT="${RUN_DIR}/login.out"
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ $# -ge 1 ]]; then
  code="$1"
else
  read -r code
fi
code="${code//$'\r'/}"
code="${code#"${code%%[![:space:]]*}"}"
code="${code%"${code##*[![:space:]]}"}"
if [[ -z "$code" ]]; then
  echo "Usage: $0 AUTHORIZATION_CODE" >&2
  echo "Start first: bash $SELF_DIR/aws-remote-login-start.sh" >&2
  exit 1
fi

if [[ ! -p "$FIFO" ]]; then
  echo "No login session. Run: bash $SELF_DIR/aws-remote-login-start.sh" >&2
  exit 1
fi

printf '%s\n' "$code" >"$FIFO"

if [[ -f "$PID_FILE" ]]; then
  pid="$(cat "$PID_FILE")"
  if kill -0 "$pid" 2>/dev/null; then
    wait "$pid" 2>/dev/null || true
  fi
fi

if aws sts get-caller-identity 2>/dev/null; then
  aws sts get-caller-identity
else
  echo "Login may have failed. Last output:" >&2
  tail -15 "$OUT" 2>/dev/null || true
  exit 1
fi
