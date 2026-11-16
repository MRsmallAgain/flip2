# flip2 toolkit v1.4.0-alpha.6-flip2

## Highlights

- **Wizard Device section** — sideload and phone control from the setup wizard (`feature/wizard-device-section`).
- **Portrait SDL pointer (ScummVM)** — `portrait_sdl_pointer_packages` auto-mouse with a separate SDL step profile (80/32 ms, half first tap, debounced OK). Homescreen cursor stays speed 20 at 200/50 ms. Documented in [docs/FLIPMOUSE-ARCADE.md](FLIPMOUSE-ARCADE.md).
- **Launcher input** — deferred `dumpsys` poll (after keypad drain) and skip full `dumpsys window` when `ResumedActivity` already names the foreground app (fixes periodic homescreen hang).
- **Cursor speed** — **Star + Vol up/down** adjusts speed in all mouse modes; plain volume passes through so games are not bumped accidentally.

## FlipMouse Arcade (`0.3.1-flip2` → `0.3.2-flip2`)

- `image_policy.portrait_sdl_pointer` emit/first-boot/installer merge; stale bypass migration off SDL packages.
- Passive mode mutes keys (no double-fire). Null IME `SDL_POINTER_PACKAGES` passthrough.
- Star+Vol speed chord; poll deferral and launcher foreground fast path.

## Verify downloads

```sh
cd pipeline/deploy/dist
sha256sum -c SHA256SUMS
```

## Release assets

Same asset set as v1.4.0-alpha.5-flip2 with versioned bundle names `1.4.0-alpha.6-flip2`. Pack installers after merge, then `flip2 release --notes docs/RELEASE-NOTES-v1.4.0-alpha.6-flip2.md`.
