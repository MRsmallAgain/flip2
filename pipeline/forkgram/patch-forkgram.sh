#!/usr/bin/env bash
# Patch Forkgram for the TCL Flip 2 null-keyboard setup.
#
# Adds BACK-to-delete in focused text fields and stops Telegram from hiding the
# IME / pretending a hardware keyboard is present. See README.md in this dir.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PKG="org.forkgram.classic"
EXPECTED_VERSION="13.0.2.0"
PATCH_FILE="$HERE/forkgram-$EXPECTED_VERSION-back.patch"

WORK="${WORK:-/tmp/forkgram-patch}"
SRC_APK=""
DO_INSTALL=1
UNINSTALL=0
FORCE=0

die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*"; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Patches Forkgram so BACK deletes in a focused text field instead of closing the
app, and so the null-keyboard IME can be shown and receive keys.

Options:
  --apk PATH     Use PATH as the source APK (default: pull from device)
  --work DIR     Work directory (default: $WORK)
  --no-install   Build and sign only
  --uninstall    Uninstall the app first (wipes app data; needed once when
                 switching from the F-Droid signature to the debug signature)
  --force        Skip the version-name check
  -h, --help     Show this help

The source APK is backed up to ~/forkgram-original-$EXPECTED_VERSION.apk.
Signed output: \$WORK/forkgram-$EXPECTED_VERSION-patched-signed.apk
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --apk) SRC_APK="${2:-}"; [ -n "$SRC_APK" ] || die "--apk needs a path"; shift 2 ;;
    --work) WORK="${2:-}"; [ -n "$WORK" ] || die "--work needs a path"; shift 2 ;;
    --no-install) DO_INSTALL=0; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (try --help)" ;;
  esac
done

# --- toolchain -------------------------------------------------------------

if [ -z "${JAVA_HOME:-}" ] || [ ! -x "$JAVA_HOME/bin/java" ]; then
  for cand in "$HOME/.local/opt/jdk17" /usr/lib/jvm/java-17-openjdk-amd64 \
              /usr/lib/jvm/default-java; do
    if [ -x "$cand/bin/java" ]; then JAVA_HOME="$cand"; break; fi
  done
fi
[ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ] \
  || die "Java not found; set JAVA_HOME (JDK 17 required by this apktool)"
export PATH="$JAVA_HOME/bin:$PATH"

APKTOOL="${APKTOOL:-$HOME/.local/bin/apktool.jar}"
[ -f "$APKTOOL" ] || die "apktool not found at $APKTOOL (set APKTOOL=...)"

find_build_tool() {
  local name="$1" d ver
  for d in "${ANDROID_HOME:-}/build-tools" "${ANDROID_SDK_ROOT:-}/build-tools" \
           "$HOME/.local/share/android-sdk/build-tools" \
           "$HOME/Android/Sdk/build-tools" "$HOME/android-sdk/build-tools" \
           /opt/android-sdk/build-tools /usr/lib/android-sdk/build-tools; do
    [ -d "$d" ] || continue
    for ver in $(ls -1 "$d" 2>/dev/null | sort -Vr); do
      if [ -x "$d/$ver/$name" ]; then echo "$d/$ver/$name"; return 0; fi
    done
  done
  return 1
}
ZIPALIGN="$(find_build_tool zipalign || true)"
APKSIGNER="$(find_build_tool apksigner || true)"
[ -n "$ZIPALIGN" ] || die "zipalign not found (set ANDROID_HOME to an SDK with build-tools)"
[ -n "$APKSIGNER" ] || die "apksigner not found (set ANDROID_HOME to an SDK with build-tools)"

need_device() {
  adb get-state >/dev/null 2>&1 || die "no adb device (or pass --apk PATH)"
}

# --- source APK ------------------------------------------------------------

BACKUP="$HOME/forkgram-original-$EXPECTED_VERSION.apk"
if [ -z "$SRC_APK" ]; then
  if [ -f "$BACKUP" ]; then
    SRC_APK="$BACKUP"
  else
    need_device
    REMOTE="$(adb shell pm path "$PKG" | tr -d '\r' | sed -n 's/^package://p' | head -1)"
    [ -n "$REMOTE" ] || die "$PKG not installed; pass --apk PATH with the original APK"
    log "Pulling $REMOTE"
    adb pull "$REMOTE" "$BACKUP" >/dev/null
    SRC_APK="$BACKUP"
  fi
fi
[ -f "$SRC_APK" ] || die "APK not found: $SRC_APK"

if adb get-state >/dev/null 2>&1; then
  VN="$(adb shell dumpsys package "$PKG" 2>/dev/null \
        | sed -n 's/^ *versionName=//p' | head -1 | tr -d '\r')"
  if [ -n "$VN" ] && [ "$VN" != "$EXPECTED_VERSION" ] && [ "$FORCE" -eq 0 ]; then
    die "installed Forkgram is $VN but the patch targets $EXPECTED_VERSION; use --force to try anyway"
  fi
fi

# --- decode, patch, build --------------------------------------------------

mkdir -p "$WORK"
DEC="$WORK/dec"
rm -rf "$DEC"
log "Decoding $(basename "$SRC_APK")"
java -jar "$APKTOOL" d -r -f -o "$DEC" "$SRC_APK" >"$WORK/decode.log" 2>&1 \
  || die "apktool decode failed (see $WORK/decode.log)"

log "Applying BACK-to-delete / IME patches"
if ! ( cd "$DEC" && patch -p1 --batch --forward < "$PATCH_FILE" ); then
  die "patch did not apply — wrong Forkgram version? (expected $EXPECTED_VERSION)"
fi

log "Building"
UNSIGNED="$WORK/forkgram-$EXPECTED_VERSION-patched.apk"
java -jar "$APKTOOL" b -o "$UNSIGNED" "$DEC" >"$WORK/build.log" 2>&1 \
  || die "apktool build failed (see $WORK/build.log)"

# --- align + sign ----------------------------------------------------------

ALIGNED="$WORK/forkgram-$EXPECTED_VERSION-aligned.apk"
SIGNED="$WORK/forkgram-$EXPECTED_VERSION-patched-signed.apk"
"$ZIPALIGN" -p -f 4 "$UNSIGNED" "$ALIGNED"

KS="${KEYSTORE:-$HOME/.android/debug.keystore}"
KS_PASS="${KEYSTORE_PASS:-android}"
KS_ALIAS="${KEYSTORE_ALIAS:-androiddebugkey}"
if [ ! -f "$KS" ]; then
  log "Creating debug keystore at $KS"
  mkdir -p "$(dirname "$KS")"
  keytool -genkeypair -keystore "$KS" -storepass "$KS_PASS" -keypass "$KS_PASS" \
    -alias "$KS_ALIAS" -keyalg RSA -keysize 2048 -validity 10000 \
    -dname "CN=Android Debug,O=Android,C=US" >/dev/null 2>&1
fi
"$APKSIGNER" sign --ks "$KS" --ks-pass "pass:$KS_PASS" --key-pass "pass:$KS_PASS" \
  --ks-key-alias "$KS_ALIAS" --out "$SIGNED" "$ALIGNED"
"$APKSIGNER" verify "$SIGNED" >/dev/null
log "Signed APK: $SIGNED"

# --- install ---------------------------------------------------------------

if [ "$DO_INSTALL" -eq 1 ]; then
  need_device
  if [ "$UNINSTALL" -eq 1 ]; then
    log "Uninstalling $PKG (app data will be lost)"
    adb uninstall "$PKG" >/dev/null || true
  fi
  if ! adb install -r "$SIGNED"; then
    die "install failed. If it reported INSTALL_FAILED_UPDATE_INCOMPATIBLE, rerun with --uninstall (wipes app data)."
  fi
  log "Installed. Launch Forkgram and test BACK in a text field; empty fields still navigate back."
fi
