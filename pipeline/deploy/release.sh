#!/usr/bin/env bash
# Publish a release from packed dist artifacts (A7).
#
# Uses `gh`, so it targets whichever host that CLI is authenticated against.
# The original github.com/MRsmallAgain/flip2 repository is unreachable now
# (the account is suspended), so a GitHub release needs a new home first.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MANIFEST="$ROOT/pipeline/deploy/manifest.json"
DIST="$ROOT/pipeline/deploy/dist"

usage() {
  cat <<EOF
Usage: flip2 release [--dry-run] [--notes FILE] [--republish] [--skip-site]

Create the GitHub release v<manifest.version> from:
  flip2-installer-clean-magisk.zip
  flip2-installer-base-magisk.zip
  flip2-installer-full-magisk.zip
  flip2-installer-slim-magisk.zip
  flip2-installer-image-post-magisk.zip
  flip2-packages-<version>.zip (zip dist/flip2-packages-<version>/ first)
  flip2-system-tree-<version>.zip (zip dist/flip2-system-tree/ first)
  SHA256SUMS (regenerated from the files above on every run)

Pack first: flip2 installer pack --flavor clean|base|full|slim|image-post; flip2 pack-all; flip2 image build-tree

  --dry-run    Print the gh command and site deploy command only
  --notes      Release notes markdown file (required for a new release)
  --republish  Re-upload the assets onto the existing release (--clobber),
               leaving its title and notes alone unless --notes is given
  --skip-site  Skip flip2burn.online sync after GitHub publish (default: deploy site)
EOF
}

DRY=0
NOTES=""
SKIP_SITE=0
REPUBLISH=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    --notes) NOTES="${2:-}"; shift 2 ;;
    --republish) REPUBLISH=1; shift ;;
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

# Asset names, not paths: SHA256SUMS is regenerated from this list, so it is
# the single statement of what the release carries.
ASSET_NAMES=(
  "flip2-installer-clean-magisk.zip"
  "flip2-installer-base-magisk.zip"
  "flip2-installer-full-magisk.zip"
  "flip2-installer-slim-magisk.zip"
  "flip2-installer-image-post-magisk.zip"
  "flip2-packages-$VERSION.zip"
  "flip2-system-tree-$VERSION.zip"
)

missing=()
for n in "${ASSET_NAMES[@]}"; do
  [[ -f "$DIST/$n" ]] || missing+=("$DIST/$n")
done
if ((${#missing[@]})); then
  echo "Missing release assets (pack first):" >&2
  printf ' - %s\n' "${missing[@]}" >&2
  exit 1
fi

# Derive SHA256SUMS from the bytes actually being uploaded. It used to be a
# hand-maintained file and it drifted: v1.4.0-alpha.2-flip2 carried sums for
# installers built 2026-11-11 while catalog.json pinned rebuilds from 2026-11-13,
# so every `sha256sum -c` against the release failed while the zips on the
# mirror were fine. Generating it here makes that class of skew impossible.
(
  cd "$DIST"
  sha256sum "${ASSET_NAMES[@]}" > SHA256SUMS
)

ASSETS=()
for n in "${ASSET_NAMES[@]}"; do
  ASSETS+=("$DIST/$n")
done
ASSETS+=("$DIST/SHA256SUMS")

if [[ "$DRY" -eq 1 ]]; then
  if [[ "$REPUBLISH" -eq 1 ]]; then
    echo "gh release upload \"$TAG\" --clobber \\"
  else
    echo "gh release create \"$TAG\" --target master --title \"flip2 toolkit $TAG\" --notes-file NOTES \\"
  fi
  printf '  %q\n' "${ASSETS[@]}"
  echo "SHA256SUMS ($(grep -c . "$DIST/SHA256SUMS") files):"
  sed 's/^/  /' "$DIST/SHA256SUMS"
  if [[ "$SKIP_SITE" -eq 0 ]]; then
    echo "then: \"$ROOT/pipeline/deploy/deploy-site.sh\""
  else
    echo "(site deploy skipped)"
  fi
  exit 0
fi

if [[ "$REPUBLISH" -eq 1 ]]; then
  gh release upload "$TAG" --clobber "${ASSETS[@]}"
  if [[ -n "$NOTES" ]]; then
    [[ -f "$NOTES" ]] || { echo "--notes file not found: $NOTES" >&2; exit 1; }
    gh release edit "$TAG" --notes-file "$NOTES"
  fi
  echo "Republished assets for $TAG"
else
  [[ -n "$NOTES" && -f "$NOTES" ]] || {
    echo "--notes FILE required for a new release (markdown release body)" >&2
    exit 1
  }
  gh release create "$TAG" --target master --title "flip2 toolkit $TAG" --notes-file "$NOTES" "${ASSETS[@]}"
  echo "Published $TAG"
fi

if [[ "$SKIP_SITE" -eq 0 ]]; then
  "$ROOT/pipeline/deploy/deploy-site.sh"
fi
