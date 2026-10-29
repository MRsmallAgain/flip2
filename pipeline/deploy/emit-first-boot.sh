#!/usr/bin/env bash
# Emit image-tier settings lines for first-boot.sh (A5). Same rules as emit.sh home_keys + display.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MANIFEST="$ROOT/pipeline/deploy/manifest.json"
HOME_KEYS="$ROOT/launcher-overlay/home-keys.json"

command -v jq >/dev/null || { echo "jq not found" >&2; exit 1; }

declare -A HKMAP=(
  [left]=keyshortcut_leftkey
  [right]=keyshortcut_rightkey
  [up]=keyshortcut_upkey
  [down]=keyshortcut_downkey
  [shortcuts_bar]=keyshortcut_shortcutsbar
)

echo "# --- home keys (keyshortcut_*) ---"
for k in left right shortcuts_bar up down; do
  v="$(jq -r --arg k "$k" '.[$k] // ""' "$HOME_KEYS")"
  [[ -n "$v" ]] || continue
  gk="${HKMAP[$k]}"
  printf "settings put global '%s' '%s'\n" "$gk" "$v"
done

echo ""
echo "# --- display (manifest image tier) ---"
jq -r '.components[]
  | select((.tiers | index("image")) and .artifact == "settings-write" and .name != "home_keys")
  | .settings[]? // empty' "$MANIFEST" \
  | while IFS=' ' read -r ns key val; do
      printf "settings put %s '%s' '%s'\n" "$ns" "$key" "$val"
    done
