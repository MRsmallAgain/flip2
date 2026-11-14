# flip2 toolkit v1.4.0-alpha.4-flip2

## Highlights

- **Astro Loop is playable on the Flip 2.** The stock F-Droid build drew a 960×2142 portrait column, which on a 321×428 panel collapsed to ≈0.2 scale — tiny, pinned to the top half. `flip2 astro-loop patch` now ships a display patch (960 design height, 960×720 landscape design rect, room centred, manifest locked to landscape) and rebuilds the APK.
- **The landscape gamepad was mostly broken, and is now verified.** Three separate input faults plus two wrong mappings were fixed; every mapping in this release was proven on device with a uinput fake keypad and `getevent` on the virtual pad, not inferred.
- **FlipMouse Arcade 0.3.0:** `5` is the primary button, `#` is the right trigger, and triggers are emitted as **axes** so games that read `AXIS_BRAKE`/`AXIS_GAS` see them.

## FlipMouse Arcade (`0.2.0-flip2` → `0.3.0-flip2`)

### Buttons that needed two presses

Three independent faults in the daemon's event loop, all of which could swallow or delay a key:

| Cause | Fix |
|-------|-----|
| The daemon re-adopted **its own** pass-through uinput clone on restart. A clone whose creator died stays `select()`-readable forever without producing an event, so the loop spun on read errors and starved the real keypads | Resolve each node's sysfs backing and skip `/devices/virtual/`; one device per name; `O_NONBLOCK` |
| One `read()` per wakeup left the rest of a burst queued, so a second press arrived a wakeup late | Drain the whole queue per wakeup; drop a device whose read really fails and rebuild the `fd_set` |
| Two `dumpsys window displays` calls per 1.5 s poll (~100–160 ms each) stalled the loop inside the key path, and an unbounded `select()` meant the poll only ran *after* the next key arrived | One cached probe per cycle; `select()` always bounded by the next poll deadline |

This also closes the long-standing "first press after rotating is swallowed" note.

### D-pad and numpad

- The landscape cross is a **true 90° CCW rotation**: physical Up→screen left, Down→right, Left→down, Right→up. The earlier mapping was the diagonal mirror, which left Up/Down right but made up/down feel inverted.
- The **numpad cluster did nothing at all**. It wrote only `ABS_RX`/`ABS_RY`, and Astro Loop reads `AXIS_X`/`AXIS_Y` and `AXIS_HAT_X`/`AXIS_HAT_Y` — never the right stick. Key `6` also had no `case`. The numpad now ORs into the same rotated direction set as the D-pad and keeps its diagonals (`1/3/7/9`).
- Both crosses use held-key bitmasks, so two directions can be held at once and releasing one does not drop the other.

### Buttons and triggers

| Key | Gamepad |
|-----|---------|
| `5` | A — `BTN_SOUTH` (primary action) |
| `0` | B — `BTN_EAST` |
| `*` | X — `BTN_NORTH` |
| OK | Select — `BTN_THUMBL` |
| `#` | RT — `BTN_TR2` **and** `ABS_GAS` |
| Messenger, Vol-down | RT — `BTN_TR2` + `ABS_GAS` |
| Vol-up | LT — `BTN_TL2` + `ABS_BRAKE` |
| Upper-left soft | L1 — `BTN_TL` |
| Right soft, tap | R1 — `BTN_TR` (emitted on release) |
| Right soft, hold ≥1 s | landscape cursor |
| Back, short tap | Start — `BTN_START` |
| Back, hold ≥2 s | real Android Back |

- `5` used to be swallowed as the numpad's neutral key — a no-op on the most reachable key in the cluster — while A sat on `#` in the corner. They are swapped, and `5` left the movement cross.
- **Triggers are axes.** Astro Loop computes `max(AXIS_LTRIGGER, AXIS_BRAKE)` / `max(AXIS_RTRIGGER, AXIS_GAS)` and latches above 0.6; it never looks at `BTN_TL2`/`BTN_TR2`. Each trigger key emits both the button and the axis, so either convention works. The axes are declared **`0..32767`, not the sticks' symmetric range** — a released `0` on a symmetric axis normalises to 0.5, just under the 0.6 latch, and the trigger would read as half-held forever.
- Each trigger tracks a **set** of held keys, because three physical keys drive RT; releasing one does not drop the trigger while another is down.

## Astro Loop

`flip2 astro-loop patch [--orientation portrait|landscape]` downloads the pinned F-Droid v1.5 APK, applies `astro-loop-1.5-flip2-display.patch`, rebuilds, and installs.

| Change | Why |
|--------|-----|
| `GameConfig.DESIGN_HEIGHT` 2142 → 960 | `renderScale = min(w/960, h/2142)` collapsed to ≈0.2 on this panel |
| `DesignSpace` portrait 2142 → 960, landscape 960 → 720 | Matches the new design rect in both shapes |
| `DesignSpace.designWidth()` landscape 2142 → 960 | Landscape design rect becomes 960×720, filling 428×321 instead of letterboxing |
| `setCabinetOrientationLock` `FULL_USER` → `LOCKED` | Leaving a cabinet requested "follow the device", which resolves to portrait and undid the manifest lock |
| `RoomAnchor.anchorX` always centred | Landscape right-aligned page 0 and flush-left page 2 |
| `InputRouter.onKey` accepts `0x6a` (`BTN_THUMBL`) as activate | The virtual pad's OK did nothing in landscape |
| `android:screenOrientation` → `landscape` | Written by the build script, which verifies the rewrite landed |

The build script re-checks orientation because `apktool d -r` leaves a **binary** `AndroidManifest.xml` and `sed` exits 0 matching nothing — that shipped a still-portrait build once.

Opening composition is verified on 428×321: subject at x213.5 against a panel centre of 214.0.

## Verify downloads

```sh
cd pipeline/deploy/dist
sha256sum -c SHA256SUMS
```

## Release assets

| Asset | Tier |
|-------|------|
| flip2-installer-base-magisk.zip | B — wizard Base (FlipMouse, no Arcade/Astro Loop) |
| flip2-installer-full-magisk.zip | B — full stack + Sherpa voices in installer |
| flip2-installer-slim-magisk.zip | B — full without bundled Sherpa |
| flip2-installer-clean-magisk.zip | B — reduced APK/module set |
| flip2-installer-image-post-magisk.zip | B — after image merge / first-boot |
| flip2-packages-1.4.0-alpha.4-flip2.zip | D — per-component zips + APKs + inner SHA256SUMS |
| flip2-system-tree-1.4.0-alpha.4-flip2.zip | A — system/product merge tree |
| SHA256SUMS | sums for the seven files above |

All assets are published as links to `https://flip2burn.online/packages/<name>`.

## Install

1. Root with **neutron.img** (catalog pin) after bootloader unlock. Unlocking **erases the phone**.
2. Magisk → Install from storage → **`flip2-installer-full-magisk.zip`** for a conservative first install (or `base` to match the wizard's Base profile).
3. Reboot; check `/cache/flip2-installer.log`. The de-root helper lands at `/data/local/flip2/deroot.sh`.
4. For Astro Loop: `flip2 astro-loop patch` with the phone connected. Stock `install` still works but the UI is tiny.
