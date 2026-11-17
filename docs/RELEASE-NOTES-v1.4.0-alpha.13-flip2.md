# flip2 toolkit v1.4.0-alpha.13-flip2

## Highlights

- **FlipMouse Arcade — landscape gamepad rotation + Back** — Shared `keypad_dirs_to_stick` / `keypad_keycode_to_rel` for stick, landscape cursor, and SDL pointer; orientation changes clear held directions; `landscape_probe()` scoped to display 0; default short **Back** → Android `KEY_BACK` (`back_short=android`, legacy `back_short=start`).
- **ScummVM SDL pointer — numpad cross** — Numpad **2/4/6/8** and diagonals move the cursor (same rotation as D-pad); **5** / **0** = left / right click under thumb; landscape SDL uses **90° CCW** (not portrait-only mapping).

## Verify downloads

```sh
cd pipeline/deploy/dist
sha256sum -c SHA256SUMS
```

## Release assets

Magisk installers repacked at `1.4.0-alpha.13-flip2`; FlipMouse Arcade zip in component bundle. Companion AppImage `1.4.0-alpha.13` when packed.
