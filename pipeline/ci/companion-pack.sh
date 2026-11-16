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
Usage: pipeline/ci/companion-pack.sh <smoke|linux|win>

  smoke   npm install (if needed), electron --smoke
  linux   prepack:linux + electron-builder --linux (AppImage, dir)
  win     prepack:win + electron-builder --win (NSIS, portable)

Artifacts: companion/dist/
EOF
}

log() { printf '==> %s\n' "$*"; }

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
  win)
    ensure_companion_deps
    (cd "$COMPANION" && npm run pack:win)
    ;;
  -h|--help) usage; exit 0 ;;
  *) echo "Unknown command: ${cmd:-}" >&2; usage; exit 1 ;;
esac
