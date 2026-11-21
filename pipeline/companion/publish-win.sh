#!/usr/bin/env bash
# Pin a native Windows Companion .exe and optionally sync it to the mirror.
# Does not walk the full catalog (no neutron.img fetch).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CATALOG="$ROOT/wizard/catalog.json"
DIST="$ROOT/pipeline/deploy/dist"

die() { echo "$*" >&2; exit 1; }

command -v jq >/dev/null || die "jq not found"
command -v sha256sum >/dev/null || die "sha256sum not found"
[[ -f "$CATALOG" ]] || die "missing $CATALOG"

EXE=""
DRY=0
NO_SYNC=0
COMMIT_MSG=""

usage() {
  cat <<'EOF'
Usage: flip2 companion publish-win --file PATH [options]

  Update wizard/catalog.json companion-win, pins.json, pipeline/deploy/dist/.

Options:
  --file PATH   Required
  --dry-run
  --no-sync
  --commit MSG
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --file) EXE="${2:-}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --no-sync) NO_SYNC=1; shift ;;
    --commit) COMMIT_MSG="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown: $1" ;;
  esac
done

[[ -n "$EXE" ]] || { usage >&2; die "--file is required"; }
[[ -f "$EXE" ]] || die "not a file: $EXE"

EXE="$(readlink -f "$EXE")"
base="$(basename "$EXE")"
[[ "$base" == flip2-companion-*-win-x64.exe ]] || die "expected flip2-companion-*-win-x64.exe"

size="$(stat -c%s "$EXE")"
sha="$(sha256sum "$EXE" | awk '{print $1}')"

if [ "$size" -lt 80000000 ]; then
  echo "WARN: ~86-90 MB expected (WIZARD-FAILURES #12)" >&2
fi

echo "==> companion-win: $base ($size bytes, $sha)"

if [ "$DRY" -eq 1 ]; then
  exit 0
fi

mkdir -p "$DIST"
cp -f "$EXE" "$DIST/$base"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
jq --arg file "$base" --argjson size "$size" --arg sha "$sha" \
  --arg url "https://flip2burn.online/packages/$base" \
  '(.files[] | select(.id == "companion-win") | .file) = $file
   | (.files[] | select(.id == "companion-win") | .size) = $size
   | (.files[] | select(.id == "companion-win") | .sha256) = $sha
   | (.files[] | select(.id == "companion-win") | .url) = $url' \
  "$CATALOG" > "$tmp"
mv "$tmp" "$CATALOG"
trap - EXIT

bash "$ROOT/pipeline/wizard/gen-pins.sh"

if [ -n "$COMMIT_MSG" ]; then
  git -C "$ROOT" add wizard/catalog.json wizard/pins.json
  git -C "$ROOT" commit -m "$COMMIT_MSG"
fi

if [ "$NO_SYNC" -eq 0 ] && command -v aws >/dev/null; then
  bash "$ROOT/pipeline/deploy/sync-site-packages.sh" --only companion-win
elif [ "$NO_SYNC" -eq 0 ]; then
  echo "==> run: bash pipeline/deploy/sync-site-packages.sh --only companion-win"
fi

echo "==> publish-win done"
