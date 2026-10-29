#!/usr/bin/env bash
# Emit installer payload text files from manifest.json (+ home-keys.json for home_keys).
set -euo pipefail

usage() {
  cat <<EOF
Usage: emit.sh --flavor clean|full --manifest PATH --home-keys PATH --root PATH --data DIR

Write payload/data settings.txt, wallpaper.txt, modules.txt, and apks.txt for the selected flavor.
EOF
}

FLAVOR=""
MANIFEST=""
HOME_KEYS=""
ROOT=""
DATA=""

while [ $# -gt 0 ]; do
  case "$1" in
    --flavor) FLAVOR="${2:-}"; shift 2 ;;
    --manifest) MANIFEST="${2:-}"; shift 2 ;;
    --home-keys) HOME_KEYS="${2:-}"; shift 2 ;;
    --root) ROOT="${2:-}"; shift 2 ;;
    --data) DATA="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

[[ -n "$FLAVOR" && -n "$MANIFEST" && -n "$HOME_KEYS" && -n "$ROOT" && -n "$DATA" ]] || {
  usage >&2; exit 1
}
case "$FLAVOR" in clean|full) ;; *) echo "--flavor must be clean or full" >&2; exit 1 ;; esac

command -v jq >/dev/null || { echo "jq not found" >&2; exit 1; }

mkdir -p "$DATA"
: > "$DATA/settings.txt"
: > "$DATA/wallpaper.txt"
: > "$DATA/modules.txt"
: > "$DATA/apks.txt"

ROWS="$(jq -r --arg flavor "$FLAVOR" '
  .components[]
  | select([.tiers[]] | index($flavor))
  | [ .install_order, .name, .artifact, (.zip // ""), (.apk // ""),
      (.package // ""), (.module_id // ""), (.external.repo // ""),
      (.external.tag // ""), (.external.asset // ""), (.external.url // ""),
      (.asset // "") ] | join("|")
' "$MANIFEST" | sort -n)"

declare -A HKMAP=(
  [left]=keyshortcut_leftkey
  [right]=keyshortcut_rightkey
  [up]=keyshortcut_upkey
  [down]=keyshortcut_downkey
  [shortcuts_bar]=keyshortcut_shortcutsbar
)

while IFS='|' read -r _order name artifact zip apk pkg mid _erepo _etag _easset _eurl wpasset; do
  [[ -n "$name" ]] || continue

  case "$artifact" in
    user-apk)
      if [[ -n "$apk" && -n "$pkg" ]]; then
        base="$(basename "$apk")"
        printf '%s %s\n' "$base" "$pkg" >> "$DATA/apks.txt"
      fi
      ;;
    magisk-module)
      if [[ -n "$zip" && -n "$mid" ]]; then
        base="$(basename "$zip")"
        printf '%s %s\n' "$mid" "$base" >> "$DATA/modules.txt"
      fi
      ;;
    wallpaper)
      if [[ -n "$wpasset" ]]; then
        echo "flip2-wallpaper.png" >> "$DATA/wallpaper.txt"
      fi
      ;;
    settings-write)
      if [[ "$name" == "home_keys" ]]; then
        for k in left right shortcuts_bar up down; do
          v="$(jq -r --arg k "$k" '.[$k] // ""' "$HOME_KEYS")"
          printf "settings put global '%s' '%s'\n" "${HKMAP[$k]}" "$v" >> "$DATA/settings.txt"
        done
      elif [[ "$name" == "display" ]]; then
        jq -r '.components[] | select(.name=="display") | .settings[]? // empty' "$MANIFEST" \
          | while IFS=' ' read -r ns key val; do
              printf "settings put %s '%s' '%s'\n" "$ns" "$key" "$val"
            done >> "$DATA/settings.txt"
      fi
      ;;
  esac

  [[ -n "$pkg" ]] || continue
  jq -r --arg n "$name" '.components[] | select(.name==$n) | .settings[]? // empty' "$MANIFEST" \
    | while IFS=' ' read -r ns key val; do
        printf "settings put %s %s '%s'\n" "$ns" "$key" "${val:-}"
      done >> "$DATA/settings.txt"
done <<< "$ROWS"
