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

echo ""
echo "# --- gamepad.conf (image_policy.portrait_gamepad) ---"
PORTRAIT_GP="$(jq -r '
  [.components[]
   | select((.tiers | index("image")) or (.tiers | index("full")))
   | select(.image_policy.portrait_gamepad == true)
   | .package
   | select(. != null and . != "")] | unique | join(",")' "$MANIFEST")"
if [[ -n "$PORTRAIT_GP" ]]; then
  printf "mkdir -p /data/local/flip2\n"
  printf "GP=/data/local/flip2/gamepad.conf\n"
  printf '[ ! -f "$GP" ] && printf '\''landscape_auto=1\nenabled=0\n'\'' > "$GP"\n'
  printf 'sed -i '\''/^portrait_gamepad_packages=/d'\'' "$GP" 2>/dev/null || true\n'
  printf 'echo '\''portrait_gamepad_packages=%s'\'' >> "$GP"\n' "$PORTRAIT_GP"
  printf 'chmod 0664 "$GP" 2>/dev/null || true\n'
fi

echo ""
echo "# --- gamepad.conf (image_policy.native_keypad_bypass) ---"
NATIVE_BYPASS="$(jq -r '
  [.components[]
   | select((.tiers | index("image")) or (.tiers | index("full")))
   | select(.image_policy.native_keypad_bypass == true)
   | .package
   | select(. != null and . != "")] | unique | join(",")' "$MANIFEST")"
if [[ -n "$NATIVE_BYPASS" ]]; then
  printf "mkdir -p /data/local/flip2\n"
  printf "GP=/data/local/flip2/gamepad.conf\n"
  printf '[ ! -f "$GP" ] && printf '\''landscape_auto=1\nenabled=0\n'\'' > "$GP"\n'
  printf 'sed -i '\''/^native_keypad_bypass_packages=/d'\'' "$GP" 2>/dev/null || true\n'
  printf 'echo '\''native_keypad_bypass_packages=%s'\'' >> "$GP"\n' "$NATIVE_BYPASS"
  printf 'chmod 0664 "$GP" 2>/dev/null || true\n'
fi

echo ""
echo "# --- gamepad.conf (image_policy.portrait_sdl_pointer) ---"
SDL_PTR="$(jq -r '
  [.components[]
   | select((.tiers | index("image")) or (.tiers | index("full")))
   | select(.image_policy.portrait_sdl_pointer == true)
   | .package
   | select(. != null and . != "")] | unique | join(",")' "$MANIFEST")"
if [[ -n "$SDL_PTR" ]]; then
  printf "mkdir -p /data/local/flip2\n"
  printf "GP=/data/local/flip2/gamepad.conf\n"
  printf '[ ! -f "$GP" ] && printf '\''landscape_auto=1\nenabled=0\n'\'' > "$GP"\n'
  printf 'sed -i '\''/^portrait_sdl_pointer_packages=/d'\'' "$GP" 2>/dev/null || true\n'
  # Migration: an earlier seed put SDL pointer apps on native keypad bypass.
  # Bypass detaches the keypad; these packages need Arcade attached for REL.
  # Strip every portrait_sdl_pointer package out of that line. An empty
  # remainder is deleted. Runtime sync_keypad_bypass() also refuses to
  # detach while one of these apps is foreground.
  printf '# Drop portrait SDL pointer packages from a stale keypad-bypass line.\n'
  printf 'BYP=$(sed -n '\''s/^native_keypad_bypass_packages=//p'\'' "$GP" | head -n 1)\n'
  printf 'if [ -n "$BYP" ]; then\n'
  printf '  NEW=\n'
  printf '  OLDIFS=$IFS\n'
  printf '  IFS=,\n'
  printf '  for p in $BYP; do\n'
  printf '    case ",%s," in\n' "$SDL_PTR"
  printf '      *",$p,"*) ;;\n'
  printf '      *) NEW=${NEW:+$NEW,}$p ;;\n'
  printf '    esac\n'
  printf '  done\n'
  printf '  IFS=$OLDIFS\n'
  printf '  sed -i '\''/^native_keypad_bypass_packages=/d'\'' "$GP" 2>/dev/null || true\n'
  printf '  if [ -n "$NEW" ]; then echo "native_keypad_bypass_packages=$NEW" >> "$GP"; fi\n'
  printf 'fi\n'
  printf 'echo '\''portrait_sdl_pointer_packages=%s'\'' >> "$GP"\n' "$SDL_PTR"
  printf 'chmod 0664 "$GP" 2>/dev/null || true\n'
fi
