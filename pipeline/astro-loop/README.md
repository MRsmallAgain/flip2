# Astro Loop on Flip 2

[Astro Loop](https://f-droid.org/packages/com.astroloop.game/) (`com.astroloop.game`) is an open-source roguelike shooter (PubDeer, GPLv3). The F-Droid build is **pure Kotlin on Canvas** — no native `.so` libraries — so it installs on the Flip 2 (4058G, armeabi-v7a / 32-bit ARM) without ABI patches.

## Flip 2 platform fit

| Concern | Status |
|--------|--------|
| **ABI** | No JNI libs; runs on 32-bit ARM |
| **Display** | Logical **321×428** (`display_size_forced`); game scales vector canvas |
| **D-pad / keypad** | Upstream **v1.5** ships `InputRouter`: `KEYCODE_DPAD_*`, hat axes, A/Enter = activate, B/Back = cancel, Start/X/Y = pause |
| **Touch** | Still works; directional mode switches when hardware keys arrive |
| **Network** | No internet permission (offline game) |

The physical Flip 2 keypad should emit standard Android DPAD keys once focus is in the game. **Verify on device** before assuming menu focus and combat steering feel right on the small panel.

## Patches (this branch)

There is **no smali patch** yet — upstream already targets gamepads and D-pads. Future Flip2-only work might include:

- Remap TCL-specific keycodes if DPAD is not reported
- Default to directional mode on first launch
- Smaller UI safe-area tweaks for 321×428

Track findings in this README when you add `astro-loop-*.patch`.

## Install

```sh
flip2 astro-loop install              # download F-Droid v6 (1.5), verify pin, adb install
flip2 astro-loop install --no-install # verify only
```

Or from the wizard catalog id **`astro-loop`** (`com.astroloop.game_6.apk`).

## Pin (catalog)

- **File:** `com.astroloop.game_6.apk`
- **versionCode:** 6, **versionName:** 1.5
- **URL:** https://f-droid.org/repo/com.astroloop.game_6.apk
- **SHA-256:** `79aa83482f64f7ae0bc245aa3550bc0e231fecdc046cb783b818917e418f6cf7`

After upstream bumps, re-download, `sha256sum`, update `wizard/catalog.json`, regenerate `wizard/pins.json`, and `pipeline/deploy/sources/`.

## Upstream

- Repo: https://github.com/PubDeer/astro-loop (read/build; upstream does not accept PRs)
- Issues welcome upstream for generic Android/controller bugs

Not affiliated with PubDeer; APK is fetched from F-Droid at install time (GPL).
