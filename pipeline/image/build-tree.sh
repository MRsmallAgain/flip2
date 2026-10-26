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

if [ "${#MISSING[@]}" -gt 0 ]; then
  echo "Missing artifacts (build them first):" >&2
  printf ' - %s\n' "${MISSING[@]}" >&2
  exit 1
fi

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
