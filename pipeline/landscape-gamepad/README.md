# Landscape gamepad companion (Flip 2)

When the display is in **landscape** (horizontal games), the physical keypad is sideways. **Flip2Gamepad** (Magisk) grabs the matrix keypad (+ volume on `mtk-kpd`) and exposes a **virtual uinput gamepad** with your rotated D-pad and dual-stick layout.

## Activation

| Source | Config key | Behavior |
|--------|------------|----------|
| Landscape | `landscape_auto=1` (default) | Active when `dumpsys window displays` reports landscape — see *Rotation detection* below |
| Manual | `enabled=1` | Always active until cleared |
| Passive | both off | Daemon runs; keys pass through natively (no grab) |

Config file: `/data/local/flip2/gamepad.conf` (created on first boot by Magisk `service.sh`).

**Coexistence:** FlipMouse and gamepad both want `EVIOCGRAB` on the keypad. Do not run both in active grab mode — disable mouse toggle or set `enabled=0` when testing games.

## Key layout (D-pad rotated **left** in landscape)

Phone top toward your left, keypad toward you — portrait “up” on the D-pad becomes stick **left**.

### Left stick / D-pad — counter-clockwise

| Physical D-pad | Output (stick + hat) |
|----------------|----------------------|
| Up | Move **left** (−X) |
| Down | Move **right** (+X) |
| Left | Move **down** (+Y) |
| Right | Move **up** (−Y) |

That is a true 90° counter-clockwise rotation (`Up→left→down→right`). The earlier version mapped Left→−Y / Right→+Y, which is the diagonal *mirror* of this: it left Up/Down correct but swapped the up/down half of the cross, so on screen up and down felt inverted.

### Right stick — dual-stick preset (numpad)

| Key | Stick |
|-----|--------|
| **5** | Center (neutral) |
| **8** | Right |
| **4** | Down |
| **2** | Left |
| **1** / **9** / **7** / **3** | Diagonals |

Emitted as `ABS_RX` / `ABS_RY` on the virtual device.

### Face buttons

| Key | Gamepad |
|-----|---------|
| **#** | A (`BTN_SOUTH`) |
| **0** | B (`BTN_EAST`) |
| *** | X (`BTN_NORTH`) |
| D-pad center (OK) | Select — left stick click (`BTN_THUMBL`), like pressing the stick |
| **Back** (short tap) | Start (`BTN_START` press/release) |
| **Back** (hold ≥2s, release) | Real Android Back (re-injected through matrix uinput clone) |

### Triggers / shoulders

| Key | Gamepad |
|-----|---------|
| Upper-left soft (139) | L1 (`BTN_TL`) |
| Right soft (48) | R1 (`BTN_TR`) |
| Star (522) | Mapped as face X today; prefer L2 in companion preset (TODO) |
| Mail / Messenger (30) | R2 (`BTN_TR2`) |
| Volume up / down | L2 / R2 (`BTN_TL2` / `BTN_TR2`) |

Per-key customization will live in the **companion APK** + config file (not implemented in v0.1 — mappings are compiled in `main.c`).

## Commands

```sh
flip2 gamepad build          # requires libevdev from flip2 flipmouse build first
flip2 gamepad install        # Magisk zip + on-device unpack/start
flip2 gamepad status
flip2 gamepad rollback
```

## Rotation detection

The daemon polls `dumpsys window displays` every ~1.5s. This TCL build never prints AOSP's `rotation=1`/`rotation=3`; it prints `mCurrentRotation=ROTATION_90` plus a `cur=428x321` size, and `mLandscapeRotation=ROTATION_90` is a **constant** that must never be matched. Detection therefore accepts the TCL form, the AOSP form, or `cur=` width > height.

## D-pad scale

`ABS_HAT0X`/`ABS_HAT0Y` are declared over the same `-32767..32767` range as the sticks, so D-pad presses are written at full scale (`STICK_EDGE`, not `±1`). Writing raw `±1` normalises to ≈0.00003 in Android — below every hat deadzone — so the D-pad silently did nothing.

## Multiple keys at once

The keypad reports each direction as its own key, so the daemon tracks the D-pad and the numpad stick as **bitmasks of held keys** (`dpad_held`, `numpad_held`) and re-derives both axes from the set on every press and release.

Storing one stick value instead (the earlier behaviour) meant the newest key overwrote the whole axis pair: pressing a second direction cancelled the first, and releasing *either* key zeroed both axes — so lifting one finger dropped the other direction, and the still-held key never re-fired until you pressed it again. Both of those were the same bug.

Held state is also cleared on every mode change (`sync_apply_mode` / `set_active`), because a key held across the switch never delivers a release the daemon can see.

Verified on device with a fake `matrix-keypad` driven through uinput: press Up, press Left, release Up, release Left yields `HAT0X -32767 → (unchanged) → 0`, `HAT0Y 0 → +32767 → (unchanged) → 0`.

## Architecture

```
matrix-keypad + mtk-kpd
        │
        ▼
  flip2-gamepad (Magisk late_start supervisor)
        │ EVIOCGRAB when active
        └─► uinput "Flip2 Gamepad" (ABS_X/Y, ABS_RX/RY, hat, BTN_*)
```

Companion APK (`com.tim.flip2.gamepad`): see [companion/README.md](companion/README.md) — settings UI scaffold only.

## Related

- [FLIPMOUSE-SYSTEM.md](../../docs/FLIPMOUSE-SYSTEM.md) — same libevdev pattern
- [astro-loop/README.md](../astro-loop/README.md) — games with built-in gamepad support
- `flip2-ondevice-keys` skill — raw scan codes for adb `sendevent` tests

## Status

**Verified on device (Astro Loop 1.5, landscape)** — `mode -> 1` in `/cache/FlipMouse.log`, real `mtk-kpd`/`matrix-keypad` grabbed, and a held D-pad press moves the game's menu selection (1668 px changed vs 58 px of rest noise). Still a `dumpsys` poll (~1.5s), so the first input after a rotation change can be swallowed.
