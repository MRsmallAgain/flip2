#!/usr/bin/env bash
# Safe wizard-only deploy: skip gen + packages (footer/media tweaks, etc.)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export PATH="$ROOT/bin:${HOME}/.local/bin:${PATH}"

if ! aws sts get-caller-identity >/dev/null 2>&1; then
  echo "AWS session not valid. Canonical login (same-device, localhost callback):" >&2
  echo "  bash $ROOT/pipeline/deploy/aws-login-same-device-bg.sh" >&2
  echo "  # or: bash $ROOT/pipeline/deploy/aws-login-same-device.sh  (foreground)" >&2
  echo "See: $ROOT/pipeline/deploy/AWS-LOGIN.md" >&2
  exit 1
fi

echo "==> AWS OK: $(aws sts get-caller-identity --query Arn --output text)"
exec "$ROOT/pipeline/deploy/deploy-site.sh" --skip-gen --skip-packages "$@"
