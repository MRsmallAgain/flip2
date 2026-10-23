# shellcheck shell=bash
# adb helpers — require flip2_paths_init first.

flip2_adb_require_device() {
  adb get-state >/dev/null 2>&1 || {
    echo "No adb device (authorized). Unplug/replug USB; accept RSA prompt." >&2
    return 1
  }
}

flip2_adb_wait_boot() {
  adb wait-for-device
  local i boot
  for i in $(seq 1 "${1:-45}"); do
    boot=$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
    [[ "$boot" == "1" ]] && return 0
    sleep 2
  done
  echo "Boot not completed after wait." >&2
  return 1
}

flip2_launcher_restart() {
  adb shell am force-stop com.android.launcher3 2>/dev/null || true
  adb shell am start -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null || true
}
