# shellcheck shell=bash
# Magisk module install helpers — require flip2_adb_require_device first.

# flip2_magisk_push_install <zip> [remote-name]
# Push a module zip to /sdcard/Download and install it via magisk CLI.
# Prints what happened; caller decides about reboot (staged in modules_update
# until reboot on Magisk 25.2).
flip2_magisk_push_install() {
  local zip="$1"
  local name="${2:-$(basename "$zip")}"
  local remote="/sdcard/Download/$name"
  adb get-state >/dev/null 2>&1 || { echo "No adb device" >&2; return 1; }
  [[ -f "$zip" ]] || { echo "Missing $zip" >&2; return 1; }
  adb push "$zip" "$remote"
  adb shell "su -c 'magisk --install-module $remote'"
}

# flip2_magisk_module_installed <module-id>
# 0 if the module dir exists with a module.prop (i.e. active or staged).
flip2_magisk_module_installed() {
  adb shell "su -c 'ls /data/adb/modules/$1/module.prop 2>/dev/null'" | grep -q module.prop
}
