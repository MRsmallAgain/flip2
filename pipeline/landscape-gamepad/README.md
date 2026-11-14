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

### Numpad — second D-pad, rotated the same way

The numpad cluster is the same physical cross, so it drives the **same** left stick + hat as the D-pad, with the same 90° CCW rotation. (It used to write only `ABS_RX`/`ABS_RY`, which Astro Loop never reads — see *Status* below.) Phone keypad layout: `1-2-3` is the **top** row, `7-8-9` the bottom.

| Key | Output (stick + hat) |
|-----|----------------------|
| **2** (up) | Move **left** (−X) |
| **8** (down) | Move **right** (+X) |
| **4** (left) | Move **down** (+Y) |
| **6** (right) | Move **up** (−Y) |
| **1** | left + down |
| **3** | left + up |
| **7** | right + down |
| **9** | right + up |
| **5** | neutral |

Diagonals are why the numpad keeps its own per-key bits: one key sets two directions, and a direction only clears when no held key still wants it. Mixing the two crosses is safe — both are OR-ed into the same direction set.

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
| Right soft (48), **tap** | R1 (`BTN_TR`) — emitted on release, so it never fires while you are still holding for the cursor gesture |
| Right soft (48), **hold ≥1s** | Switches to the landscape cursor (see below) |
| Star (522) | Mapped as face X today; prefer L2 in companion preset (TODO) |
| Mail / Messenger (30) | R2 (`BTN_TR2`) |
| Volume up / down | L2 / R2 (`BTN_TL2` / `BTN_TR2`) |

Per-key customization will live in the **companion APK** + config file (not implemented in v0.1 — mappings are compiled in `main.c`).

> **Shipped daemon:** the module that actually ships is `FlipMouseArcade` ([`../flipmouse-arcade/`](../flipmouse-arcade/)), a single daemon that covers gamepad, landscape cursor and portrait mouse. This directory is the earlier standalone gamepad (legacy, not installed). The key table above is common to both, except that the Arcade daemon decides the right-soft tap/hold split itself: tap → R1, hold → cursor.

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

**Verified on device (Astro Loop 1.5, landscape)** — `mode -> 1` in `/cache/FlipMouse.log`, real `mtk-kpd`/`matrix-keypad` grabbed, and a held D-pad press moves the game's menu selection (1668 px changed vs 58 px of rest noise).

### Input reliability (Arcade daemon, 2026-11-14)

Symptom: buttons occasionally needed two presses, or a press did nothing at all. Three separate causes, all in the event loop:

| Cause | Fix |
|-------|-----|
| The daemon re-adopted its **own** pass-through uinput clone on restart. A clone whose creator had died stays `select()`-readable forever without producing an event, so the loop spun on `ERROR: Failed to read event` and starved the real keypads | Resolve each node's `/sys/class/input/*/device` target and skip anything under `/devices/virtual/`; one device per name; `O_NONBLOCK` |
| One `read()` per wakeup left the rest of a burst queued, so a D-pad press plus a button arrived a wakeup late | Drain the whole queue per wakeup; drop a device whose read really fails and rebuild the `fd_set` |
| Two `dumpsys window displays` calls per 1.5 s poll (~100–160 ms each) stalled the loop, and an unbounded `select()` meant the poll only ran *after* the next key arrived | One cached probe per cycle; `select()` always bounded by the next poll deadline (this closes the old "first press after rotating is swallowed" note) |

Verified: `/proc/<pid>/fd` shows only `event1`/`event2` plus `/dev/uinput`, and CPU ticks stay flat (~1 tick per 3 s). The right-soft tap path was proven end-to-end with a uinput fake keypad: `right soft tap: BTN_TR (R1)` in the log, `BTN_TR` on the virtual gamepad. Note that a rotated physical **Right** still maps to screen *up* — Astro Loop's hangar carousel only steps on screen left/right, so Right does nothing on that menu by design.

### Numpad dead on every key (2026-11-14)

Symptom: none of the numpad directions did anything in game, right included.

`InputRouter.onMotion` calls `getAxisValue` on `0`/`1` (`AXIS_X`/`AXIS_Y`), `15`/`16` (`AXIS_HAT_X`/`AXIS_HAT_Y`) and the triggers `17`/`18`/`22`/`23`. It never reads `25`/`26` (`AXIS_RX`/`AXIS_RY`). The numpad was a **separate** direction set that wrote only `ABS_RX`/`ABS_RY`, so its output went to an axis no Astro Loop code path touches. Two further faults: key **6** had no `case` at all (`NPAD_BIT_6` did not exist), and the numpad was rotated the *opposite* way to the D-pad (`8`→right, `2`→left), so it would have felt inverted the moment it started working.

The numpad now ORs into the same rotated direction set as the D-pad and writes `ABS_X`/`ABS_Y` + `ABS_HAT0X`/`ABS_HAT0Y` at full scale. Verified with a uinput fake keypad emitting `2/8/4/6/1` and `getevent` on the virtual pad:

| Key | Emitted |
|-----|---------|
| `2` | `ABS_X` −32767, `HAT0X` −32767 |
| `8` | `ABS_X` +32767, `HAT0X` +32767 |
| `4` | `ABS_Y` +32767, `HAT0Y` +32767 |
| `6` | `ABS_Y` −32767, `HAT0Y` −32767 |
| `1` | both axes in one report |
