#!/usr/bin/env bash
# Patch Astro Loop v1.5 for TCL Flip 2 display (321×428 logical).
#
# Stock game uses a 960×2142 portrait design column → renderScale ≈ min(428/960,
# 321/2142) ≈ 0.2 on Flip2, so everything is tiny and pinned to the top. This
# patch uses a 960×720 landscape design rect (960×960 portrait) and locks the
# orientation in the manifest.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PKG="com.astroloop.game"
EXPECTED_VERSION="1.5"
PATCH_FILE="$HERE/astro-loop-1.5-flip2-display.patch"

WORK="${WORK:-/tmp/astro-loop-patch}"
SRC_APK=""
DO_INSTALL=1
UNINSTALL=0
FORCE=0
ORIENT="${FLIP2_ASTRO_LOOP_ORIENT:-landscape}"

die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*"; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Applies Flip 2 display patch to F-Droid Astro Loop 1.5 (versionCode 6).

Options:
  --apk PATH     Source APK (default: download F-Droid pin or ~/astro-loop-original-6.apk)
  --work DIR     Work directory (default: $WORK)
  --no-install   Build and sign only
  --uninstall    Uninstall $PKG first (needed for F-Droid → debug-signed patch)
  --force        Skip version check
  --orientation portrait|landscape
                 Lock screen orientation (default: landscape on Flip2)
  -h, --help     Show this help

Output: \$WORK/com.astroloop.game_6-flip2-display-signed.apk
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --apk) SRC_APK="${2:-}"; [ -n "$SRC_APK" ] || die "--apk needs a path"; shift 2 ;;
    --work) WORK="${2:-}"; [ -n "$WORK" ] || die "--work needs a path"; shift 2 ;;
    --no-install) DO_INSTALL=0; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    --force) FORCE=1; shift ;;
    --orientation)
      ORIENT="${2:-}"
      case "$ORIENT" in portrait|landscape) shift 2 ;;
      *) die "--orientation must be portrait or landscape" ;;
      esac ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (try --help)" ;;
  esac
done

if [ -z "${JAVA_HOME:-}" ] || [ ! -x "$JAVA_HOME/bin/java" ]; then
  for cand in "$HOME/.local/opt/jdk17" /usr/lib/jvm/java-17-openjdk-amd64; do
    [ -x "$cand/bin/java" ] && JAVA_HOME="$cand" && break
  done
fi
[ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ] || die "Java 17 not found"
export PATH="$JAVA_HOME/bin:$PATH"

APKTOOL="${APKTOOL:-$HOME/.local/bin/apktool.jar}"
[ -f "$APKTOOL" ] || die "apktool not found at $APKTOOL"

find_build_tool() {
  local name="$1" d ver
  for d in "${ANDROID_HOME:-}/build-tools" "$HOME/.local/share/android-sdk/build-tools" "$HOME/Android/Sdk/build-tools"; do
    [ -d "$d" ] || continue
    for ver in $(ls -1 "$d" 2>/dev/null | sort -Vr); do
      [ -x "$d/$ver/$name" ] && echo "$d/$ver/$name" && return 0
    done
  done
  return 1
}
ZIPALIGN="$(find_build_tool zipalign || true)"
[ -n "$ZIPALIGN" ] || die "zipalign not found"

BACKUP="$HOME/astro-loop-original-6.apk"
FDROID_URL="https://f-droid.org/repo/com.astroloop.game_6.apk"
FDROID_SHA="79aa83482f64f7ae0bc245aa3550bc0e231fecdc046cb783b818917e418f6cf7"

if [ -z "$SRC_APK" ]; then
  if [ -f "$BACKUP" ]; then
    SRC_APK="$BACKUP"
  else
    log "Downloading F-Droid v6"
    mkdir -p "$(dirname "$BACKUP")"
    curl -fsSL "$FDROID_URL" -o "$BACKUP" || die "download failed"
    actual="$(sha256sum "$BACKUP" | awk '{print $1}')"
    [ "$actual" = "$FDROID_SHA" ] || die "checksum mismatch"
    SRC_APK="$BACKUP"
  fi
fi
[ -f "$SRC_APK" ] || die "APK not found: $SRC_APK"

mkdir -p "$WORK"
DEC="$WORK/dec"
rm -rf "$DEC"
log "Decoding $(basename "$SRC_APK")"
# Full decode, NOT `-r`: raw resources leaves AndroidManifest.xml as binary XML,
# which makes the orientation rewrite below silently match nothing.
java -jar "$APKTOOL" d -f -o "$DEC" "$SRC_APK" >"$WORK/decode.log" 2>&1 \
  || die "apktool decode failed (see $WORK/decode.log)"
if ! grep -qa '<manifest' "$DEC/AndroidManifest.xml"; then
  die "AndroidManifest.xml is not editable text — decode failed"
fi

log "Applying Flip 2 display patch"
if ! ( cd "$DEC" && patch -p0 --batch --forward < "$PATCH_FILE" ); then
  die "patch did not apply — wrong Astro Loop version? (expected $EXPECTED_VERSION / vc 6)"
fi

log "Locking $ORIENT in AndroidManifest.xml"
sed -i \
  -e 's/android:screenOrientation="[a-zA-Z]*"/android:screenOrientation="'"$ORIENT"'"/' \
  "$DEC/AndroidManifest.xml" \
  || die "could not set orientation in AndroidManifest.xml"
# The rewrite must actually land. A silent no-op shipped a still-portrait build once:
# sed exits 0 when it matches nothing, and -r decoding left the manifest binary.
if ! grep -qa "android:screenOrientation=\"$ORIENT\"" "$DEC/AndroidManifest.xml"; then
  die "orientation rewrite did not take effect (expected screenOrientation=\"$ORIENT\")"
fi
grep -ao "android:screenOrientation=\"[a-zA-Z]*\"" "$DEC/AndroidManifest.xml" | sed 's/^/    /'

log "Building"
UNSIGNED="$WORK/com.astroloop.game_6-flip2-display-unsigned.apk"
java -jar "$APKTOOL" b -o "$UNSIGNED" "$DEC" >"$WORK/build.log" 2>&1 \
  || die "apktool build failed (see $WORK/build.log)"

ALIGNED="$WORK/com.astroloop.game_6-flip2-display-aligned.apk"
SIGNED="$WORK/com.astroloop.game_6-flip2-display-signed.apk"
"$ZIPALIGN" -p -f 4 "$UNSIGNED" "$ALIGNED"

KS="${KEYSTORE:-$HOME/.android/debug.keystore}"
KS_PASS="${KEYSTORE_PASS:-android}"
KS_ALIAS="${KEYSTORE_ALIAS:-androiddebugkey}"
if [ ! -f "$KS" ]; then
  keytool -genkeypair -keystore "$KS" -storepass "$KS_PASS" -keypass "$KS_PASS" \
    -alias "$KS_ALIAS" -keyalg RSA -keysize 2048 -validity 10000 \
    -dname "CN=Android Debug,O=Android,C=US" >/dev/null 2>&1
fi

APKSIGNER="$(find_build_tool apksigner || true)"
if [ -n "$APKSIGNER" ]; then
  "$APKSIGNER" sign --ks "$KS" --ks-pass "pass:$KS_PASS" --key-pass "pass:$KS_PASS" \
    --ks-key-alias "$KS_ALIAS" --out "$SIGNED" "$ALIGNED"
  "$APKSIGNER" verify "$SIGNED" >/dev/null
else
  jarsigner -keystore "$KS" -storepass "$KS_PASS" -keypass "$KS_PASS" \
    -signedjar "$SIGNED" "$ALIGNED" "$KS_ALIAS"
fi

log "Signed APK: $SIGNED"

if [ "$DO_INSTALL" -eq 1 ]; then
  adb get-state >/dev/null 2>&1 || die "no adb device (use --no-install)"
  if [ "$UNINSTALL" -eq 1 ]; then
    log "Uninstalling $PKG (app data will be lost)"
    adb uninstall "$PKG" >/dev/null 2>&1 || true
  fi
  if ! adb install -r "$SIGNED"; then
    if adb shell pm path "$PKG" >/dev/null 2>&1; then
      log "Install failed — uninstalling existing build and retrying"
      adb uninstall "$PKG" >/dev/null 2>&1 || true
      adb install -r "$SIGNED" || die "install failed after uninstall"
    else
      die "install failed"
    fi
  fi
  log "Installed display-patched build ($ORIENT). Readable scale on Flip2 logical 321×428."
fi
