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
  | select(.external)
  | select((.external.asset // .incoming // "") != "")
  | (if ((.external.url // "") != "") then
       [.name, .external.url, (.external.asset // .incoming // "unknown.apk")]
     elif ((.external.repo // "") != "") and ((.external.tag // "") != "") then
       [.name,
        ("https://github.com/" + .external.repo + "/releases/download/" + .external.tag + "/" + (.external.asset // .incoming)),
        (.external.asset // .incoming // "unknown.apk")]
     else
       empty
     end)
  | @tsv
' "$MANIFEST")

SHERPA_JSON="$ROOT/pipeline/deploy/sherpa-models.json"
if [[ -f "$SHERPA_JSON" ]]; then
  while IFS=$'\t' read -r id url file; do
    [[ -n "$url" && -n "$file" ]] || continue
    out="$DEST/$file"
    if [[ -f "$out" ]]; then
      echo "skip (exists): $file"
      continue
    fi
    echo "fetch: $id -> $file"
    curl -fsSL -o "$out" "$url"
  done < <(jq -r '.models[] | [.id, .url, .file] | @tsv' "$SHERPA_JSON")
fi

echo "sources in $DEST"
