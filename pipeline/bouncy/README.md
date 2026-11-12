# Vector Pinball (Bouncy) on Flip 2

[Vector Pinball](https://f-droid.org/packages/com.dozingcatsoftware.bouncy/) (`com.dozingcatsoftware.bouncy`) v43 (1.16.0) is a demo pinball game on the Flip2 stack. The **Flip 2 patch** adds hardware flipper controls and an optional unlimited-mode score reset. **Left and right are never swapped** — left-side keys always drive the left flipper; right-side keys drive the right flipper.

## Flipper mapping (fixed — never swapped)

| Physical control | Key code | Flipper |
|------------------|----------|---------|
| D-pad **left** | 21 (`DPAD_LEFT`) | **Left** (upstream) |
| D-pad **right** | 22 (`DPAD_RIGHT`) | **Right** (upstream) |
| Upper-left soft key | **`KEYCODE_SOFT_LEFT` (1)** — kernel 139 in `matrix-keypad.kl` | **Left** (patch) |
| Right soft key | **`KEYCODE_SOFT_RIGHT` (2)** — kernel 48 in `matrix-keypad.kl` | **Right** (patch) |

Apps receive Android `KeyEvent` keycodes from `.kl`, not raw evdev scan codes. Upstream already maps Z, `/`, L1, R1, Space, Enter, and D-pad center. With **Flip2Gamepad** in landscape, L1/R1 align with the same physical keys; this patch does not remap or invert sides.

**Cursor toggle:** Holding upper-left soft ~1s normally enables FlipMouse cursor mode. Bouncy sets `image_policy.block_cursor_hold: true` in `pipeline/deploy/manifest.json`; installer / first-boot emit writes `block_cursor_toggle_packages=com.dozingcatsoftware.bouncy` into `/data/local/flip2/gamepad.conf`. FlipMouse / FlipMouseArcade skips cursor holds while that package is focused. Add the same flag on other game components — no daemon rebuild.

Touch flippers and **Independent Flippers** preference behave as stock.

## Unlimited balls — reset score each ball

Settings → **Reset score each ball (unlimited mode)** (`flip2_reset_score_unlimited`, default **off**).

When **Unlimited Balls** is checked on the start screen **and** this preference is on, score is set to **0** each time a new ball is launched. With the pref off, score accumulates across balls (stock unlimited behavior).

## Install

```sh
flip2 bouncy patch --no-install   # build signed APK only
flip2 bouncy install              # patch + adb install (default)
flip2 bouncy install --fdroid     # stock F-Droid build only
```

Patched APK is signed with the **debug keystore** (same as astro-loop). Uninstall the F-Droid build first if you see a signature clash:

```sh
adb uninstall com.dozingcatsoftware.bouncy
flip2 bouncy install
```

## Release (wizard / installer / menu slot 9)

```sh
flip2 bouncy patch --no-install   # if needed
flip2 bouncy release              # copy signed APK → pipeline/deploy/sources/
```

Then regenerate pins if SHA changed (`jq` per `wizard/pins.README.md`) and `pipeline/wizard/gen-pipeline-js.sh`.

## Pin (catalog)

- **Shipped:** `pipeline/deploy/sources/com.dozingcatsoftware.bouncy_43.apk` (patched, debug-signed)
- **SHA-256:** `f4097f3b4906145c671dbdf34bf3fbe3d75fce49e8998e5ba72458c84668f66e`
- **Patch base:** `pipeline/deploy/sources/com.dozingcatsoftware.bouncy_43-fdroid.apk` (stock F-Droid v43)

Wizard catalog has **no public URL** for bouncy (patched bytes must match pin — use installer bundle, local pick, or WebUSB push).

## Patch contents

- `bouncy-43-flip2-controls.patch` — `FieldViewManager` key lists, `launchBallIfNeeded` score reset, prefs UI
- `patch-bouncy.sh` — apktool decode (full, for `res/xml`), patch, build, zipalign, apksigner

Upstream: https://github.com/dozingcat/Vector-Pinball (GPL-3.0).
