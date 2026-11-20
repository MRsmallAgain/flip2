#!/usr/bin/env bash
# Tier 1 on-device bridge helpers for Flip2 — status, open FluffyChat sign-in.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FLUFFY_PKG="chat.fluffy.fluffychat"
BEEPER_PKG="com.beeper.android"

die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*"; }

usage() {
  cat <<EOF
Usage: $(basename "$0") <subcommand>

  status       Print installed messaging/bridge packages on adb device
  open-signin  Launch FluffyChat and D-pad to Sign in / Login with Matrix-ID
  help         This help

See: $ROOT/docs/BRIDGE-ON-DEVICE-FLIP2.md
EOF
}

cmd_status() {
  adb get-state >/dev/null 2>&1 || die "no adb device"
  echo "Device: $(adb shell getprop ro.product.model 2>/dev/null | tr -d '\r') ($(adb shell getprop ro.product.cpu.abi 2>/dev/null | tr -d '\r'))"
  adb shell wm size 2>/dev/null | tr -d '\r' || true
  echo ""
  echo "Packages (bridge-related):"
  for pkg in "$FLUFFY_PKG" "$BEEPER_PKG" org.forkgram.classic com.whatsapp com.whatsapp.w4b org.thoughtcrime.securesms org.signal.android; do
    if adb shell pm path "$pkg" 2>/dev/null | grep -q package:; then
      ver="$(adb shell dumpsys package "$pkg" 2>/dev/null | grep versionName= | head -1 | tr -d '\r' | cut -d= -f2)"
      echo "  [installed] $pkg${ver:+ ($ver)}"
    else
      echo "  [missing]   $pkg"
    fi
  done
  echo ""
  echo "Tier 1: Beeper On-Device OR FluffyChat + tier-2 bridges."
  echo "Doc: $ROOT/docs/BRIDGE-ON-DEVICE-FLIP2.md"
}

cmd_open_signin() {
  adb get-state >/dev/null 2>&1 || die "no adb device"
  log "Launching FluffyChat"
  adb shell am start -n "${FLUFFY_PKG}/.MainActivity" >/dev/null 2>&1 \
    || adb shell monkey -p "$FLUFFY_PKG" -c android.intent.category.LAUNCHER 1 >/dev/null
  sleep 2
  log "D-pad down to login buttons (5×)"
  for _ in 1 2 3 4 5; do
    adb shell input keyevent 20
    sleep 0.25
  done
  log "On phone: OK on Sign in or Login with Matrix-ID; enter homeserver + credentials."
  adb exec-out screencap -p > /tmp/fluffychat-signin-hint.png 2>/dev/null \
    && echo "Screenshot: /tmp/fluffychat-signin-hint.png"
}

sub="${1:-help}"
shift || true
case "$sub" in
  status) cmd_status ;;
  open-signin) cmd_open_signin ;;
  help|-h|--help) usage ;;
  *) die "unknown: $sub (try help)" ;;
esac
