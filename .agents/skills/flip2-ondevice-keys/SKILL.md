---
name: flip2-ondevice-keys
description: Inject keypad holds and taps on the TCL Flip 2 for IME and FlipMouse tests. Use whenever a listen, cursor toggle, star, pound, soft key, or arrow needs to be driven over adb, or when `input keyevent` and `--longpress` fail to reproduce a hold.
---

# Driving the Flip 2 keypad

The matrix keypad is `/dev/input/event2`. `input_event` on this 4058G is 16 bytes. `adb shell input keyevent` speaks HID codes, not these scan codes, and `--longpress` is about 8 ms — shorter than both holds below. Use `sendevent`.

Wake first: `adb shell input keyevent KEYCODE_WAKEUP`.

## Scan codes

From `keypad-backspace/magisk-module/system/usr/keylayout/matrix-keypad.kl`:

| Key | Scan |
|-----|------|
| Star (`*`, dictation / mouse exit) | 522 |
| Pound (`#`, language or symbols) | 523 |
| Upper-left soft key (mouse toggle) | 139 |
| Right soft key (Shortcuts) | 48 |
| DEL (mouse drag) | 138 |
| D-pad up / down / left / right | 103 / 108 / 105 / 106 |
| Back | 158 |
| D-pad center | 28 |

Every event is followed by `sendevent /dev/input/event2 0 0 0` (EV_SYN). Value `1` is down, `0` is up.

## Holds

- IME `*` / `#` hold is **380 ms**. Sleep about **0.6 s** between down and up so the hold fires and a tap does not.
- FlipMouse cursor toggle is **1000 ms** on scan 139, then release. Sleep about **1.2 s**.

Root must wrap the whole chain. This works:

```bash
adb shell "su -c 'sendevent /dev/input/event2 1 522 1; sendevent /dev/input/event2 0 0 0; sleep 0.6; sendevent /dev/input/event2 1 522 0; sendevent /dev/input/event2 0 0 0'"
```

`adb shell su -c "sendevent ...; sleep ..."` runs everything after `;` unprivileged, so the hold never completes.

## Dictation check

1. `am start -a android.intent.action.SENDTO -d smsto:1` opens Messages compose. Confirm `mCurrentFocus` is `com.android.mms` and the null keyboard is the current method.
2. `adb logcat -c`, then the star hold above. Toast should be `Listening (EN)` or `Listening (UK)`.
3. Stop with a second star hold. `Flip2STT` `commitSttText:` is the raw transcript. `harvest final=` means the listen took the Vosk path.
4. Reinstalling the IME kills the process. Tap the compose field again before the next hold.
5. The user's daily language is **uk**. `flip2 ime lang en` is only for an English clip; put it back with `flip2 ime lang uk`.

## Mouse-mode check

After a 1.2 s hold of scan 139, an arrow (scan 103) should be swallowed and scan 48 should still reach the IME. If the arrow still arrives, mouse mode never grabbed the keypad. Scan 48 arriving does not prove the grab. See the `flip2-flipmouse` skill before changing `main.c`.
