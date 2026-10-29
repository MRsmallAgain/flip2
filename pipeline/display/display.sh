#!/usr/bin/env bash
# Global wm density, screen-compat, font_scale — not per-app DPI on retail API 30.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/lib/bootstrap.sh"
flip2_env_init

TELEGRAM_PKG="${FLIP2_TELEGRAM_PKG:-org.forkgram.classic}"
TAGDRAWER_PKG="${FLIP2_TAGDRAWER_PKG:-com.iwadjp.pixeltagdrawer}"

usage() {
  cat <<EOF
Usage: flip2 display <subcommand> [args]

  status                    Show wm size, density and font_scale
  size [reset|WxH]          Logical display size override (default 321x428)
  density [reset|DPI]       Global display density (default panel). reset = stock 160
  compat on|off <package>   am screen-compat (legacy letterbox), not per-app DPI
  font [reset|SCALE]        system font_scale (1.0 default)
  presets                   Print suggested DPI values for 240x320

Per-app DPI for Forkgram/Pixel Tag Drawer is not available on retail Android 11.
See: $ROOT/docs/DISPLAY-DPI.md

Examples:
  flip2 display size 321x428
  flip2 display size reset
  flip2 display density 140
  flip2 display density reset
  flip2 display compat on $TELEGRAM_PKG
  flip2 display font 1.1
EOF
}

cmd="${1:-help}"
shift || true

case "$cmd" in
  help|-h|--help)
    usage
    ;;
  status)
    adb shell wm size 2>/dev/null || true
    echo -n "display_size_forced: "
    adb shell settings get global display_size_forced 2>/dev/null || echo "(unset)"
    adb shell wm density 2>/dev/null || true
    echo -n "font_scale: "
    adb shell settings get system font_scale 2>/dev/null || echo "(unknown)"
    echo "Forkgram: $TELEGRAM_PKG"
    echo "Tag drawer: $TAGDRAWER_PKG"
    ;;
  size)
    arg="${1:-}"
    if [[ -z "$arg" ]]; then
      adb shell wm size
      exit 0
    fi
    if [[ "$arg" == "reset" ]]; then
      adb shell wm size reset
      echo "Done. Size override cleared."
      exit 0
    fi
    # Same value the bundle bakes into display_size_forced at install time,
    # written through `wm size` so it applies now as well as at next boot.
    adb shell wm size "$arg"
    echo "Done. Takes effect immediately and survives a reboot."
    ;;
  density)
    arg="${1:-}"
    if [[ -z "$arg" ]]; then
      adb shell wm density
      exit 0
    fi
    if [[ "$arg" == "reset" ]]; then
      adb shell wm density reset
    else
      adb shell wm density "$arg"
    fi
    echo "Done. Reboot or restart apps if layout looks stuck."
    ;;
  compat)
    [[ $# -ge 2 ]] || { echo "Usage: flip2 display compat on|off <package>" >&2; exit 1; }
    mode="$1"
    pkg="$2"
    case "$mode" in
      on|off) adb shell am screen-compat "$mode" "$pkg" ;;
      *) echo "Mode must be on or off" >&2; exit 1 ;;
    esac
    echo "screen-compat $mode $pkg"
    ;;
  font)
    arg="${1:-}"
    if [[ -z "$arg" ]]; then
      adb shell settings get system font_scale
      exit 0
    fi
    if [[ "$arg" == "reset" ]]; then
      adb shell settings put system font_scale 1.0
    else
      adb shell settings put system font_scale "$arg"
    fi
    echo "font_scale set. Some apps need restart."
    ;;
  presets)
    cat <<EOF
Stock main panel: 160 dpi (240x320)
  Larger UI:  flip2 display density 140  (or 120 — very large)
  Smaller UI: flip2 display density 180  (or 200 — more on screen)
  Undo:       flip2 display density reset

Telegram text: in-app Settings → Chat Settings → Text Size
AppShelf: check in-app display options; no flip2 per-app DPI on API 30
EOF
    ;;
  *)
    echo "Unknown display subcommand: $cmd" >&2
    usage >&2
    exit 1
    ;;
esac
