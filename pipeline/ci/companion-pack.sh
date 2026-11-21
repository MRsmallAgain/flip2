#!/usr/bin/env bash
# Pack TCL Flip2 Manager (Electron companion). Used by GitLab CI and local release prep.
#
#   bash pipeline/ci/companion-pack.sh smoke    # headless smoke (Linux)
#   bash pipeline/ci/companion-pack.sh linux    # AppImage + linux-unpacked
#   bash pipeline/ci/companion-pack.sh win      # NSIS + portable (Wine image or Windows)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COMPANION="$ROOT/companion"

usage() {
  cat <<EOF
Usage: pipeline/ci/companion-pack.sh <smoke|linux|prepack-win|win>

  smoke       npm install (if needed), electron --smoke
  linux       prepack:linux + electron-builder --linux (AppImage, dir)
  prepack-win npm run prepack:win + verify platform-tools-win (CI network fetch)
  win         prepack:win + electron-builder --win; fails if extraResources omit adb

Artifacts: companion/dist/
EOF
}

log() { printf '==> %s\n' "$*"; }

verify_prepack_win() {
  local adb_src="$COMPANION/platform-tools-win/adb.exe"
  local need=("adb.exe" "AdbWinApi.dll" "AdbWinUsbApi.dll")
  local f
  for f in "${need[@]}"; do
    if [[ ! -f "$COMPANION/platform-tools-win/$f" ]]; then
      echo "FATAL: prepack:win missing platform-tools-win/$f" >&2
      exit 1
    fi
  done
  log "verified platform-tools-win ($(stat -c '%s' "$adb_src") byte adb.exe)"
}

ensure_companion_deps() {
  if [[ -n "${CI:-}" ]] && [[ -f "$COMPANION/package-lock.json" ]]; then
    log "npm ci in companion/"
    (cd "$COMPANION" && npm ci --no-fund --no-audit)
    return
  fi
  if [[ ! -d "$COMPANION/node_modules/electron" ]]; then
    log "npm install in companion/"
    (cd "$COMPANION" && npm install --no-fund --no-audit)
  fi
}

cmd="${1:-}"
case "$cmd" in
  smoke)
    ensure_companion_deps
    smoke_args=(--smoke)
    [[ -n "${CI:-}" ]] && smoke_args+=(--no-sandbox)
    if [[ -n "${CI:-}" ]] && [[ -z "${DISPLAY:-}" ]] && command -v xvfb-run >/dev/null; then
      (cd "$COMPANION" && xvfb-run -a npm run start:safe -- "${smoke_args[@]}")
    else
      (cd "$COMPANION" && npm run start:safe -- "${smoke_args[@]}")
    fi
    ;;
  linux)
    ensure_companion_deps
    (cd "$COMPANION" && npm run pack:linux)
    ;;
  prepack-win)
    ensure_companion_deps
    log "prepack:win (platform-tools + VCOM for extraResources)"
    (cd "$COMPANION" && npm run prepack:win)
    verify_prepack_win
    ;;
  win)
    ensure_companion_deps
    log "prepack:win (platform-tools + VCOM for extraResources)"
    (cd "$COMPANION" && npm run prepack:win)
    verify_prepack_win
    if [[ -n "${CI:-}" ]]; then
      log "CI: portable-only (NSIS under Wine fails on uninstaller stub)"
      (cd "$COMPANION" && npm run pack:win:ci)
    else
      (cd "$COMPANION" && npm run pack:win)
    fi
    unpacked_adb="$COMPANION/dist/win-unpacked/resources/platform-tools/adb.exe"
    if [[ ! -f "$unpacked_adb" ]]; then
      echo "FATAL: packaged build missing dist/win-unpacked/resources/platform-tools/adb.exe" >&2
      echo "  Wine/CI packs can pass prepack but omit extraResources — do not publish this artifact." >&2
      exit 1
    fi
    log "verified bundled adb in win-unpacked: $unpacked_adb"
    ;;
  -h|--help) usage; exit 0 ;;
  *) echo "Unknown command: ${cmd:-}" >&2; usage; exit 1 ;;
esac
