#!/usr/bin/env bash
# Host-side USB/adb checks for Flip2 wizard WebUSB — run on the PC with the phone plugged in.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VENDOR=1bbb

RED=$'\033[31m'
GRN=$'\033[32m'
YLW=$'\033[33m'
RST=$'\033[0m'

verdicts=()
add_verdict() { verdicts+=("$1"); }

section() { echo; echo "=== $1 ==="; }

section "Flip2 USB / host adb debug"
echo "Time: $(date -Iseconds)"

section "Wizard JS (live vs repo)"
LOCAL_ADB="${ROOT}/wizard/pages/js/adb.js"
if [[ -f "$LOCAL_ADB" ]]; then
  LOCAL_SHA="$(sha256sum "$LOCAL_ADB" | awk '{print $1}')"
  LIVE_SHA="$(curl -sL 'https://flip2burn.online/pages/js/adb.js' 2>/dev/null | sha256sum | awk '{print $1}')"
  if [[ "$LOCAL_SHA" == "$LIVE_SHA" ]]; then
    echo -e "${GRN}OK${RST}: flip2burn.online adb.js matches repo"
  else
    echo -e "${YLW}WARN${RST}: site adb.js differs from repo"
    add_verdict deploy-site
  fi
  echo "  repo HEAD: $(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo '?')"
fi

section "USB bus (TCL 1bbb)"
TCL_LINE=""
if command -v lsusb >/dev/null; then
  TCL_LINE="$(lsusb -d "${VENDOR}:" 2>/dev/null || true)"
fi
if [[ -z "$TCL_LINE" ]]; then
  echo -e "${RED}FAIL${RST}: no ${VENDOR}:xxxx device"
  add_verdict phone-not-plugged
else
  echo "$TCL_LINE"
  PID="$(echo "$TCL_LINE" | grep -oE "${VENDOR}:[0-9a-f]{4}" | cut -d: -f2)"
  case "$PID" in
    0c01) echo -e "${GRN}OK${RST}: adb-only PID 0c01" ;;
    0167) echo -e "${YLW}NOTE${RST}: MTP+adb 0167" ;;
    2000) echo -e "${RED}FAIL${RST}: preloader"; add_verdict preloader-mode ;;
  esac
fi

if lsusb -d "${VENDOR}:0167" >/dev/null 2>&1; then
  section "ADB interface (0167)"
  if lsusb -v -d "${VENDOR}:0167" 2>/dev/null | grep -q "ADB Interface"; then
    echo -e "${GRN}OK${RST}: ADB interface in descriptor"
  fi
fi

adb_serial_line() {
  adb devices 2>/dev/null | awk 'NR>1 && $1!="" {print}'
}

section "Host adb"
if command -v adb >/dev/null; then
  adb kill-server 2>/dev/null || true
  sleep 1
  echo "$(adb devices -l 2>&1)"
  ADB_LINES="$(adb_serial_line)"
  if echo "$ADB_LINES" | grep -qE '[[:space:]]device$'; then
    echo -e "${GRN}OK${RST}: host adb sees device (authorized)"
    add_verdict host-adb-holding
  elif echo "$ADB_LINES" | grep -q unauthorized; then
    echo -e "${YLW}NOTE${RST}: host adb unauthorized — tap Allow on phone"
    add_verdict adb-unauthorized
  elif [[ -n "$TCL_LINE" ]]; then
    sleep 2
    ADB_LINES="$(adb_serial_line)"
    if [[ -z "$ADB_LINES" ]]; then
      echo -e "${RED}FAIL${RST}: phone on USB bus but host adb lists zero serials (adbd not connected)"
      add_verdict adbd-invisible-to-host
    fi
  fi
  pgrep -x adb >/dev/null && echo "adb daemon: running (kill before WebUSB)" || echo "adb daemon: stopped (good for WebUSB)"
fi

section "Verdict"
if [[ ${#verdicts[@]} -eq 0 ]]; then
  [[ -z "$TCL_LINE" ]] && echo -e "${YLW}INCONCLUSIVE${RST}: plug phone" || echo -e "${GRN}HOST OK${RST}"
else
  echo -e "${RED}ISSUES:${RST}"
  printf '  - %s\n' "${verdicts[@]}"
  if [[ " ${verdicts[*]} " == *adbd-invisible-to-host* ]]; then
    echo
    echo "adbd not on USB — enable USB debugging, replug, unlock; or Companion host adb"
  fi
fi
