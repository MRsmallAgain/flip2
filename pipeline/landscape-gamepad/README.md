# Landscape gamepad companion (Flip 2)

When the display is in **landscape** (horizontal games), the physical keypad is sideways. **Flip2Gamepad** (Magisk) grabs the matrix keypad (+ volume on `mtk-kpd`) and exposes a **virtual uinput gamepad** with your rotated D-pad and dual-stick layout.

## Activation

| Source | Config key | Behavior |
|--------|------------|----------|
| Landscape | `landscape_auto=1` (default) | Active when `dumpsys window displays` shows `rotation=1` or `3` |
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
| Left | Move **up** (−Y) |
| Right | Move **down** (+Y) |

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

**v0.1 scaffold** — landscape detection via `dumpsys` poll (~1.5s). Untested on device for game compatibility. Astro Loop portrait patch locks portrait; use games that allow landscape or manual `enabled=1` for horizontal titles.
