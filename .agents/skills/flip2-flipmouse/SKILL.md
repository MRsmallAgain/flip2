---
name: flip2-flipmouse
description: Build, install, and debug FlipMouse on the TCL Flip 2. Use whenever the user mentions the virtual mouse, cursor toggle, hold delay, keypad grab, shortcuts dying in mouse mode, or the FlipMouse Magisk module.
---

# FlipMouse on the Flip 2

Vendored, patched copy of TylerBoni/FlipMouse. It stays a passive observer until activated, because grabbing the keypad at boot collides with the null keyboard's `*` key.

```bash
export PATH="$HOME/.local/share/flip2/bin:$PATH"
flip2 flipmouse build              # NDK armv7a static libevdev → pipeline/flipmouse/build/FlipMouse.zip
flip2 flipmouse build --debug      # -DDEBUG, logs to /cache/FlipMouse.log
flip2 flipmouse install            # magisk --install-module, unpack into modules/, start daemon now
flip2 flipmouse status
flip2 flipmouse rollback           # remove module; reboot restores stock
```

Needs the NDK at `~/.local/share/android-sdk/ndk/29.0.14206865` (or `ANDROID_NDK_ROOT`). `install` refuses to run if the zip is missing.

## Controls (toolkit 1.1.0-flip2, module 1.4.1-flip2)

Do not document a 2 second hold. The toggle is 1 second.

| Action | Key | Code |
|--------|-----|------|
| Enter / leave mouse mode | Hold the upper-left soft key, then release | scan 139, `HOLD_TOGGLE_MS` 1000 |
| Leave mouse mode | Tap star | 522 |
| Drag toggle | DEL | 138 |
| Shortcuts bar | Right soft key passes through | raw 48 is `SOFT_RIGHT`; it must not be swallowed |

Raw 48 used to fall into `case KEY_B` and get eaten, which is why Shortcuts died in mouse mode. Drag moved off that key onto DEL. Star is the exit, and it is also the IME dictation key, so mouse mode must not grab the keypad until the user asks.

Magisk 25.2 only stages a new module in `modules_update` until reboot. `pipeline/flipmouse/install.sh` unpacks straight into `/data/adb/modules/FlipMouse` and starts the daemon. A reboot is not required to pick up a binary change, but the running `mouse` process must be the new file. Compare checksums:

```bash
md5sum pipeline/flipmouse/build/mouse
adb shell "su -c 'md5sum /data/adb/modules/FlipMouse/mouse; pidof mouse'"
```

`flip2 flipmouse status` showing a live PID is not enough if that binary is from an older install.

## When the hold does not grab

A 1.2 s hold of scan 139 that still lets arrow scan 103 reach the IME means mouse mode never activated. Soft-right scan 48 reaching the IME is expected once grabbed, and also expected when not grabbed, so it does not prove the grab.

The kernel `input_event` on this 4058G is 16 bytes and the binary reads 16, so a 64-bit `time_t` size mismatch is not the bug. `ENABLE_LOG` is off unless the zip was built with `--debug`; `/cache/FlipMouse.log` otherwise only has `service.sh` lines. Rebuild with `--debug`, install, and watch that log across one hold before changing `main.c` again.

Release builds log only: `Virtual mouse initialized (passive — hold upper-left soft key 1s and release to activate)`.
