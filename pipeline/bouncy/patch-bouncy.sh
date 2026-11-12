#!/usr/bin/env bash
# Patch Vector Pinball (Bouncy) v43 for Flip 2: D-pad + soft keys 139/48 flippers,
# optional reset score per ball in unlimited mode. Left/right mapping is never swapped.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLIP2_ROOT="$(cd "$HERE/../.." && pwd)"

PKG="com.dozingcatsoftware.bouncy"
EXPECTED_VERSION="43"
PATCH_FILE="$HERE/bouncy-43-flip2-controls.patch"
DEFAULT_APK="$FLIP2_ROOT/pipeline/deploy/sources/com.dozingcatsoftware.bouncy_43-fdroid.apk"
FDROID_SHA="ffda0d9cb0b1b2aa58be9559dda891c4fa24391bc481d297a8e3d96c31f62721"

WORK="${WORK:-/tmp/bouncy-patch}"
SRC_APK=""
DO_INSTALL=1
FORCE=0

die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*"; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Applies Flip 2 controls patch to F-Droid Bouncy v43 (1.16.0).

Options:
  --apk PATH     Source APK (default: deploy pin $DEFAULT_APK)
  --work DIR     Work directory (default: $WORK)
  --no-install   Build and sign only
  --force        Skip version check
  -h, --help     Show this help

Output: \$WORK/com.dozingcatsoftware.bouncy_43-flip2-signed.apk
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --apk) SRC_APK="${2:-}"; [ -n "$SRC_APK" ] || die "--apk needs a path"; shift 2 ;;
    --work) WORK="${2:-}"; [ -n "$WORK" ] || die "--work needs a path"; shift 2 ;;
    --no-install) DO_INSTALL=0; shift ;;
    --force) FORCE=1; shift ;;
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
[ -f "$PATCH_FILE" ] || die "patch not found: $PATCH_FILE"

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

SRC_APK="${SRC_APK:-$DEFAULT_APK}"
[ -f "$SRC_APK" ] || die "APK not found: $SRC_APK"
if [ "$FORCE" -eq 0 ]; then
  actual="$(sha256sum "$SRC_APK" | awk '{print $1}')"
  [ "$actual" = "$FDROID_SHA" ] || die "checksum mismatch (got $actual); use --force to override"
fi

mkdir -p "$WORK"
DEC="$WORK/dec"
rm -rf "$DEC"
log "Decoding $(basename "$SRC_APK")"
java -jar "$APKTOOL" d -f -o "$DEC" "$SRC_APK" >"$WORK/decode.log" 2>&1 \
  || die "apktool decode failed (see $WORK/decode.log)"

log "Applying Flip 2 controls patch"
if ! ( cd "$DEC" && patch -p0 --batch --forward < "$PATCH_FILE" ); then
  die "patch did not apply — wrong Bouncy version? (expected v$EXPECTED_VERSION)"
fi

log "Building"
UNSIGNED="$WORK/com.dozingcatsoftware.bouncy_43-flip2-unsigned.apk"
java -jar "$APKTOOL" b -o "$UNSIGNED" "$DEC" >"$WORK/build.log" 2>&1 \
  || die "apktool build failed (see $WORK/build.log)"

ALIGNED="$WORK/com.dozingcatsoftware.bouncy_43-flip2-aligned.apk"
SIGNED="$WORK/com.dozingcatsoftware.bouncy_43-flip2-signed.apk"
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
  adb install -r "$SIGNED" || die "install failed (uninstall F-Droid build first if signature clash)"
  log "Installed. D-pad L/R + soft 139/48 = flippers (never swapped). See pipeline/bouncy/README.md."
fi
