---
name: flip2-adb
description: Recover and use adb on the TCL Flip 2 (4058G / Gflip6) from Linux. Use whenever adb says "no permissions", "unauthorized", "device not found", or the phone disappears after a replug or reboot; when a ZCode or sandbox shell cannot see USB; or before any flip2 install, status, or on-device test.
---

# Flip2 adb on Linux

The phone is a TCL Flip 2 (4058G). Host tooling lives in `~/.local/share/flip2`. Talk to it through the `flip2` CLI, not one-off `adb` recipes, once the device is authorized.

```bash
export PATH="$HOME/.local/share/flip2/bin:$PATH"
```

## When `adb devices` is not `device`

`no permissions` means the udev rule is missing. A one-time `chmod` on the USB node dies on the next replug. The persistent fix is:

```bash
sudo cp ~/.local/share/flip2/launcher-patch/scripts/51-android-flip2-adb.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules && sudo udevadm trigger
```

Unplug and replug. The rule covers vendor `1bbb:0c01` (adb) and `0e8d:*` (MediaTek preloader). `unauthorized` needs the on-phone RSA prompt. `device not found` after reboot is usually the same replug, not a dead daemon.

This environment's shell sometimes cannot see USB even when the user's terminal can. If `adb devices` is empty here and the user says the phone is plugged in, say so and give them the exact `flip2` command to run locally. Do not keep retrying the same `adb` call.

## Quoting and reboots

Root commands that chain with `;` must stay inside `su`. This works:

```bash
adb shell "su -c 'ls /data/adb/modules; pidof mouse'"
```

This does not: `adb shell su -c "ls; pidof mouse"` runs everything after `;` unprivileged.

`sys.boot_completed` stays `1` across `adb reboot` until the new boot finishes. Confirm a real reboot with `adb shell uptime` (a fresh boot is about 30 seconds). Wake the screen with `adb shell input keyevent KEYCODE_WAKEUP` before any UI check.

`adb push` of a directory does not follow symlinks (`remote symlink failed`). Copy real files (`cp -L`) before pushing models or other linked trees.
