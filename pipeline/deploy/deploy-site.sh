#!/usr/bin/env bash
# Sync wizard/ to flip2burn.online (S3 + CloudFront). Part of flip2 release cycle.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WIZARD="$ROOT/wizard"
STACK="${FLIP2_SITE_STACK:-flip2burn-site}"
REGION="${FLIP2_SITE_REGION:-us-east-1}"

usage() {
  cat <<EOF
Usage: flip2 site deploy [--dry-run] [--skip-gen]

Sync wizard/ to the live site (CloudFormation stack: $STACK).

Before sync (unless --skip-gen):
  pipeline/wizard/gen-pipeline-js.sh

Requires: aws CLI, stack outputs BucketName + DistributionId.

Env:
  FLIP2_SITE_STACK     CloudFormation stack name (default: flip2burn-site)
  FLIP2_SITE_REGION    AWS region for stack lookup (default: us-east-1)
EOF
}

DRY=0
SKIP_GEN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    --skip-gen) SKIP_GEN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown: $1" >&2; usage >&2; exit 1 ;;
  esac
done

command -v aws >/dev/null || { echo "aws CLI not found" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq not found" >&2; exit 1; }

if [[ "$SKIP_GEN" -eq 0 ]]; then
  "$ROOT/pipeline/wizard/gen-pipeline-js.sh"
fi

BUCKET="$(aws cloudformation describe-stacks --region "$REGION" \
  --stack-name "$STACK" \
  --query "Stacks[0].Outputs[?OutputKey=='BucketName'].OutputValue" --output text 2>/dev/null || true)"
DIST="$(aws cloudformation describe-stacks --region "$REGION" \
  --stack-name "$STACK" \
  --query "Stacks[0].Outputs[?OutputKey=='DistributionId'].OutputValue" --output text 2>/dev/null || true)"

if [[ -z "$BUCKET" || "$BUCKET" == "None" || -z "$DIST" || "$DIST" == "None" ]]; then
  echo "Stack $STACK missing or no BucketName/DistributionId outputs (region $REGION)" >&2
  echo "See infra/cloudformation/README.md" >&2
  exit 1
fi

if [[ "$DRY" -eq 1 ]]; then
  echo "Would: aws s3 sync $WIZARD/ s3://${BUCKET}/ --delete ..."
  echo "Would: aws cloudfront create-invalidation --distribution-id $DIST --paths '/*'"
  echo "Site: https://flip2burn.online/"
  exit 0
fi

echo "==> syncing wizard/ -> s3://${BUCKET}/"
aws s3 sync "$WIZARD/" "s3://${BUCKET}/" --delete \
  --cache-control "public,max-age=300" \
  --exclude ".git/*"
echo "==> CloudFront invalidation /*"
aws cloudfront create-invalidation --distribution-id "$DIST" --paths "/*" >/dev/null
echo "==> live: https://flip2burn.online/ (catalog $(jq -r '.version' "$WIZARD/catalog.json"))"
