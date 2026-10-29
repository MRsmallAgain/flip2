#!/usr/bin/env bash
# Tier A: assemble dist/flip2-system-tree/ — the flip2 components that can be
# baked into a stock image, laid out as a system/product merge tree:
#
#   system/app/PixelTagDrawer/PixelTagDrawer.apk   (D-pad Up tags)
#   system/app/Launcher4/Launcher4.apk             (preloaded default HOME)
#   system/app/Flip2NullKeyboard/...apk            (preloaded IME)
#   system/usr/keylayout/matrix-keypad.kl          (backspace remap)
#   product/overlay/Flip2NavOverlay.apk            (nav bar hide overlay)
#   product/overlay/Flip2LauncherOverlay.apk       (stock Launcher3 RRO)
#   system/media/flip2-wallpaper.png               (default wallpaper asset)
#   first-boot.sh                                  (settings + /data writes)
#
# A merge tree can only carry files, so the settings-write components
# (home_keys, display) and the wallpaper's /data copy cannot be baked as
# settings. They are emitted as first-boot.sh, run once as root after Magisk
# is installed — see docs/IMAGE-BUILD.md step 6.
#
# Only components whose manifest tiers include "image" are included. The
# output tree is meant to be merged into the system/product partitions of the
# user's own stock firmware and flashed via fastbootd — see docs/IMAGE-BUILD.md.
# FlipMouse is NOT image-bakeable (it needs runtime root to read /dev/input)
# and Forkgram is never bundled (GPL) — both stay in Tier B.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/lib/bootstrap.sh"
flip2_env_init

MANIFEST="$ROOT/pipeline/deploy/manifest.json"
DIST="$ROOT/pipeline/deploy/dist"

usage() {
  cat <<EOF
Usage: flip2 image build-tree [--out DIR]

Assemble the Tier A system/product merge tree at
  $DIST/flip2-system-tree/
from the components whose manifest tiers include "image". Nothing is
pushed or flashed; the tree is merged into your own stock firmware dump
before a fastbootd flash (docs/IMAGE-BUILD.md).
EOF
}

OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT="${2:-}"; [ -n "$OUT" ] || { echo "--out needs a path" >&2; exit 1; }; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done
command -v jq >/dev/null || { echo "jq not found" >&2; exit 1; }

VERSION="$(jq -r '.version // "dev"' "$MANIFEST")"
[[ -n "$OUT" ]] || OUT="$DIST/flip2-system-tree"

log() { echo "==> $*"; }
MISSING=()

rm -rf "$OUT"
mkdir -p "$OUT"

# --- component trees --------------------------------------------------------
# Magisk modules that are plain file placements map 1:1 into the image tree.
# Their magisk-module/system|product trees are copied verbatim; user APKs are
# preloaded as /system/app/<Name>/<Name>.apk (Android requires that layout).

# navoverlay + launcher_overlay: product/overlay RRO APKs.
# The navoverlay module tree nests under system/product/overlay (it doubles as
# a Magisk replacement); the launcher overlay module has product/overlay.
for comp in navoverlay launcher_overlay; do
  src=""
  case "$comp" in
    navoverlay)      src="$ROOT/framework-nav-overlay/magisk-module" ;;
    launcher_overlay) src="$ROOT/launcher-overlay/magisk-module" ;;
  esac
  ovdir=""
  for cand in "$src/product/overlay" "$src/system/product/overlay"; do
    [[ -d "$cand" ]] && { ovdir="$cand"; break; }
  done
  if [[ -n "$ovdir" ]]; then
    log "overlay: $comp"
    mkdir -p "$OUT/product/overlay"
    cp -a "$ovdir/." "$OUT/product/overlay/"
  else
    MISSING+=("$comp product/overlay tree")
  fi
done

# keypad: system/usr/keylayout/matrix-keypad.kl
if [[ -f "$ROOT/keypad-backspace/magisk-module/system/usr/keylayout/matrix-keypad.kl" ]]; then
  log "keylayout: keypad-backspace"
  mkdir -p "$OUT/system/usr/keylayout"
  cp -a "$ROOT/keypad-backspace/magisk-module/system/usr/keylayout/." "$OUT/system/usr/keylayout/"
else
  MISSING+=("keypad matrix-keypad.kl")
fi

# tagdrawer: system/app/PixelTagDrawer (verbatim from the module tree)
if [[ -d "$ROOT/pixel-tag-drawer/magisk-module/system/app/PixelTagDrawer" ]]; then
  log "system app: PixelTagDrawer"
  mkdir -p "$OUT/system/app"
  cp -a "$ROOT/pixel-tag-drawer/magisk-module/system/app/." "$OUT/system/app/"
else
  MISSING+=("tagdrawer PixelTagDrawer module tree")
fi

# Preloaded user APKs (launcher4, ime) as system/app — must NOT be priv-app
# (they are debug-signed; priv-app requires platform signature).
preload_apk() {
  local apk="$1" name="$2"
  if [[ -f "$ROOT/$apk" ]]; then
    log "system app: $name"
    mkdir -p "$OUT/system/app/$name"
    cp "$ROOT/$apk" "$OUT/system/app/$name/$name.apk"
  else
    MISSING+=("$apk (build it first)")
  fi
}
preload_apk "launcher4/dist/launcher4.apk" "Launcher4"
preload_apk "pipeline/ime/null-keyboard/dist/nullkeyboard.apk" "Flip2NullKeyboard"

# wallpaper: the default asset rides in system/media so the phone can copy it
# into /data at first boot (the tree cannot write there itself).
WP_ASSET="$ROOT/pipeline/wallpaper/assets/flip2-wallpaper.png"
if [[ -f "$WP_ASSET" ]]; then
  log "asset: flip2-wallpaper.png"
  mkdir -p "$OUT/system/media"
  cp "$WP_ASSET" "$OUT/system/media/flip2-wallpaper.png"
else
  MISSING+=("pipeline/wallpaper/assets/flip2-wallpaper.png (run: flip2 wallpaper gen)")
fi

if [ "${#MISSING[@]}" -gt 0 ]; then
  echo "Missing artifacts (build them first):" >&2
  printf ' - %s\n' "${MISSING[@]}" >&2
  exit 1
fi

# --- first-boot.sh ----------------------------------------------------------
# The one thing a merge tree cannot do is run a command. The image-tier
# settings-write components (home_keys, display) and the wallpaper's copy into
# /data are emitted here as a script to run once as root after Magisk is up.
# Values are expanded host-side so the device sh needs no jq.
log "first-boot.sh (settings + wallpaper)"
{
  cat <<'FB_HEAD'
#!/system/bin/sh
# flip2 first-boot.sh — generated by pipeline/image/build-tree.sh.
#
# Run ONCE as root after flashing the image and completing Magisk:
#   adb push first-boot.sh /data/local/tmp/
#   adb shell su -c "sh /data/local/tmp/first-boot.sh"
#
# A system/product merge tree can only carry files, so the settings this image
# needs are applied here instead of being baked. Both are plain Settings writes
# that Android re-reads at boot, so nothing has to run again afterwards.
FB_HEAD
	  echo ""
	  "$ROOT/pipeline/deploy/emit-first-boot.sh"
  cat <<'FB_TAIL'

# --- default wallpaper ------------------------------------------------------
# This ROM has no `cmd wallpaper`; the framework reads
# /data/system/users/0/wallpaper at boot. Stamp-guarded so a second run never
# replaces a wallpaper the user has since chosen.
# Overridable so the hook can be exercised on a phone that still has the stock image
# (push the asset elsewhere and set FLIP2_WALLPAPER_SRC).
WP_SRC=${FLIP2_WALLPAPER_SRC:-/system/media/flip2-wallpaper.png}
WP_DST=/data/system/users/0/wallpaper
WP_STAMP=/data/local/flip2/.wallpaper-applied
if [ -f "$WP_SRC" ] && [ ! -f "$WP_STAMP" ]; then
  mkdir -p /data/local/flip2
  if cp "$WP_SRC" "$WP_DST"; then
    chown system:system "$WP_DST"
    chmod 600 "$WP_DST"
    restorecon "$WP_DST" 2>/dev/null
    touch "$WP_STAMP"
    echo "wallpaper installed: $WP_DST"
  else
    echo "FAILED: could not write $WP_DST"
  fi
elif [ -f "$WP_STAMP" ]; then
  echo "wallpaper already applied"
else
  echo "no $WP_SRC in this tree; wallpaper skipped"
fi

echo "first-boot done. Reboot to apply the logical display size."
FB_TAIL
} > "$OUT/first-boot.sh"
chmod 755 "$OUT/first-boot.sh"

# --- manifest of contents + checksums ---------------------------------------
# Plain-text record of what went into the tree, for IMAGE-BUILD verification.
{
  echo "flip2 system tree v$VERSION — merge into system/ and product/ of your"
  echo "own stock firmware image. Do NOT flash EMMC_BOOT; back up vbmeta first."
  echo "Docs: docs/IMAGE-BUILD.md"
  echo "Contents:"
  ( cd "$OUT" && find . -type f ! -name MANIFEST.txt ! -name SHA256SUMS | sed 's|^\./||' | sort | sed 's/^/  /' )
} > "$OUT/MANIFEST.txt"

( cd "$OUT" && find . -type f ! -name SHA256SUMS | sed 's|^\./||' | sort | xargs sha256sum ) > "$OUT/SHA256SUMS"

log "built $OUT"
echo "    Merge into your stock firmware system/product partitions, then flash"
echo "    with fastbootd (docs/IMAGE-BUILD.md). FlipMouse and Forkgram are NOT"
echo "    image-bakeable — run the Tier B full installer after first boot."
