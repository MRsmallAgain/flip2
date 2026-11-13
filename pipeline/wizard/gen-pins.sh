#!/usr/bin/env bash
# Regenerate wizard/pins.json from wizard/catalog.json.
#
# pins.json is a derived snapshot: catalog.js merges it over catalog.json and
# lets pin sha256/size win. A stale copy therefore overrides good catalog pins
# and every download fails verification — the 2026-11-13 mismatch. Never
# hand-edit it; run this (or `flip2 wizard pins`) after any catalog change.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CATALOG="$ROOT/wizard/catalog.json"
OUT="$ROOT/wizard/pins.json"

CHECK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK=1; shift ;;
    -h|--help)
      echo "Usage: gen-pins.sh [--check]"
      echo "  --check  exit 1 (and print a diff) if pins.json is stale"
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

command -v jq >/dev/null || { echo "jq not found" >&2; exit 1; }
[[ -f "$CATALOG" ]] || { echo "missing $CATALOG" >&2; exit 1; }

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
jq '{version, pinned, catalog: "wizard/catalog.json", files: [.files[] | {id, file, sha256, size, url}]}' \
  "$CATALOG" > "$tmp"

if [[ "$CHECK" -eq 1 ]]; then
  if [[ -f "$OUT" ]] && cmp -s "$tmp" "$OUT"; then
    echo "OK: pins.json matches catalog.json"
    exit 0
  fi
  echo "STALE: pins.json does not match catalog.json — run flip2 wizard pins" >&2
  diff -u "$OUT" "$tmp" >&2 || true
  exit 1
fi

if [[ -f "$OUT" ]] && cmp -s "$tmp" "$OUT"; then
  echo "pins unchanged: $OUT"
else
  mv "$tmp" "$OUT"
  echo "generated: $OUT"
fi
