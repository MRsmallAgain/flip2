#!/usr/bin/env bash
# One-shot host pipeline: build everything that can be baked into super, plus
# the post-flash artifacts (first-boot, image-post zip, optional Sherpa URLs).
# Optional --stock-super merges a built super-flip2.img into the kit. Does not flash.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/lib/bootstrap.sh"
flip2_env_init

MANIFEST="$ROOT/pipeline/deploy/manifest.json"
DIST="$ROOT/pipeline/deploy/dist"
KIT="$DIST/flip2-image-kit"

usage() {
  cat <<EOF
Usage: flip2 image prepare [--skip-flipmouse-system] [--with-sherpa-urls] [--kit DIR]
       [--stock-super PATH] [--skip-avb-on-merge]

  1. flip2 deploy source-fetch     (F-Droid pins for image_preload APKs)
  2. flip2 wallpaper gen         (if asset missing)
  3. flip2 launcher4 build + flip2 ime build
  4. Optional: flip2 flipmouse build-system (unless --skip-flipmouse-system)
  5. flip2 image build-tree        -> dist/flip2-system-tree/
  6. flip2 installer pack --flavor image-post [--sherpa-url ...]
  7. Copy tree + first-boot + zip (+ IMAGE-FLASH-STEPS.txt) into --kit

Output:
  dist/flip2-system-tree/          merge into your stock system/product
  dist/flip2-installer-image-post-magisk.zip
  dist/flip2-image-kit/            (default) portable bundle for flash day
  dist/super-flip2.img             (when --stock-super PATH is set)

Cannot bake (post-flash only):
  Forkgram, Material Files (GPL / external download -> image-post zip)
  Sherpa STT models (large; --with-sherpa-urls bakes URLs into image-post)
  neutron.img boot (separate fastboot flash)

Docs: docs/IMAGE-BUILD.md, docs/IMAGE-TIERS.md
EOF
}

SKIP_FM=0
WITH_SHERPA=0
KIT_OUT=""
STOCK_SUPER=""
SKIP_AVB_MERGE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --skip-flipmouse-system) SKIP_FM=1; shift ;;
    --with-sherpa-urls) WITH_SHERPA=1; shift ;;
    --kit) KIT_OUT="${2:-}"; [ -n "$KIT_OUT" ] || { echo "--kit needs a path" >&2; exit 1; }; shift 2 ;;
    --stock-super) STOCK_SUPER="${2:-}"; [ -n "$STOCK_SUPER" ] || { echo "--stock-super needs a path" >&2; exit 1; }; shift 2 ;;
    --skip-avb-on-merge) SKIP_AVB_MERGE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done
[[ -n "$KIT_OUT" ]] || KIT_OUT="$KIT"

log() { echo "==> $*"; }

export JAVA_HOME="${JAVA_HOME:-$HOME/.local/opt/jdk17}"
export PATH="$JAVA_HOME/bin:$ROOT/bin:$PATH"

log "source fetch (image_preload APKs)"
"$ROOT/bin/flip2" source fetch

if [[ ! -f "$ROOT/pipeline/wallpaper/assets/flip2-wallpaper.png" ]]; then
  log "wallpaper gen"
  "$ROOT/bin/flip2" wallpaper gen
fi

log "launcher4 + null keyboard build"
"$ROOT/bin/flip2" launcher4 build
if [[ ! -f "$ROOT/pipeline/ime/null-keyboard/vendor/jars/sherpa-onnx-classes.jar" ]]; then
  log "fetch-sherpa (vendor)"
  bash "$ROOT/pipeline/ime/null-keyboard/vendor/fetch-sherpa.sh"
fi
"$ROOT/bin/flip2" ime build

if [[ "$SKIP_FM" -eq 0 ]]; then
  if command -v ndk-build >/dev/null 2>&1 || [[ -n "${ANDROID_NDK_HOME:-}" ]]; then
    log "flipmouse build-system (optional)"
    if "$ROOT/bin/flip2" flipmouse build-system 2>/dev/null; then
      :
    else
      echo "NOTE: flipmouse build-system failed or incomplete; tree may omit system init mouse" >&2
    fi
  else
    echo "NOTE: no NDK — skip flipmouse build-system (Magisk FlipMouse still in full installer)" >&2
  fi
fi

log "image build-tree"
"$ROOT/pipeline/image/build-tree.sh"

BUILT_SUPER=""
if [[ -n "$STOCK_SUPER" ]]; then
  MERGE_ARGS=(--stock-super "$STOCK_SUPER" --tree "$DIST/flip2-system-tree" --out "$DIST/super-flip2.img")
  [[ "$SKIP_AVB_MERGE" -eq 1 ]] && MERGE_ARGS+=(--skip-avb)
  log "image merge-super"
  "$ROOT/pipeline/image/merge-super.sh" "${MERGE_ARGS[@]}"
  BUILT_SUPER="$DIST/super-flip2.img"
fi

PACK_ARGS=(--flavor image-post)
if [[ "$WITH_SHERPA" -eq 1 ]]; then
  BASE="https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models"
  PACK_ARGS+=(--sherpa-url "en=$BASE/sherpa-onnx-streaming-zipformer-en-20M-2023-02-17-mobile.tar.bz2")
  PACK_ARGS+=(--sherpa-url "uk=$BASE/sherpa-onnx-nemo-fast-conformer-transducer-be-de-en-es-fr-hr-it-pl-ru-uk-20k-int8.tar.bz2")
fi
log "installer pack image-post"
"$ROOT/pipeline/deploy/pack-installer.sh" "${PACK_ARGS[@]}"

rm -rf "$KIT_OUT"
mkdir -p "$KIT_OUT"
log "image kit -> $KIT_OUT"
cp -a "$DIST/flip2-system-tree" "$KIT_OUT/"
cp "$DIST/flip2-installer-image-post-magisk.zip" "$KIT_OUT/"
if [[ -n "$BUILT_SUPER" && -f "$BUILT_SUPER" ]]; then
  cp "$BUILT_SUPER" "$KIT_OUT/super-flip2.img"
  [[ -f "$BUILT_SUPER.sha256" ]] && cp "$BUILT_SUPER.sha256" "$KIT_OUT/"
fi

VERSION="$(jq -r '.version // "dev"' "$MANIFEST")"
if [[ -n "$BUILT_SUPER" && -f "$BUILT_SUPER" ]]; then
  cat > "$KIT_OUT/IMAGE-FLASH-STEPS.txt" <<STEPS
flip2 image kit v$VERSION — includes super-flip2.img (merged from your stock super).

1. fastbootd: flash boot (neutron.img) + super-flip2.img from this kit. Never flash EMMC_BOOT.
   Orange/unlocked: you may need a matching vbmeta_system — see docs/IMAGE-BUILD.md.
2. Magisk dial *#*#217703#*#*, reboot.
3. adb push flip2-system-tree/first-boot.sh /data/local/tmp/
   adb shell su -c "sh /data/local/tmp/first-boot.sh"
   adb reboot
4. Magisk: install flip2-installer-image-post-magisk.zip from this kit, reboot.
5. Sherpa STT if not in zip: flip2 ime sherpa (or wizard push sherpa tarballs).

See docs/IMAGE-BUILD.md and docs/IMAGE-TIERS.md
STEPS
else
  cat > "$KIT_OUT/IMAGE-FLASH-STEPS.txt" <<STEPS
flip2 image kit v$VERSION — host-side; merge super yourself or re-run prepare with --stock-super.

1. flip2 image merge-super --stock-super YOUR/super.img  OR  merge flip2-system-tree manually.
2. fastbootd: flash boot (neutron.img) + rebuilt super. Never flash EMMC_BOOT.
3. Magisk dial *#*#217703#*#*, reboot.
4. adb push flip2-system-tree/first-boot.sh /data/local/tmp/
   adb shell su -c "sh /data/local/tmp/first-boot.sh"
   adb reboot
5. Magisk: install flip2-installer-image-post-magisk.zip from this kit, reboot.
6. Sherpa STT if not in zip: flip2 ime sherpa (or wizard push sherpa tarballs).

See docs/IMAGE-BUILD.md and docs/IMAGE-TIERS.md
STEPS
fi

log "done"
echo "    system tree: $DIST/flip2-system-tree/"
echo "    image-post:  $DIST/flip2-installer-image-post-magisk.zip"
[[ -n "${BUILT_SUPER:-}" && -f "${BUILT_SUPER:-}" ]] && echo "    built super: $BUILT_SUPER"
echo "    kit:         $KIT_OUT/"
