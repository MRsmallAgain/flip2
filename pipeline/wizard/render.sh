#!/usr/bin/env bash
# Regenerate # BEGIN GENERATED … # END GENERATED regions in wizard/device/*.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MANIFEST="$ROOT/pipeline/deploy/manifest.json"
HOME_KEYS="$ROOT/launcher-overlay/home-keys.json"
INSTALL="$ROOT/wizard/device/install.sh"
VERIFY="$ROOT/wizard/device/verify.sh"

command -v jq >/dev/null || { echo "jq not found" >&2; exit 1; }

wizard_incoming() {
  case "$1" in
    forkgram) echo forkgram.apk ;;
    materialfiles) echo materialfiles.apk ;;
    launcher4) echo launcher4.apk ;;
    ime) echo nullkeyboard.apk ;;
    intertune) echo intertune.apk ;;
    bouncy) echo bouncy.apk ;;
    *) jq -r --arg n "$1" '.components[] | select(.name==$n) | .incoming // empty' "$MANIFEST" ;;
  esac
}

patch_between_markers() {
  local file="$1" blockfile="$2"
  local out
  out="$(mktemp)"
  awk -v bf="$blockfile" '
    BEGIN {
      while ((getline line < bf) > 0) block = block line "\n"
      close(bf)
      inblock=0
    }
    /# BEGIN GENERATED/ {
      print "# BEGIN GENERATED"
      printf "%s", block
      inblock=1
      next
    }
    /# END GENERATED/ { inblock=0; print "# END GENERATED"; next }
    !inblock { print }
  ' "$file" > "$out"
  mv "$out" "$file"
}

gen_install() {
  cat <<'HDR'
place_module() {
  mid=$1; zip=$2
  [ -f "$IN/$zip" ] || fail "module zip missing: $IN/$zip"
  T=/data/adb/modules/$mid
  mkdir -p "$T"
  unzip_any "$IN/$zip" "$T" || fail "could not unpack module: $mid"
  ok "module placed: $mid"
}

HDR
  jq -r '
    .components[]
    | select([.tiers[]] | index("full") or index("wizard"))
    | select(.artifact == "magisk-module")
    | [.module_id, (.zip | split("/") | last)] | @tsv
  ' "$MANIFEST" | while IFS=$'\t' read -r mid zip; do
    [[ -n "$mid" ]] && printf 'place_module %-30s %s\n' "$mid" "$zip"
  done

  cat <<'FM'

# Nothing starts FlipMouse's daemon until Magisk service time — start it now,
# the way installer/service.sh does.
FM=/data/adb/modules/FlipMouse
[ -x "$FM/mouse" ] || fail "FlipMouse module has no mouse binary"
rm -f "$FM/update"
chmod 755 "$FM/mouse" "$FM/service.sh" 2>/dev/null
chmod 644 "$FM/module.prop" 2>/dev/null
nohup sh "$FM/service.sh" </dev/null >/dev/null 2>&1 &
ok "FlipMouse daemon started"

# --- user APKs, manifest 60-80 plus the wizard's own downloads -------------
install_apk() {
  f=$1; pkg=$2
  [ -f "$IN/$f" ] || fail "APK missing: $IN/$f"
  S=$STAGE/$f
  cp "$IN/$f" "$S" && chmod 644 "$S" || fail "could not stage $f"
  pm install -r "$S" >/dev/null 2>&1 || { rm -f "$S"; fail "pm install failed: $pkg ($f)"; }
  rm -f "$S"
  ok "installed: $pkg"
}

FM
  jq -r '
    .components[]
    | select([.tiers[]] | index("full") or index("wizard"))
    | select(.artifact == "user-apk" and (.incoming // "") != "")
    | [.name, .package, (.install_order // 999)] | @tsv
  ' "$MANIFEST" | sort -t$'\t' -k3 -n | while IFS=$'\t' read -r name pkg _ord; do
    [[ -n "$name" && -n "$pkg" ]] || continue
    inc="$(wizard_incoming "$name")"
    [[ -n "$inc" ]] && printf 'install_apk %-22s %s\n' "$inc" "$pkg"
  done

  echo ""
  echo "# --- IME settings (manifest 70): values mirror payload data/settings.txt ---"
  jq -r '.components[] | select(.name=="ime") | .settings[]? // empty' "$MANIFEST" | while IFS=' ' read -r ns key val; do
    if [[ "$key" == "enabled_input_methods" || "$key" == "default_input_method" ]]; then
      printf '%s\n' "settings put $ns $key \"\$NULL_IME\" \\" "  || fail \"settings: $key\""
    else
      printf '%s\n' "settings put $ns $key '$val' \\" "  || fail \"settings: $key\""
    fi
  done
  echo "appops set --user 0 \$NULL_PKG WRITE_SETTINGS allow \\"
  echo "  || fail \"appops: WRITE_SETTINGS for \$NULL_PKG\""
  echo "pm grant \$NULL_PKG android.permission.RECORD_AUDIO \\"
  echo "  || fail \"pm grant: RECORD_AUDIO for \$NULL_PKG\""
  echo 'ok "IME settings applied"'
  echo ""
  echo "# --- home keys, manifest 90: values mirror launcher-overlay/home-keys.json -"
  echo "# Quoted: & and \$ inside Label-package-component break unquoted args."
  declare -A HKMAP=( [left]=keyshortcut_leftkey [right]=keyshortcut_rightkey [up]=keyshortcut_upkey [down]=keyshortcut_downkey [shortcuts_bar]=keyshortcut_shortcutsbar )
  for k in left right shortcuts_bar up down; do
    v="$(jq -r --arg k "$k" '.[$k] // ""' "$HOME_KEYS")"
    gk="${HKMAP[$k]}"
    printf '%s\n' "settings put global '$gk' '$v' \\" "  || fail \"$gk\""
  done
  echo 'ok "home keys applied"'
  echo ""
  echo "# --- display size, manifest 95: logical 321x428 on the 240x320 panel --------"
  jq -r '.components[] | select(.name=="display") | .settings[]? // empty' "$MANIFEST" | while IFS=' ' read -r ns key val; do
    printf '%s\n' "settings put $ns '$key' '$val' \\" "  || fail \"settings: $key\""
  done
  echo 'ok "display size 321x428 (takes effect after reboot)"'
  echo ""
  cat <<'WP'
# --- wallpaper: default background, copied where the framework reads it -----
WP=/data/local/flip2/incoming/flip2-wallpaper.png
WPDST=/data/system/users/0/wallpaper
if [ -f "$WP" ] && [ ! -f "$STAGE/.wallpaper-applied" ]; then
  cp "$WP" "$WPDST" || fail "wallpaper copy"
  chown system:system "$WPDST" 2>/dev/null
  chmod 600 "$WPDST"
  restorecon "$WPDST" 2>/dev/null
  touch "$STAGE/.wallpaper-applied"
  ok "wallpaper installed (shows after reboot)"
else
  echo "NOTE: no flip2-wallpaper.png in incoming/; keeping the current wallpaper"
fi

cmd package set-home-activity $HOME_ACT >/dev/null 2>&1 \
  || fail "could not set HOME to launcher4"
ok "HOME set to launcher4"
WP
}

gen_verify() {
  echo "# --- Apps installed (manifest full|wizard user-apk labels) ----------------"
  echo "for entry in \\"
  {
    jq -r '
      .components[]
      | select([.tiers[]] | index("full") or index("wizard"))
      | select(.artifact == "user-apk" and (.label // "") != "" and (.package // "") != "")
      | "\(.label) \(.package)"
    ' "$MANIFEST"
    echo "Tag Drawer com.iwadjp.pixeltagdrawer"
  } | while read -r line; do
    printf "  '%s' \\\n" "$line"
  done
  echo "  ; do"
  echo "  pkg=\${entry##* }; label=\${entry% *}"
  echo '  check "$label installed" pm path "$pkg"'
  echo "done"
  echo ""
  echo "# --- The five keyshortcuts match home-keys.json -------------------------------"
  echo "expect_leftkey='$(jq -r '.left' "$HOME_KEYS")'"
  echo "expect_rightkey='$(jq -r '.right' "$HOME_KEYS")'"
  echo "expect_shortcutsbar='$(jq -r '.shortcuts_bar' "$HOME_KEYS")'"
  echo "expect_upkey='$(jq -r '.up' "$HOME_KEYS")'"
  echo "expect_downkey='$(jq -r '.down' "$HOME_KEYS")'"
  echo "for entry in \\"
  echo '  "leftkey $expect_leftkey" \'
  echo '  "rightkey $expect_rightkey" \'
  echo '  "shortcutsbar $expect_shortcutsbar" \'
  echo '  "upkey $expect_upkey" \'
  echo '  "downkey $expect_downkey"; do'
  echo '  name=${entry%% *}; expect=${entry#* }'
  echo '  got=$(settings get global "keyshortcut_$name" 2>/dev/null)'
  echo '  if [ "$got" = "$expect" ]; then'
  echo '    echo "PASS: keyshortcut_$name"'
  echo '    PASS=$((PASS + 1))'
  echo '  else'
  echo '    echo "FAIL: keyshortcut_$name is '\''$got'\''"'
  echo '    FAILS=$((FAILS + 1))'
  echo '  fi'
  echo "done"
  echo ""
  disp="$(jq -r '.components[] | select(.name=="display") | .settings[]? // empty' "$MANIFEST" | awk '{print $3}')"
  echo "# --- Display size (logical 321x428 on the 240x320 panel) ----------------------"
  echo "SIZE=\$(settings get global display_size_forced 2>/dev/null)"
  echo "if [ \"\$SIZE\" = \"$disp\" ]; then"
  echo "  echo \"PASS: display_size_forced=$disp\""
  echo '  PASS=$((PASS + 1))'
  echo "else"
  echo "  echo \"FAIL: display_size_forced is '\$SIZE' (expected $disp)\""
  echo '  FAILS=$((FAILS + 1))'
  echo 'fi'
}

render_install() {
  block="$(mktemp)"
  gen_install > "$block"
  patch_between_markers "$INSTALL" "$block"
  rm -f "$block"
  echo "rendered: $INSTALL"
}

render_verify() {
  if ! grep -q '# BEGIN GENERATED' "$VERIFY"; then
    echo "verify.sh has no GENERATED markers" >&2
    exit 1
  fi
  block="$(mktemp)"
  gen_verify > "$block"
  patch_between_markers "$VERIFY" "$block"
  rm -f "$block"
  echo "rendered: $VERIFY"
}

case "${1:-all}" in
  install) render_install ;;
  verify) render_verify ;;
  all)
    render_install
    render_verify
    ;;
  *) echo "Usage: render.sh [install|verify|all]" >&2; exit 1 ;;
esac
