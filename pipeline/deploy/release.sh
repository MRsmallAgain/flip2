#!/usr/bin/env bash
# Publish a release from packed dist artifacts (A7).
#
# The project's public home moved off GitHub on 2026-11-13 (the account was
# suspended), so this drives two backends:
#
#   gitlab (default)  `glab release create`, with the assets published as
#                     **links to the package mirror** rather than uploads. The
#                     mirror already serves these bytes and catalog.json pins
#                     them; pushing ~1.4 GB of zips into GitLab's package
#                     registry would spend a 10 GiB quota duplicating files that
#                     are already hosted. Anything the mirror is missing is
#                     copied to the site bucket first, invalidated, then polled
#                     until it serves the right byte count — a release link that
#                     404s is worse than no release.
#   github            `gh release create`, uploading the same files. Kept for
#                     the day that account is reinstated.
#
# --host or FLIP2_RELEASE_HOST selects the backend.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MANIFEST="${FLIP2_RELEASE_MANIFEST:-$ROOT/pipeline/deploy/manifest.json}"
DIST="${FLIP2_RELEASE_DIST:-$ROOT/pipeline/deploy/dist}"
MIRROR="${FLIP2_PACKAGES_URL:-https://flip2burn.online/packages}"
STACK="${FLIP2_SITE_STACK:-flip2burn-site}"
REGION="${FLIP2_SITE_REGION:-us-east-1}"
REMOTE="${FLIP2_RELEASE_REMOTE:-gitlab}"
HOST="${FLIP2_RELEASE_HOST:-gitlab}"
REPO="${FLIP2_RELEASE_REPO:-}"

usage() {
  cat <<EOF
Usage: flip2 release [--host gitlab|github] [--dry-run] [--notes FILE]
                     [--republish] [--skip-site]

Create the release v<manifest.version> from:
  flip2-installer-clean-magisk.zip
  flip2-installer-base-magisk.zip
  flip2-installer-full-magisk.zip
  flip2-installer-slim-magisk.zip
  flip2-installer-image-post-magisk.zip
  flip2-packages-<version>.zip (zip dist/flip2-packages-<version>/ first)
  flip2-system-tree-<version>.zip (zip dist/flip2-system-tree/ first)
  SHA256SUMS (regenerated from the files above on every run)

Pack first: flip2 installer pack --flavor clean|base|full|slim|image-post; flip2 pack-all; flip2 image build-tree

Backends:
  gitlab   (default) assets are release links to $MIRROR,
           not uploads. Anything missing from the mirror is copied to the site
           bucket, invalidated, then polled until it serves the right size.
  github   uploads the files to a GitHub release, as before.

  --host HOST  gitlab|github (default: \$FLIP2_RELEASE_HOST, else gitlab)
  --dry-run    Print the commands that would run, and the regenerated sums
  --notes      Release notes markdown file (required for a new release; on
               --republish the existing body is kept when this is omitted)
  --republish  Update an existing release instead of creating one
  --skip-site  Skip flip2burn.online sync afterwards (default: deploy site)

Env:
  FLIP2_RELEASE_HOST     gitlab|github
  FLIP2_RELEASE_REPO     OWNER/REPO to publish to (default: this repo)
  FLIP2_RELEASE_REMOTE   git remote that must already hold master (default: $REMOTE)
  FLIP2_RELEASE_DIST     directory holding the packed assets (default: dist/)
  FLIP2_RELEASE_MANIFEST manifest.json to read the version from
  FLIP2_PACKAGES_URL     mirror base URL (default: $MIRROR)
  FLIP2_SITE_STACK       CloudFormation stack for the bucket (default: $STACK)
  FLIP2_SITE_REGION      its region (default: $REGION)
EOF
}

DRY=0
NOTES=""
SKIP_SITE=0
REPUBLISH=0
while [ $# -gt 0 ]; do
  case "$1" in
    --host) HOST="${2:-}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --notes) NOTES="${2:-}"; shift 2 ;;
    --republish) REPUBLISH=1; shift ;;
    --skip-site) SKIP_SITE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown: $1" >&2; usage >&2; exit 1 ;;
  esac
done

command -v jq >/dev/null || { echo "jq not found" >&2; exit 1; }
command -v curl >/dev/null || { echo "curl not found" >&2; exit 1; }
case "$HOST" in
  gitlab) command -v glab >/dev/null || { echo "glab not found (needed for --host gitlab)" >&2; exit 1; } ;;
  github) command -v gh >/dev/null || { echo "gh not found (needed for --host github)" >&2; exit 1; } ;;
  *) echo "unknown host: $HOST (gitlab|github)" >&2; exit 2 ;;
esac

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

# Optional mirror assets (not part of Magisk SHA256SUMS): Companion AppImage / Windows exe.
COMPANION_VER="$(jq -r '.version // empty' "$ROOT/companion/package.json" 2>/dev/null || true)"
COMPANION_LINUX_NAME=""
COMPANION_WIN_NAME=""
COMPANION_DIST="$ROOT/companion/dist"
if [[ -n "$COMPANION_VER" ]]; then
  COMPANION_LINUX_NAME="flip2-companion-${COMPANION_VER}-linux-x86_64.AppImage"
  if [[ ! -f "$DIST/$COMPANION_LINUX_NAME" ]]; then
    COMPANION_LINUX_NAME=""
  fi
  COMPANION_WIN_NAME="flip2-companion-${COMPANION_VER}-win-x64.exe"
  if [[ ! -f "$DIST/$COMPANION_WIN_NAME" && ! -f "$COMPANION_DIST/$COMPANION_WIN_NAME" ]]; then
    COMPANION_WIN_NAME=""
  fi
fi

# What the GitLab backend links to. SHA256SUMS is included so a release page can
# be checked with `sha256sum -c` without going back to the repo.
RELEASE_NAMES=("${ASSET_NAMES[@]}" "SHA256SUMS")
[[ -n "$COMPANION_LINUX_NAME" ]] && RELEASE_NAMES+=("$COMPANION_LINUX_NAME")
[[ -n "$COMPANION_WIN_NAME" ]] && RELEASE_NAMES+=("$COMPANION_WIN_NAME")

asset_path() {
  local n="$1"
  if [[ -f "$DIST/$n" ]]; then echo "$DIST/$n"; return; fi
  if [[ -f "$COMPANION_DIST/$n" ]]; then echo "$COMPANION_DIST/$n"; return; fi
  echo "$DIST/$n"
}
file_size() { stat -c%s "$(asset_path "$1")"; }
file_sha() { sha256sum "$(asset_path "$1")" | awk '{print $1}'; }

mirror_code() {  # mirror_code <name> -> HTTP status of a 1-byte range GET
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' -r 0-0 --max-time 30 "$MIRROR/$1" || echo 000)"
  printf '%s' "$code"
}

mirror_size() {  # mirror_size <name> -> Content-Length, empty on failure
  # tolower() rather than IGNORECASE: that is a gawk extension, and the default
  # awk on Debian/Ubuntu is mawk, where the header test silently never matched —
  # every file then looked absent and the publisher refused to run.
  curl -sI --max-time 30 "$MIRROR/$1" \
    | awk 'tolower($1) == "content-length:" {print $2}' | tr -d '\r'
}

BUCKET_CACHE=""
mirror_bucket() {  # mirror_bucket -> site bucket name (cached; empty without aws)
  if [[ -z "$BUCKET_CACHE" ]]; then
    BUCKET_CACHE="$(aws cloudformation describe-stacks --region "$REGION" --stack-name "$STACK" \
      --query "Stacks[0].Outputs[?OutputKey=='BucketName'].OutputValue" --output text 2>/dev/null || true)"
  fi
  printf '%s' "$BUCKET_CACHE"
}

mirror_sha() {  # mirror_sha <name> -> sha256 stamped into object metadata at upload
  local bucket
  command -v aws >/dev/null || return 0
  bucket="$(mirror_bucket)"
  [[ -n "$bucket" && "$bucket" != None ]] || return 0
  aws s3api head-object --bucket "$bucket" --key "packages/$1" \
    --query 'Metadata.sha256' --output text 2>/dev/null | tr -d '\r' | sed 's/^None$//'
}

mirror_ok() {  # 0 when the mirror serves OUR bytes, not merely our byte count
  local code got stamped
  code="$(mirror_code "$1")"
  { [[ "$code" == 200 ]] || [[ "$code" == 206 ]]; } || return 1
  got="$(mirror_size "$1")"
  [[ "$got" == "$(file_size "$1")" ]] || return 1
  # A size match is not an identity match. The rebuilt clean/image-post zips and
  # SHA256SUMS came out at exactly the previous release's byte counts, so size
  # alone read as "already mirrored" and was skipped: v1.4.0-alpha.5 shipped
  # fresh links onto stale bytes. Compare the sha256 stamped into S3 object
  # metadata at upload instead (read via the S3 API, not HTTP, so no CDN
  # header-forwarding dependency). An object without a stamp predates this check
  # and is re-mirrored once to acquire one.
  stamped="$(mirror_sha "$1")"
  if [[ -z "$stamped" ]]; then
    command -v aws >/dev/null || { echo "WARN: no aws CLI; $1 verified by size only" >&2; return 0; }
    echo "    $1 carries no sha256 metadata on the bucket — re-mirroring to stamp it" >&2
    return 1
  fi
  [[ "$stamped" == "$(file_sha "$1")" ]]
}

mirror_upload() {  # mirror_upload <name>...
  local bucket dist_id n code got ok i want
  local -a paths=()
  command -v aws >/dev/null || { echo "aws CLI not found; cannot mirror: $*" >&2; exit 1; }
  bucket="$(aws cloudformation describe-stacks --region "$REGION" --stack-name "$STACK" \
    --query "Stacks[0].Outputs[?OutputKey=='BucketName'].OutputValue" --output text 2>/dev/null || true)"
  dist_id="$(aws cloudformation describe-stacks --region "$REGION" --stack-name "$STACK" \
    --query "Stacks[0].Outputs[?OutputKey=='DistributionId'].OutputValue" --output text 2>/dev/null || true)"
  [[ -n "$bucket" && "$bucket" != None ]] \
    || { echo "stack $STACK has no BucketName (region $REGION)" >&2; exit 1; }

  for n in "$@"; do
    want="$(file_size "$n")"
    sha="$(file_sha "$n")"
    echo "==> mirror: packages/$n ($want bytes, sha256 ${sha:0:16})"
    # The sha256 stamp is what mirror_ok() compares on the next run: byte count
    # alone let a rebuilt asset that matched its predecessor's size be skipped.
    aws s3 cp "$(asset_path "$n")" "s3://$bucket/packages/$n" \
      --content-type application/octet-stream \
      --cache-control "public,max-age=86400" \
      --metadata "sha256=$sha" >/dev/null
    paths+=("/packages/$n")
  done

  # S3 answers 403 for a missing key when ListBucket is denied, and CloudFront
  # caches that 403 — so a fresh upload can still read 403 until the path is
  # invalidated. Invalidate, then poll, rather than failing on a cache artefact
  # or claiming success on one.
  if [[ -n "$dist_id" && "$dist_id" != None ]]; then
    echo "==> invalidating ${#paths[@]} mirror path(s)"
    aws cloudfront create-invalidation --distribution-id "$dist_id" --paths "${paths[@]}" >/dev/null
  else
    echo "WARN: stack $STACK has no DistributionId; skipping invalidation" >&2
  fi

  for n in "$@"; do
    ok=0
    for i in $(seq 1 12); do
      if mirror_ok "$n"; then ok=1; break; fi
      sleep 5
    done
    if [[ "$ok" -ne 1 ]]; then
      code="$(mirror_code "$n")"; got="$(mirror_size "$n")"
      echo "mirror is not serving $n after upload (HTTP $code, size '${got}', wanted $(file_size "$n"))" >&2
      echo "the release was NOT created — fix the mirror and re-run" >&2
      exit 1
    fi
    echo "    OK: packages/$n"
  done
}

# --- gitlab helpers ----------------------------------------------------------
# API paths are absolute and project-qualified, so nothing here depends on which
# git remote glab would infer from the working directory.
urlenc() { printf '%s' "$1" | jq -Rr @uri; }

PROJECT=""
if [[ "$HOST" == gitlab ]]; then
  if [[ -n "$REPO" ]]; then
    PROJECT="$REPO"
  else
    PROJECT="$(glab api '/projects/:fullpath' 2>/dev/null | jq -r '.path_with_namespace // empty' || true)"
  fi
  [[ -n "$PROJECT" ]] \
    || { echo "could not resolve the GitLab project (set FLIP2_RELEASE_REPO)" >&2; exit 1; }
fi

mirror_missing=()
if [[ "$HOST" == gitlab ]]; then
  for n in "${RELEASE_NAMES[@]}"; do
    if ! mirror_ok "$n"; then mirror_missing+=("$n"); fi
  done
fi

links_json=""
if [[ "$HOST" == gitlab ]]; then
  links_json="$(jq -n --arg base "$MIRROR" \
    '$ARGS.positional | map({name: ., url: ($base + "/" + .), link_type: "package"})' \
    --args "${RELEASE_NAMES[@]}")"
fi

if [[ "$DRY" -eq 1 ]]; then
  if ((${#mirror_missing[@]})); then
    total=0
    for n in "${mirror_missing[@]}"; do total=$((total + $(file_size "$n"))); done
    echo "would mirror first (not yet on $MIRROR):"
    for n in "${mirror_missing[@]}"; do printf '  - %-42s %12s\n' "$n" "$(file_size "$n")"; done
    echo "  total: $total bytes"
    echo
  fi
  if [[ "$HOST" == gitlab ]]; then
    echo "glab release create \"$TAG\" --repo \"$PROJECT\" --ref master \\"
    echo "  --name \"flip2 toolkit $TAG\" --notes-file NOTES \\"
    echo "  --assets-links '<${#RELEASE_NAMES[@]} links to $MIRROR>'"
    printf '%s\n' "$links_json" | jq -c '.[]' | sed 's/^/  /'
  else
    if [[ "$REPUBLISH" -eq 1 ]]; then
      echo "gh release upload \"$TAG\" --clobber \\"
    else
      echo "gh release create \"$TAG\" --target master --title \"flip2 toolkit $TAG\" --notes-file NOTES \\"
    fi
    printf '  %q\n' "${ASSETS[@]}"
  fi
  echo
  echo "SHA256SUMS ($(grep -c . "$DIST/SHA256SUMS") files):"
  sed 's/^/  /' "$DIST/SHA256SUMS"
  if [[ "$SKIP_SITE" -eq 0 ]]; then
    echo
    echo "then: \"$ROOT/pipeline/deploy/deploy-site.sh\""
  else
    echo "(site deploy skipped)"
  fi
  exit 0
fi

if [[ "$HOST" == gitlab ]]; then
  # --ref tags what is already pushed, so an unpushed master would publish a
  # release for commits nobody can fetch.
  git ls-remote --exit-code --heads "$REMOTE" master >/dev/null 2>&1 \
    || { echo "master is not on remote '$REMOTE' — push it first" >&2; exit 1; }

  # `glab release create` also updates an existing release, replacing its asset
  # links with the ones given. That would blank the body on a republish, so when
  # no --notes was supplied the current description is read back and re-sent.
  notes_tmp=""
  if [[ "$REPUBLISH" -eq 1 && -z "$NOTES" ]]; then
    notes_tmp="$(mktemp)"
    trap 'rm -f "$notes_tmp"' EXIT
    existing="$(glab api "/projects/$(urlenc "$PROJECT")/releases/$(urlenc "$TAG")" 2>/dev/null || true)"
    if [[ -z "$existing" ]] || [[ -n "$(printf '%s' "$existing" | jq -r '.message // empty')" ]]; then
      echo "no readable release $TAG on $PROJECT to republish" >&2
      exit 1
    fi
    printf '%s' "$existing" | jq -r '.description // ""' > "$notes_tmp"
    NOTES="$notes_tmp"
    echo "==> republish: keeping the existing release body ($(wc -c < "$notes_tmp") bytes)"
  fi

  # Validate the notes before uploading anything: a run that is going to fail on
  # a missing --notes must not have already pushed hundreds of megabytes into the
  # mirror.
  if [[ -n "$NOTES" ]]; then
    [[ -f "$NOTES" ]] || { echo "--notes file not found: $NOTES" >&2; exit 1; }
  elif [[ "$REPUBLISH" -eq 0 ]]; then
    echo "--notes FILE required for a new release (markdown release body)" >&2
    exit 1
  fi

  if ((${#mirror_missing[@]})); then
    mirror_upload "${mirror_missing[@]}"
  fi

  glab release create "$TAG" --repo "$PROJECT" --ref master \
    --name "flip2 toolkit $TAG" --notes-file "$NOTES" \
    --assets-links "$links_json"

  # Read it back. A release page whose links 404 is precisely the failure this
  # backend exists to prevent, so the published state is checked, not assumed.
  published="$(glab api "/projects/$(urlenc "$PROJECT")/releases/$(urlenc "$TAG")" 2>/dev/null || true)"
  [[ -n "$published" ]] || { echo "release $TAG is not readable after publishing" >&2; exit 1; }
  [[ "$(printf '%s' "$published" | jq -r '.tag_name // empty')" == "$TAG" ]] \
    || { echo "release $TAG came back with the wrong tag" >&2; exit 1; }

  bad=0
  for n in "${RELEASE_NAMES[@]}"; do
    url="$(printf '%s' "$published" | jq -r --arg n "$n" '.assets.links[]? | select(.name == $n) | .url' | head -1)"
    if [[ "$url" != "$MIRROR/$n" ]]; then
      echo "  MISSING LINK  $n (got '${url:-none}')" >&2
      bad=1
    elif ! mirror_ok "$n"; then
      echo "  DEAD LINK     $n -> $url" >&2
      bad=1
    else
      echo "  OK            $n"
    fi
  done
  [[ "$bad" -eq 0 ]] || { echo "release $TAG has broken links — see above" >&2; exit 1; }

  echo "Published $TAG on $PROJECT (${#RELEASE_NAMES[@]} verified links to $MIRROR)"
else
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
fi

if [[ "$SKIP_SITE" -eq 0 ]]; then
  "$ROOT/pipeline/deploy/deploy-site.sh"
fi
