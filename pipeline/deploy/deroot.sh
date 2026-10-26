#!/usr/bin/env bash
# Host wrapper for the on-device de-root helper. Pushes the device script
# (the same one embedded in the Tier B installer zip) to /data/local/flip2
# and runs it over plain adb shell, so it works with or without root.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/lib/bootstrap.sh"
flip2_env_init

DEV_SCRIPT="$ROOT/pipeline/deploy/installer/deroot.sh"

usage() {
  cat <<EOF
Usage: flip2 deroot [--uninstall-apks]

Runs the flip2 de-root helper on the device (plain adb shell; uses su only
if root is available). With --uninstall-apks it also removes the flip2 user
APKs (Launcher4, NullKeyboard, Forkgram).

Final manual step (root only): Magisk app -> Uninstall -> Restore Images,
then reboot. No CLI can safely restore the boot image.
EOF
}

ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --uninstall-apks|-u) ARGS+=("$1"); shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

flip2_adb_require_device

adb shell mkdir -p /data/local/flip2
adb push "$DEV_SCRIPT" /data/local/flip2/deroot.sh >/dev/null
adb shell chmod 755 /data/local/flip2/deroot.sh
adb shell sh /data/local/flip2/deroot.sh "${ARGS[@]}"
