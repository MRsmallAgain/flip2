#!/usr/bin/env bash
# TCL Flip2 Manager — dependency check, npm install if needed, start Companion.
# Usage: ./run-companion.sh [--smoke | extra electron args…]
set -euo pipefail

COMPANION_DIR="$(cd "$(dirname "$0")" && pwd)"
FLIP2_ROOT="$(cd "$COMPANION_DIR/.." && pwd)"
WIZARD_DIR="$FLIP2_ROOT/wizard"

die() { echo "flip2-manager: $*" >&2; exit 1; }
warn() { echo "flip2-manager: warning: $*" >&2; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

echo "=== TCL Flip2 Manager (Companion) ==="
echo "Repo: $FLIP2_ROOT"

[[ -d "$WIZARD_DIR/pages" ]] || die "wizard/ not found at $WIZARD_DIR — run from a full flip2 checkout."
[[ -f "$COMPANION_DIR/package.json" ]] || die "companion/package.json missing."

if ! need_cmd node; then
  die "Node.js is not installed. Install Node 18+ (https://nodejs.org/) then re-run this script."
fi
if ! need_cmd npm; then
  die "npm is not on PATH (usually ships with Node.js)."
fi

NODE_MAJOR="$(node -p "process.versions.node.split('.')[0]" 2>/dev/null || echo 0)"
if [[ "${NODE_MAJOR:-0}" -lt 18 ]]; then
  warn "Node $NODE_MAJOR detected; Node 18+ is recommended for Electron 33."
fi

ELECTRON_BIN="$COMPANION_DIR/node_modules/.bin/electron"
if [[ ! -x "$ELECTRON_BIN" ]] || [[ ! -d "$COMPANION_DIR/node_modules/electron" ]]; then
  if [[ "${FLIP2_SKIP_NPM_INSTALL:-}" == "1" ]]; then
    die "Electron not installed and FLIP2_SKIP_NPM_INSTALL=1 — run: cd $COMPANION_DIR && npm install"
  fi
  echo "Installing Companion dependencies (first run may take a few minutes)…"
  (cd "$COMPANION_DIR" && npm install --no-fund --no-audit)
  [[ -x "$ELECTRON_BIN" ]] || die "npm install finished but electron is missing — check $COMPANION_DIR/npm-debug.log"
fi

BUNDLED_ADB="$COMPANION_DIR/platform-tools-win/adb.exe"
if [[ -z "${FLIP2_ADB:-}" && -x "$BUNDLED_ADB" ]]; then
  export FLIP2_ADB="$BUNDLED_ADB"
fi

ADB_BIN="adb"
if [[ -n "${FLIP2_ADB:-}" ]]; then
  ADB_BIN="$FLIP2_ADB"
elif ! need_cmd adb; then
  warn "adb not on PATH. Prepare → Connect needs Android Platform Tools."
  warn "  Linux: sudo apt install android-sdk-platform-tools-common  (or add platform-tools to PATH)"
  warn "  Or export FLIP2_ADB=/full/path/to/adb"
fi

if need_cmd adb || [[ -x "$ADB_BIN" ]]; then
  if out="$(adb version 2>/dev/null | head -1)"; then
    echo "adb: $out"
  fi
else
  warn "Skipping adb version check."
fi

if [[ "$(uname -s)" == "Linux" ]]; then
  RULES="/etc/udev/rules.d/51-android-flip2-adb.rules"
  if [[ ! -f "$RULES" ]]; then
    warn "Linux udev rules not installed ($RULES). Companion can install them in Prepare → USB rules."
  fi
fi

EXTRA_ARGS=("$@")
# Safe mode on Linux when GPU causes blank window (same as npm run start:safe).
if [[ "${FLIP2_COMPANION_SAFE:-}" == "1" ]] || [[ "${FLIP2_COMPANION_SAFE:-}" == "auto" && "$(uname -s)" == "Linux" ]]; then
  export ELECTRON_DISABLE_GPU=1
  EXTRA_ARGS=(--disable-gpu --disable-gpu-compositing "${EXTRA_ARGS[@]}")
fi

echo "Starting TCL Flip2 Manager…"
cd "$COMPANION_DIR"
exec "$ELECTRON_BIN" . "${EXTRA_ARGS[@]}"
