#!/usr/bin/env bash
# Install the flip2 default wallpaper.
#
# This ROM has no `cmd wallpaper` entry point ("No shell command
# implementation."), so the wallpaper is not set through the wallpaper service
# API. It is installed by placing the raw PNG where the framework keeps it and
# reads it at boot:
#
#   /data/system/users/0/wallpaper
#     owner system:system, mode 600, label u:object_r:wallpaper_file:s0
#
# Verified on donor MRV8IJJVPRYTS4UG on 2026-10-29: after a reboot the file
# was byte-identical to its source, and the system had additionally written a
# `wallpaper_orig` sibling (it parses the file at load). No settings key and no
# boot script are involved.
#
# Needs root (Magisk). The Tier B installer does the same copy at first boot,
# and `flip2 setup full` calls this script.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/lib/bootstrap.sh"
flip2_env_init

ASSET="$ROOT/pipeline/wallpaper/assets/flip2-wallpaper.png"
GEN="$ROOT/pipeline/wallpaper/gen-wallpaper.py"
REMOTE=/data/local/tmp/flip2-wallpaper.png
DEST=/data/system/users/0/wallpaper

usage() {
  cat <<EOF
Usage: flip2 wallpaper <subcommand>

  apply     Install assets/flip2-wallpaper.png as the phone's wallpaper (root)
  status    Show the on-device wallpaper file, its label and whether it matches
  gen       Regenerate the asset from gen-wallpaper.py (PIL, deterministic)

Takes effect on the running phone after a reboot; the copy is what survives.
See: $ROOT/docs/WALLPAPER.md
EOF
}

cmd="${1:-help}"
shift || true

case "$cmd" in
  help|-h|--help)
    usage
    ;;
  gen)
    python3 "$GEN" "$@"
    ;;
  status)
    flip2_adb_require_device || exit 1
    echo "== $DEST"
    adb shell "su -c 'ls -lZ $DEST 2>/dev/null || echo missing'"
    if [[ -f "$ASSET" ]]; then
      local_md5=$(md5sum "$ASSET" | cut -d' ' -f1)
      dev_md5=$(adb shell "su -c 'md5sum $DEST 2>/dev/null'" | tr -d '\r' | awk '{print $1}')
      echo "host asset : $local_md5"
      echo "on device  : ${dev_md5:-missing}"
      if [[ "$local_md5" == "$dev_md5" ]]; then
        echo "MATCH: the flip2 wallpaper is installed"
      else
        echo "DIFFERS: apply with 'flip2 wallpaper apply'"
      fi
    fi
    ;;
  apply)
    flip2_adb_require_device || exit 1
    [[ -f "$ASSET" ]] || { echo "Missing $ASSET -- run: flip2 wallpaper gen" >&2; exit 1; }
    local_md5=$(md5sum "$ASSET" | cut -d' ' -f1)
    adb push "$ASSET" "$REMOTE" >/dev/null
    adb shell "su -c 'cp $REMOTE $DEST && chown system:system $DEST && chmod 600 $DEST && restorecon $DEST'"
    dev_md5=$(adb shell "su -c 'md5sum $DEST'" | tr -d '\r' | awk '{print $1}')
    if [[ "$local_md5" != "$dev_md5" ]]; then
      echo "FAIL: on-device md5 $dev_md5 != $local_md5" >&2
      exit 1
    fi
    echo "Installed $DEST ($dev_md5). Reboot to see it on the home screen."
    ;;
  *)
    echo "Unknown wallpaper subcommand: $cmd" >&2
    usage >&2
    exit 1
    ;;
esac
