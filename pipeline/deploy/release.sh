#!/usr/bin/env bash
# Publish a GitHub release from packed dist artifacts (A7).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MANIFEST="$ROOT/pipeline/deploy/manifest.json"
DIST="$ROOT/pipeline/deploy/dist"

usage() {
  cat <<EOF
Usage: flip2 release [--dry-run] [--notes FILE]

Create github.com/MRsmallAgain/flip2 release v<manifest.version> from:
  flip2-installer-clean-magisk.zip
  flip2-installer-base-magisk.zip
  flip2-installer-full-magisk.zip
  flip2-installer-slim-magisk.zip
  flip2-installer-image-post-magisk.zip
  flip2-packages-<version>.zip (zip dist/flip2-packages-<version>/ first)
  flip2-system-tree-<version>.zip (zip dist/flip2-system-tree/ first)
  SHA256SUMS in dist/

Pack first: flip2 installer pack --flavor clean|base|full|slim|image-post; flip2 pack-all; flip2 image build-tree

  --dry-run   Print gh release create + site deploy commands only
  --notes     Release notes markdown file (required unless --dry-run)
  --skip-site Skip flip2burn.online sync after GitHub publish (default: deploy site)
EOF
}

DRY=0
NOTES=""
SKIP_SITE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    --notes) NOTES="${2:-}"; shift 2 ;;
    --skip-site) SKIP_SITE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown: $1" >&2; usage >&2; exit 1 ;;
  esac
done

command -v jq >/dev/null || { echo "jq not found" >&2; exit 1; }
command -v gh >/dev/null || { echo "gh not found" >&2; exit 1; }

VERSION="$(jq -r '.version // empty' "$MANIFEST")"
[[ -n "$VERSION" ]] || { echo "manifest version missing" >&2; exit 1; }
TAG="v$VERSION"

ASSETS=(
  "$DIST/flip2-installer-clean-magisk.zip"
  "$DIST/flip2-installer-base-magisk.zip"
  "$DIST/flip2-installer-full-magisk.zip"
  "$DIST/flip2-installer-slim-magisk.zip"
  "$DIST/flip2-installer-image-post-magisk.zip"
  "$DIST/flip2-packages-$VERSION.zip"
  "$DIST/flip2-system-tree-$VERSION.zip"
  "$DIST/SHA256SUMS"
)

missing=()
for a in "${ASSETS[@]}"; do
  [[ -f "$a" ]] || missing+=("$a")
done
if ((${#missing[@]})); then
  echo "Missing release assets (pack first):" >&2
  printf ' - %s\n' "${missing[@]}" >&2
  exit 1
fi

if [[ "$DRY" -eq 1 ]]; then
  echo "gh release create \"$TAG\" --target master --title \"flip2 toolkit $TAG\" --notes-file NOTES \\"
  printf '  %q \\n' "${ASSETS[@]}"
  if [[ "$SKIP_SITE" -eq 0 ]]; then
    echo "then: \"$ROOT/pipeline/deploy/deploy-site.sh\""
  else
    echo "(site deploy skipped)"
  fi
  exit 0
fi

[[ -n "$NOTES" && -f "$NOTES" ]] || {
  echo "--notes FILE required (markdown release body)" >&2
  exit 1
}

gh release create "$TAG" --target master --title "flip2 toolkit $TAG" --notes-file "$NOTES" "${ASSETS[@]}"
echo "Published $TAG"

if [[ "$SKIP_SITE" -eq 0 ]]; then
  "$ROOT/pipeline/deploy/deploy-site.sh"
fi
