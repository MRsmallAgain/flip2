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

echo ""
echo "# --- Null Keyboard + HOME (system preloads; image-post skips duplicate APKs) ---"
IME_PKG="$(jq -r '.components[] | select(.name=="ime") | .package' "$MANIFEST")"
jq -r '.components[] | select(.name=="ime") | .settings[]? // empty' "$MANIFEST" \
  | while IFS=' ' read -r ns key val; do
      printf "settings put %s '%s' '%s'\n" "$ns" "$key" "$val"
    done
jq -r '.components[] | select(.name=="ime") | .appops[]? // empty' "$MANIFEST" \
  | while IFS=' ' read -r op mode; do
      printf "appops set --user 0 %s %s %s\n" "$IME_PKG" "$op" "$mode"
    done
jq -r '.components[] | select(.name=="ime") | .permissions[]? // empty' "$MANIFEST" \
  | while read -r perm; do
      printf "pm grant %s %s\n" "$IME_PKG" "$perm"
    done
HOME_ACT="$(jq -r '.components[] | select(.name=="launcher4") | .home_activity // empty' "$MANIFEST")"
if [[ -n "$HOME_ACT" ]]; then
  printf "cmd package set-home-activity %s\n" "$HOME_ACT"
fi

echo ""
echo "# --- gamepad.conf (image_policy.block_cursor_hold) ---"
PKGS="$(jq -r '
  [.components[]
   | select((.tiers | index("image")) or (.tiers | index("full")))
   | select(.image_policy.block_cursor_hold == true)
   | .package
   | select(. != null and . != "")] | unique | join(",")' "$MANIFEST")"
if [[ -n "$PKGS" ]]; then
  printf "mkdir -p /data/local/flip2\n"
  printf "GP=/data/local/flip2/gamepad.conf\n"
  printf '[ ! -f "$GP" ] && printf '\''landscape_auto=1\nenabled=0\n'\'' > "$GP"\n'
  printf 'sed -i '\''/^block_cursor_toggle_packages=/d'\'' "$GP" 2>/dev/null || true\n'
  printf 'echo '\''block_cursor_toggle_packages=%s'\'' >> "$GP"\n' "$PKGS"
  printf 'chmod 0664 "$GP" 2>/dev/null || true\n'
fi
