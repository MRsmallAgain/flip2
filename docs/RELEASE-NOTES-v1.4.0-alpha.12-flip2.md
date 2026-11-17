# flip2 toolkit v1.4.0-alpha.12-flip2

## Highlights

- **FlipMouse Arcade — ScummVM in landscape** — `portrait_sdl_pointer_packages` stay in SDL mouse mode when the display is landscape (cursor, OK left click, right-soft right click). Fixes landscape gamepad stealing ScummVM input.
- **Landscape D-pad → cursor** — `mouse_keypad_to_rel()` applies the same 90° CCW map as landscape gamepad for SDL pointer and landscape cursor; step magnitude is always positive (fixes inverted-axis runaway off-screen).

## Verify downloads

```sh
cd pipeline/deploy/dist
sha256sum -c SHA256SUMS
```

## Release assets

Magisk installers repacked at `1.4.0-alpha.12-flip2`; FlipMouse Arcade zip in component bundle. Companion AppImage `1.4.0-alpha.12`.
