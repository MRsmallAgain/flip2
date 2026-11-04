#!/usr/bin/env bash
# Tier B: pack the single-shot flip2 Magisk installer zip.
# Bakes all device-side data (APK list, pre-quoted settings lines, module
# list, external-APK URLs) into plain files from manifest.json so the
# on-device service.sh needs no jq and no quoting gymnastics.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/lib/bootstrap.sh"
flip2_env_init

MANIFEST="$ROOT/pipeline/deploy/manifest.json"
TPL="$ROOT/pipeline/deploy/installer"
DIST="$ROOT/pipeline/deploy/dist"
HOME_KEYS="$ROOT/launcher-overlay/home-keys.json"

usage() {
  cat <<EOF
Usage: flip2 installer pack [--flavor clean|full|image-post] [--sherpa-url name=url]\
                        [--out DIR] [--no-zip]

Build the single-shot flip2 Magisk installer zip. The zip is a real Magisk
module whose one-shot service.sh runs at first boot as root: installs the
bundled user APKs, unpacks the flip2 modules (full flavor), applies baked
settings, writes /data/local/flip2/deroot.sh, then removes itself.

  --flavor clean|full|image-post
                        clean = root-independent user APKs + settings (de-root friendly)
                        full = modules + everything (default)
                        image-post = after Tier A flash: GPL sideloads + IME settings only
  --sherpa-url name=URL fetch a Sherpa-ONNX model tarball at install time
                        (repeatable; e.g. --sherpa-url en=https://...tar.bz2).
  --out DIR             staging directory (default: $DIST/installer-<flavor>)
  --no-zip              keep the staging dir only, do not build the zip
EOF
}

FLAVOR=full
OUT=""
NO_ZIP=0
SHERPA_URLS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --flavor) FLAVOR="${2:-}"; [ -n "$FLAVOR" ] || { echo "--flavor needs a value" >&2; exit 1; }; shift 2 ;;
    --sherpa-url) SHERPA_URLS+=("${2:-}"); [ -n "${2:-}" ] || { echo "--sherpa-url needs name=url" >&2; exit 1; }; shift 2 ;;
    --vosk-url|--whisper-url) echo "Removed: use --sherpa-url name=url" >&2; exit 1 ;;
    --out) OUT="${2:-}"; [ -n "$OUT" ] || { echo "--out needs a path" >&2; exit 1; }; shift 2 ;;
    --no-zip) NO_ZIP=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done
case "$FLAVOR" in clean|full|image-post) ;; *) echo "--flavor must be clean, full, or image-post" >&2; exit 1 ;; esac
for u in "${SHERPA_URLS[@]}"; do
  [[ "$u" == *=* ]] || { echo "--sherpa-url wants name=url, got: $u" >&2; exit 1; }
done

command -v jq >/dev/null || { echo "jq not found" >&2; exit 1; }

VERSION="$(jq -r '.version // "dev"' "$MANIFEST")"
VERSIONCODE="$(jq -r '.versionCode // "0"' "$MANIFEST")"
[[ -n "$OUT" ]] || OUT="$DIST/installer-$FLAVOR"

# Components active in this flavor, in install order.
# NOTE: '|' separator, not @tsv — empty TSV fields collapse under whitespace
# IFS in bash read, shifting columns; none of these values contain '|'.
ROWS="$(jq -r --arg flavor "$FLAVOR" '
  .components[]
  | select([.tiers[]] | index($flavor))
  | [ .install_order, .name, .artifact, (.zip // ""), (.apk // ""),
      (.package // ""), (.module_id // ""), (.external.repo // ""),
      (.external.tag // ""), (.external.asset // ""), (.external.url // ""),
      (.asset // "") ] | join("|")
' "$MANIFEST" | sort -n)"

rm -rf "$OUT"
mkdir -p "$OUT/META-INF/com/google/android" "$OUT/payload/data" "$OUT/payload/apks" "$OUT/payload/modules"

cp "$TPL/META-INF/com/google/android/update-binary" "$OUT/META-INF/com/google/android/update-binary"
cp "$TPL/META-INF/com/google/android/update-script" "$OUT/META-INF/com/google/android/update-script"
chmod 755 "$OUT/META-INF/com/google/android/update-binary"
sed -e "s/@VERSION@/$VERSION/" -e "s/@VERSIONCODE@/$VERSIONCODE/" "$TPL/module.prop.tmpl" > "$OUT/module.prop"
sed -e "s/@FLAVOR@/$FLAVOR/" "$TPL/customize.sh" > "$OUT/customize.sh"
cp "$TPL/service.sh" "$OUT/service.sh"

DATA="$OUT/payload/data"
mkdir -p "$DATA"
printf '%s\n' "$FLAVOR" > "$DATA/flavor.txt"
: > "$DATA/external-apks.txt"
: > "$DATA/appops.txt"
: > "$DATA/permissions.txt"

EMIT="$ROOT/pipeline/deploy/emit.sh"
chmod +x "$EMIT"
"$EMIT" --flavor "$FLAVOR" --manifest "$MANIFEST" --home-keys "$HOME_KEYS" --root "$ROOT" --data "$DATA"

MISSING=()
log() { echo "==> $*"; }

log "packing flip2 installer ($FLAVOR flavor, v$VERSION)"
while IFS='|' read -r _order name artifact zip apk pkg mid erepo etag easset eurl wpasset; do
  [[ -n "$name" ]] || continue
  echo "  + $name ($artifact)"
  case "$artifact" in
    user-apk)
      if [[ -n "$apk" ]]; then
        base="$(basename "$apk")"
        if [[ -f "$ROOT/$apk" ]]; then
          cp "$ROOT/$apk" "$OUT/payload/apks/$base"
        else
          MISSING+=("$apk")
        fi
      elif [[ -n "$eurl" || -n "$erepo" ]]; then
        url="$eurl"
        if [[ -z "$url" ]]; then
          url="https://github.com/$erepo/releases/download/$etag/$easset"
        fi
        printf '%s|%s\n' "$pkg" "$url" >> "$DATA/external-apks.txt"
      fi
      ;;
    magisk-module)
      base="$(basename "$zip")"
      if [[ -f "$ROOT/$zip" ]]; then
        cp "$ROOT/$zip" "$OUT/payload/modules/$base"
      else
        MISSING+=("$zip")
      fi
      ;;
    settings-write)
      if [[ "$name" == "home_keys" ]]; then
        for k in left right shortcuts_bar up down; do
          v="$(jq -r --arg k "$k" '.[$k] // ""' "$HOME_KEYS")"
          [[ -n "$v" ]] || MISSING+=("home-keys.json key: $k")
        done
      fi
      ;;
    wallpaper)
      if [[ -n "$wpasset" && -f "$ROOT/$wpasset" ]]; then
        mkdir -p "$OUT/payload/wallpaper"
        cp "$ROOT/$wpasset" "$OUT/payload/wallpaper/flip2-wallpaper.png"
      else
        MISSING+=("${wpasset:-wallpaper asset} (run: flip2 wallpaper gen)")
      fi
      ;;
  esac
  [[ -n "$pkg" ]] || continue
  jq -r --arg n "$name" '.components[] | select(.name==$n) | .appops[]? // empty' "$MANIFEST" \
    | while IFS=' ' read -r op mode; do
        printf 'appops set --user 0 %s %s %s\n' "$pkg" "$op" "$mode"
      done >> "$DATA/appops.txt"
  jq -r --arg n "$name" '.components[] | select(.name==$n) | .permissions[]? // empty' "$MANIFEST" \
    | while read -r perm; do
        printf 'pm grant %s %s\n' "$pkg" "$perm"
      done >> "$DATA/permissions.txt"
done <<< "$ROWS"

# Sherpa-ONNX models: never bundled; only tarball URLs if packer passed --sherpa-url.
if [ "${#SHERPA_URLS[@]}" -gt 0 ]; then
  for u in "${SHERPA_URLS[@]}"; do
    printf '%s %s\n' "${u%%=*}" "${u#*=}" >> "$DATA/sherpa-urls.txt"
  done
fi

cp "$TPL/deroot.sh" "$OUT/payload/deroot.sh"
chmod 755 "$OUT/payload/deroot.sh" "$OUT/service.sh"

if [ "${#MISSING[@]}" -gt 0 ]; then
  echo "Missing artifacts (build them first):" >&2
  printf ' - %s\n' "${MISSING[@]}" >&2
  exit 1
fi

if [[ "$NO_ZIP" == 1 ]]; then
  log "staging dir only: $OUT"
else
  ZIP="$DIST/flip2-installer-$FLAVOR-magisk.zip"
  rm -f "$ZIP"
  (cd "$OUT" && zip -rX "$ZIP" META-INF customize.sh module.prop service.sh payload) >/dev/null
  log "built $ZIP"
fi
log "flavor: $FLAVOR  version: $VERSION"
echo "    flash via Magisk app -> Install from storage, then reboot."
echo "    After boot check /cache/flip2-installer.log; de-root helper lands at"
echo "    /data/local/flip2/deroot.sh (run: sh /data/local/flip2/deroot.sh)."
