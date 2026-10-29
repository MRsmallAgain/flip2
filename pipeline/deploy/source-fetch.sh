#!/usr/bin/env bash
# Download manifest external APKs into pipeline/deploy/sources/ (B2).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MANIFEST="$ROOT/pipeline/deploy/manifest.json"
DEST="$ROOT/pipeline/deploy/sources"

command -v jq >/dev/null || { echo "jq not found" >&2; exit 1; }

mkdir -p "$DEST"

while IFS=$'\t' read -r name url asset; do
  [[ -n "$url" && -n "$asset" ]] || continue
  out="$DEST/$asset"
  if [[ -f "$out" ]]; then
    echo "skip (exists): $asset"
    continue
  fi
  echo "fetch: $name -> $asset"
  curl -fsSL -o "$out" "$url"
done < <(jq -r '
  .components[]
  | select(.external.url // "" != "")
  | [.name, .external.url, (.external.asset // .incoming // "unknown.apk")] | @tsv
' "$MANIFEST")

echo "sources in $DEST"
