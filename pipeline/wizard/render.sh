#!/usr/bin/env bash
# Regenerate # BEGIN GENERATED … # END GENERATED regions in wizard/device/*.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MANIFEST="$ROOT/pipeline/deploy/manifest.json"
HOME_KEYS="$ROOT/launcher-overlay/home-keys.json"
DEVICE_PATHS="$ROOT/pipeline/wizard/device-paths.json"
INSTALL="$ROOT/wizard/device/install.sh"
VERIFY="$ROOT/wizard/device/verify.sh"
WP_ASSET="$ROOT/pipeline/wallpaper/assets/flip2-wallpaper.png"

command -v jq >/dev/null || { echo "jq not found" >&2; exit 1; }

# The verifier compares the live wallpaper file against this hash instead of
# against incoming/, which cleanup removes. Baked in at render time so a phone
# can be checked at any point after install. The asset is a tracked source file
# (docs/WALLPAPER.md), so a missing one is a broken tree, not a runtime state —
# fail here rather than emit a check that can never decide anything.
[ -f "$WP_ASSET" ] || { echo "missing wallpaper asset: $WP_ASSET" >&2; exit 1; }
WP_MD5="$(md5sum "$WP_ASSET" | cut -d' ' -f1)"
[ -n "$WP_MD5" ] || { echo "could not hash $WP_ASSET" >&2; exit 1; }

# On-device paths come from device-paths.json: the browser bundle
# (pages/js/device-paths.js) and these scripts must never disagree.
dp() {
  local v
  v="$(jq -r --arg k "$1" '.[$k] // empty' "$DEVICE_PATHS")"
  [ -n "$v" ] || { echo "device-paths.json: missing $1" >&2; exit 1; }
  echo "$v"
}

# Path constants. Each script declares only the paths it uses, so a renamed
# path cannot survive in an unused variable. Values come from device-paths.json.
gen_paths_common() {
  cat <<EOF
# --- on-device paths (generated from pipeline/wizard/device-paths.json) ------
PROFILE=$(dp profileList)
WP_DEV=$(dp wallpaperDevice)
EOF
}

# install.sh additionally needs incoming/ and the ingest paths. adbd's shell
# user cannot create files under the stage root (SELinux: system_data_file)
# even at mode 0777, so the page stages into a shell-writable dir and root
# installs from it. verify.sh declares no IN: the wallpaper check uses the md5
# of the default baked in at render time, because cleanup empties incoming/
# before verify runs.
gen_paths_install() {
  gen_paths_common
  cat <<EOF
IN=$(dp incomingDir)
STAGE=$(dp stageRoot)
INSTALL_SH=$(dp installSh)
SHELL_STAGING=$(dp shellStaging)
SHELL_STAGING_INCOMING=$(dp shellStagingIncoming)
SHELL_STAGING_PROFILE_LIST=$(dp shellStagingProfileList)
SHELL_STAGING_INSTALL_SH=$(dp shellStagingInstallSh)
EOF
}

# Root-side ingest of the browser's staging area. adbd's shell user cannot
# create files under $STAGE (SELinux: system_data_file) even at mode 0777, so
# the page pushes into the shell-writable staging dir and this already-root
# script installs them with install -m (chmod is denied on these paths too).
gen_ingest() {
  cat <<'ING'
# --- ingest the browser's staging area --------------------------------------
# The page pushes into $SHELL_STAGING because adbd's shell user cannot create
# files under $STAGE. Nothing to ingest means the Companion pushed directly.
# The directory is consumed, not copied: a browser attempt that failed and
# left files behind must not overlay a later Companion push. The sum is only
# reported when something was actually ingested — a leftover verify.sh leaves
# the directory present with nothing to consume, and "ingested 0" reads like a
# failure on a Companion run that pushed straight into incoming/.
if [ -d "$SHELL_STAGING" ]; then
  n=0
  if [ -d "$SHELL_STAGING_INCOMING" ]; then
    mkdir -p "$IN"
    for f in "$SHELL_STAGING_INCOMING"/*; do
      [ -e "$f" ] || continue
      install -m 644 "$f" "$IN/$(basename "$f")" || fail "could not ingest $(basename "$f")"
      rm -f "$f"
      n=$((n + 1))
    done
  fi
  if [ -f "$SHELL_STAGING_PROFILE_LIST" ]; then
    install -m 644 "$SHELL_STAGING_PROFILE_LIST" "$PROFILE" \
      || fail "could not ingest profile.list"
    rm -f "$SHELL_STAGING_PROFILE_LIST"
    n=$((n + 1))
  fi
  if [ -f "$SHELL_STAGING_INSTALL_SH" ] && [ "$SHELL_STAGING_INSTALL_SH" != "$INSTALL_SH" ]; then
    install -m 755 "$SHELL_STAGING_INSTALL_SH" "$INSTALL_SH" \
      || fail "could not ingest install.sh"
    rm -f "$SHELL_STAGING_INSTALL_SH"
    n=$((n + 1))
  fi
  [ "$n" -gt 0 ] && ok "ingested $n staged file(s)"
fi
ING
}

wizard_incoming() {
  case "$1" in
    forkgram) echo forkgram.apk ;;
    materialfiles) echo materialfiles.apk ;;
    launcher4) echo launcher4.apk ;;
    ime) echo nullkeyboard.apk ;;
    intertune) echo intertune.apk ;;
    bouncy) echo bouncy.apk ;;
    astro_loop) echo astro-loop.apk ;;
    *) jq -r --arg n "$1" '.components[] | select(.name==$n) | .incoming // empty' "$MANIFEST" ;;
  esac
}

# Replace the lines between "# BEGIN GENERATED[ <tag>]" and "# END GENERATED[ <tag>]".
# The tag lets one script carry two regions: the main generated body and the
# PATHS block, which must sit above the code that uses those paths.
patch_between_markers() {
  local file="$1" blockfile="$2" tag="${3:-}"
  local out begin end
  out="$(mktemp)"
  begin="# BEGIN GENERATED${tag:+ $tag}"
  end="# END GENERATED${tag:+ $tag}"
  # A missing marker is a hard error: silently writing nothing would leave the
  # script with stale or undeclared path constants.
  if ! awk -v bf="$blockfile" -v begin="$begin" -v end="$end" '
    BEGIN {
      while ((getline line < bf) > 0) block = block line "\n"
      close(bf)
      inblock=0
      found=0
    }
    $0 == begin { print; printf "%s", block; inblock=1; found=1; next }
    $0 == end { inblock=0; print; next }
    !inblock { print }
    END { exit(found ? 0 : 1) }
  ' "$file" > "$out"; then
    rm -f "$out"
    echo "$file: missing marker: $begin" >&2
    exit 1
  fi
  mv "$out" "$file"
}

# Each CALL is wrapped in `if want <id>`. want() lives outside the markers.
# place_module() and install_apk() stay defined even when a call is skipped.
# Tier "managed" (Headwind) is not emitted. That block is hand-written after
# END GENERATED so a base rebuild does not need the APK.
gen_install() {
  cat <<'HDR'
place_module() {
  mid=$1; zip=$2
  [ -f "$IN/$zip" ] || fail "module zip missing: $IN/$zip"
  T=/data/adb/modules/$mid
  mkdir -p "$T"
  # Re-placing a module undoes a previous disable/remove (profile switch).
  rm -f "$T/disable" "$T/remove" 2>/dev/null
  unzip_any "$IN/$zip" "$T" || fail "could not unpack module: $mid"
  ok "module placed: $mid"
}

HDR
  jq -r '
    .components[]
    | select([.tiers[]] | index("full") or index("wizard"))
    | select(.artifact == "magisk-module")
    | [.name, .module_id, (.zip | split("/") | last)] | @tsv
  ' "$MANIFEST" | while IFS=$'\t' read -r name mid zip; do
    [[ -n "$name" && -n "$mid" && -n "$zip" ]] || continue
    printf 'if want %s; then\n' "$name"
    printf '  place_module %-30s %s\n' "$mid" "$zip"
    printf 'else\n'
    printf '  echo "NOTE: skip %s"\n' "$name"
    printf 'fi\n'
  done

  cat <<'TDE'
if want tagdrawer; then
  TD=/data/adb/modules/flip2_pixel_tag_drawer
  if [ -d "$TD" ]; then
    rm -f "$TD/disable" 2>/dev/null
    chmod 755 "$TD/service.sh" 2>/dev/null
    chmod 644 "$TD/module.prop" 2>/dev/null
    chmod 644 "$TD/system/app/PixelTagDrawer/PixelTagDrawer.apk" 2>/dev/null
  fi
fi

TDE

  cat <<'FM'

# --- FlipMouse: Base and Arcade are mutually exclusive ----------------------
# Both modules ship a `mouse` daemon whose supervisor restarts it whenever
# `pidof mouse` is empty, so two enabled modules fight over the same process.
# A profile switch must leave exactly one module enabled and one daemon.
# No profile.list means today's full base install: keep Base, disable Arcade.
FM_BASE=/data/adb/modules/FlipMouse
FM_ARCADE=/data/adb/modules/FlipMouseArcade
if want flipmouse; then
  FM=$FM_BASE
  FM_OTHER=$FM_ARCADE
  FM_NAME=FlipMouse
elif want flipmouse_arcade; then
  FM=$FM_ARCADE
  FM_OTHER=$FM_BASE
  FM_NAME="FlipMouse Arcade"
else
  FM=
fi
if [ -z "$FM" ]; then
  echo "NOTE: skip flipmouse"
else
  if [ -d "$FM_OTHER" ]; then
    # Magisk honours this flag at boot; the process is killed just below.
    touch "$FM_OTHER/disable" || fail "could not disable $(basename "$FM_OTHER")"
    rm -f "$FM_OTHER/update" 2>/dev/null
    ok "disabled $(basename "$FM_OTHER") — one mouse daemon per phone"
  fi
  # Both supervisors restart `mouse` whenever `pidof mouse` is empty, so kill
  # every straggler (and any stale wanted daemon) before starting the one we
  # want, or the loser of the race keeps the slot.
  pkill -f "$FM_OTHER/service.sh" 2>/dev/null
  pkill -f "$FM_OTHER/mouse" 2>/dev/null
  pkill -f "$FM/mouse" 2>/dev/null
  sleep 1
  # Nothing starts the daemon until Magisk service time — start it now, the
  # way installer/service.sh does.
  [ -x "$FM/mouse" ] || fail "$FM_NAME module has no mouse binary"
  rm -f "$FM/update" "$FM/disable" 2>/dev/null
  chmod 755 "$FM/mouse" "$FM/service.sh" 2>/dev/null
  chmod 644 "$FM/module.prop" 2>/dev/null
  nohup sh "$FM/service.sh" </dev/null >/dev/null 2>&1 &
  ok "$FM_NAME daemon started"
fi

# --- user APKs, manifest 60-80 plus the wizard's own downloads -------------
install_apk() {
  f=$1; pkg=$2
  [ -f "$IN/$f" ] || fail "APK missing: $IN/$f"
  S=$STAGE/$f
  cp "$IN/$f" "$S" && chmod 644 "$S" || fail "could not stage $f"
  pm install -r -d "$S" >/dev/null 2>&1 || { rm -f "$S"; fail "pm install failed: $pkg ($f)"; }
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
    [[ -n "$inc" ]] || continue
    printf 'if want %s; then\n' "$name"
    printf '  install_apk %-22s %s\n' "$inc" "$pkg"
    printf 'else\n'
    printf '  echo "NOTE: skip %s"\n' "$name"
    printf 'fi\n'
  done

  echo ""
  echo "if want ime; then"
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
  echo "else"
  echo '  echo "NOTE: skip ime"'
  echo "fi"
  echo ""
  echo "if want home_keys; then"
  echo "# --- home keys, manifest 90: values mirror launcher-overlay/home-keys.json -"
  echo "# Quoted: & and \$ inside Label-package-component break unquoted args."
  declare -A HKMAP=( [left]=keyshortcut_leftkey [right]=keyshortcut_rightkey [up]=keyshortcut_upkey [down]=keyshortcut_downkey [shortcuts_bar]=keyshortcut_shortcutsbar )
  for k in left right shortcuts_bar up down; do
    v="$(jq -r --arg k "$k" '.[$k] // ""' "$HOME_KEYS")"
    gk="${HKMAP[$k]}"
    printf '%s\n' "settings put global '$gk' '$v' \\" "  || fail \"$gk\""
  done
  echo 'ok "home keys applied"'
  echo "else"
  echo '  echo "NOTE: skip home_keys"'
  echo "fi"
  echo ""
  echo "if want display; then"
  echo "# --- display size, manifest 95: logical 321x428 on the 240x320 panel --------"
  jq -r '.components[] | select(.name=="display") | .settings[]? // empty' "$MANIFEST" | while IFS=' ' read -r ns key val; do
    printf '%s\n' "settings put $ns '$key' '$val' \\" "  || fail \"settings: $key\""
  done
  echo 'ok "display size 321x428 (takes effect after reboot)"'
  echo "else"
  echo '  echo "NOTE: skip display"'
  echo "fi"
  echo ""
  cat <<'WP'
if want wallpaper; then
# --- wallpaper: fill an empty slot, never replace a choice -------------------
# A wallpaper is a user preference, not a build artifact — see
# docs/WALLPAPER.md. Only write when there is nothing there yet; an existing
# file is its owner's (stock or their own image) and an install must leave it
# byte-for-byte alone. `flip2 wallpaper apply` is the deliberate override.
# Every branch here ends in ok or NOTE: a background that could not be written
# is not a broken install, and must never stop the steps after it. The order
# matters too — the idempotent "already the default" case is decided by the
# bytes, not by the stamp, so a re-run reports what is actually on the phone.
WP=$IN/flip2-wallpaper.png
WPDST=$WP_DEV
WPSTAMP=$STAGE/.wallpaper-applied
if [ ! -f "$WP" ]; then
  echo "NOTE: no flip2-wallpaper.png in this push; keeping the current wallpaper"
elif cmp -s "$WP" "$WPDST"; then
  touch "$WPSTAMP"
  ok "wallpaper is already the flip2 default"
elif [ -f "$WPSTAMP" ]; then
  echo "NOTE: wallpaper set by an earlier run; keeping whatever this phone has now"
elif [ -f "$WPDST" ]; then
  echo "NOTE: keeping this phone's own wallpaper; run 'flip2 wallpaper apply' for the default"
elif cp "$WP" "$WPDST"; then
  chown system:system "$WPDST" 2>/dev/null
  chmod 600 "$WPDST"
  restorecon "$WPDST" 2>/dev/null
  touch "$WPSTAMP"
  ok "wallpaper installed (shows after reboot)"
else
  echo "NOTE: could not set the default wallpaper; install unaffected — run 'flip2 wallpaper apply' later"
fi
else
  echo "NOTE: skip wallpaper"
fi

if want launcher4; then
cmd package set-home-activity $HOME_ACT >/dev/null 2>&1 \
  || fail "could not set HOME to launcher4"
ok "HOME set to launcher4"
else
  echo "NOTE: skip launcher4"
fi
WP
}

gen_verify() {
  echo "# --- Apps installed (manifest full|wizard user-apk labels) ----------------"
  jq -r '
    .components[]
    | select([.tiers[]] | index("full") or index("wizard"))
    | select(.artifact == "user-apk" and (.label // "") != "" and (.package // "") != "")
    | [.name, .label, .package, (.install_order // 999)] | @tsv
  ' "$MANIFEST" | sort -t$'\t' -k4 -n | while IFS=$'\t' read -r name label pkg _ord; do
    [[ -n "$name" && -n "$pkg" ]] || continue
    printf 'if want %s; then\n' "$name"
    printf '  check "%s installed" pm path %s\n' "$label" "$pkg"
    printf 'else\n'
    printf '  echo "NOTE: skip %s"\n' "$name"
    printf 'fi\n'
  done
  cat <<'TD'
if want tagdrawer; then
  tagdrawer_ok=0
  if pm path com.iwadjp.pixeltagdrawer >/dev/null 2>&1; then
    tagdrawer_ok=1
  elif pm list packages com.iwadjp.pixeltagdrawer 2>/dev/null | grep -q com.iwadjp.pixeltagdrawer; then
    tagdrawer_ok=1
  elif [ -f /system/app/PixelTagDrawer/PixelTagDrawer.apk ]; then
    tagdrawer_ok=1
  elif [ -f /data/adb/modules/flip2_pixel_tag_drawer/system/app/PixelTagDrawer/PixelTagDrawer.apk ]; then
    tagdrawer_ok=1
  fi
  if [ "$tagdrawer_ok" -eq 1 ]; then
    echo "PASS: Tag Drawer installed"
    PASS=$((PASS + 1))
  else
    echo "FAIL: Tag Drawer installed (place flip2_pixel_tag_drawer module and reboot)"
    FAILS=$((FAILS + 1))
  fi
else
  echo "NOTE: skip tagdrawer"
fi
TD
  echo ""
  echo "if want home_keys; then"
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
  echo "else"
  echo '  echo "NOTE: skip home_keys"'
  echo "fi"
  echo ""
  disp="$(jq -r '.components[] | select(.name=="display") | .settings[]? // empty' "$MANIFEST" | awk '{print $3}')"
  echo "if want display; then"
  echo "# --- Display size (logical 321x428 on the 240x320 panel) ----------------------"
  echo "SIZE=\$(settings get global display_size_forced 2>/dev/null)"
  echo "if [ \"\$SIZE\" = \"$disp\" ]; then"
  echo "  echo \"PASS: display_size_forced=$disp\""
  echo '  PASS=$((PASS + 1))'
  echo "else"
  echo "  echo \"FAIL: display_size_forced is '\$SIZE' (expected $disp)\""
  echo '  FAILS=$((FAILS + 1))'
  echo 'fi'
  echo "else"
  echo '  echo "NOTE: skip display"'
  echo "fi"
  echo ""
  # Wallpaper: install.sh only fills an empty slot, so a phone showing its own
  # background is the correct end state, not a defect. PASS when the live file
  # is the flip2 default (hash baked in at render time, so incoming/ — which
  # cleanup removes — is not needed); NOTE for anything else, never FAIL.
  echo "if want wallpaper; then"
  echo "# --- Wallpaper: a preference, so a mismatch is a NOTE, never a FAIL ----------"
  echo "# See docs/WALLPAPER.md: install.sh fills an empty slot and leaves an existing"
  echo "# file alone, so 'differs from the default' is the expected result for anyone"
  echo "# who chose their own image. 'flip2 wallpaper apply' is the deliberate override."
  echo "WP_DEFAULT_MD5=$WP_MD5"
  echo 'if [ ! -f "$WP_DEV" ]; then'
  echo '  echo "NOTE: no wallpaper file yet (install fills an empty slot; a reboot may be pending)"'
  echo "else"
  echo "  WP_NOW=\$(md5sum \"\$WP_DEV\" 2>/dev/null | cut -d' ' -f1)"
  echo '  if [ "$WP_NOW" = "$WP_DEFAULT_MD5" ]; then'
  echo '    echo "PASS: wallpaper is the flip2 default"'
  echo '    PASS=$((PASS + 1))'
  echo "  else"
  echo '    echo "NOTE: this phone has its own wallpaper — fine (flip2 wallpaper apply restores the default)"'
  echo "  fi"
  echo "fi"
  echo "else"
  echo '  echo "NOTE: skip wallpaper"'
  echo "fi"
}

# The script carries three regions: PATHS (used by everything below), INGEST
# (must run before the incoming check and before any module is placed) and the
# untagged body. Writing the wrong region would silently duplicate constants.
render_install() {
  block="$(mktemp)"
  gen_paths_install > "$block"
  patch_between_markers "$INSTALL" "$block" PATHS
  gen_ingest > "$block"
  patch_between_markers "$INSTALL" "$block" INGEST
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
  gen_paths_common > "$block"
  patch_between_markers "$VERIFY" "$block" PATHS
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
