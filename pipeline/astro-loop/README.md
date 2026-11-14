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

`astro-loop-1.5-flip2-display.patch` makes the stock build usable on the Flip 2:

| Change | Why |
|--------|-----|
| `GameConfig.DESIGN_HEIGHT` 2142 → 960 | Stock design is a 960×2142 portrait column; on a 321×428 panel `renderScale = min(w/960, h/2142)` collapses to ≈0.2, so the UI is tiny and pinned to the top |
| `DesignSpace.designHeight()` portrait 2142 → 960, landscape 960 → 720 | Matches the new design rect in both shapes |
| `DesignSpace.designWidth()` landscape 2142 → 960 | Landscape design rect becomes 960×720 (4:3), so it fills 428×321 instead of letterboxing |
| `HangarSurfaceView.setCabinetOrientationLock$lambda$5` `FULL_USER` (13) → `LOCKED` (14) | Leaving a cabinet requested "follow the device", which resolves to portrait on this panel and silently undid the manifest lock |
| `RoomAnchor.anchorX` always takes the centred branch | Landscape used to right-align page 0 and flush-left page 2, so the bar room and the subject sat right of centre on the 428-wide panel |
| `InputRouter.onKey` treats `0x6a` (`BTN_THUMBL`) as activate | FlipMouse Arcade's virtual gamepad emits `BTN_THUMBL` for keypad OK; stock only accepted `DPAD_CENTER`/`ENTER`, so OK did nothing in landscape |
| `android:screenOrientation` → `landscape` | Manifest lock, written by the build script (not a patch hunk — apktool emits one long XML line) |

The build script verifies the orientation rewrite actually landed; `apktool d -r` leaves a *binary* `AndroidManifest.xml`, and `sed` exits 0 matching nothing — that shipped a still-portrait build once.

Opening composition is verified on the 428×321 panel: the subject sits at x213.5 against a panel centre of 214.0. The playfield band itself is authored geometry (`walkwayY = 0.6 × height`, `ceilingY = walkwayY − 80`), so it reads as a horizontal slice with starfield above — that is upstream's composition, not a scaling artefact; tune only if it bothers us in play.

Still open:

- Remap TCL-specific keycodes if the daemon is not running (raw DPAD_* keys are accepted today)
- Default to directional mode on first launch

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
