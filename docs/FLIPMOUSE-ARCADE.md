# FlipMouse Arcade — gesture card

Shipped module: **`FlipMouseArcade`** (`flip2 flipmouse-arcade build|install`). Config: `/data/local/flip2/gamepad.conf`.

## Rule of thumb

| Soft key | Role |
|----------|------|
| **Left (139)** | Hold ≥1 s, then release, to toggle input mode. Star exits manual mouse and landscape cursor; it does not enter them |
| **Right (48)** | Game **R1** in landscape gamepad (tap), or **Shortcuts** when passed through — **never** a cursor toggle |

Star (522) exits manual portrait mouse and landscape cursor. A portrait SDL pointer app stays in auto-mouse while it is the foreground package.

## Modes

| Mode | When | Left soft hold ≥1 s | Right soft |
|------|------|---------------------|------------|
| **Passive** | `landscape_auto=0` and `enabled=0`, or idle | Portrait **mouse** | Shortcuts |
| **Portrait mouse** | After passive toggle (`mouse_manual`) | Back to passive | Shortcuts |
| **Portrait SDL pointer** | Portrait + foreground package in `portrait_sdl_pointer_packages` | Not a toggle. Leaving the app returns the launcher to the D-pad | Shortcuts |
| **Landscape gamepad** | Landscape + `landscape_auto=1`, or portrait app in `portrait_gamepad_packages` | **Landscape cursor** (unless blocklisted) | Tap = R1 |
| **Landscape cursor** | After gamepad toggle (landscape) | Back to gamepad | Pass through |

Short left tap in **gamepad** mode: **L1** (`BTN_TL`) pulse, not a mode change. Short left tap in portrait mouse (homescreen or an SDL pointer app) scrolls up one wheel step.

`mode_wanted()` order: `mouse_manual`, then landscape-cursor override, then the portrait SDL pointer list, then manual gamepad or `landscape_auto` in landscape, then the portrait gamepad list, then passive. Portrait SDL auto-mouse does not set `mouse_manual`.

Passive returns mute. The key already reached the app on the real node; re-injecting it on the matrix clone double-fires.

## `gamepad.conf` keys

```ini
landscape_auto=1
enabled=0
# Comma-separated package names (no spaces):
# block_cursor_toggle_packages=com.dozingcatsoftware.bouncy
# portrait_gamepad_packages=com.shatteredpixel.shatteredpixeldungeon
# portrait_sdl_pointer_packages=org.scummvm.scummvm
```

| Key | Effect |
|-----|--------|
| `landscape_auto=1` | Grab keypad in landscape → virtual gamepad |
| `enabled=1` | Force gamepad even in portrait (testing) |
| `block_cursor_toggle_packages` | In **landscape gamepad** only: left-soft hold does **not** switch to landscape cursor (pinball). **Portrait mouse** from passive always works |
| `portrait_gamepad_packages` | Virtual gamepad in **portrait** with standard Up/Down/Left/Right stick mapping (not 90° CCW) |
| `portrait_sdl_pointer_packages` | Portrait software-cursor apps. Auto mouse with the SDL step profile below while that package is foreground. Does not stick after you leave |
| `native_keypad_bypass_packages` | While that app is foreground, Arcade closes matrix-keypad and mtk-kpd so it stops reading physical keys, then reattaches when you leave. For apps that need the raw keypad. Keep portrait SDL pointer packages off this list. `sync_keypad_bypass()` also refuses to detach while one of them is foreground |

The Magisk `service.sh` seed writes `gamepad.conf` only when the file is missing. Installing Arcade does not rewrite a live conf.

`deploy/emit.sh` and the installer write the four package-list keys from `manifest.json` `image_policy`. `emit-first-boot.sh` does the same for image and full tiers, and strips any portrait-SDL package out of a stale bypass line.

## Cursor profiles

Two profiles. Homescreen left-soft mouse was verified on ONTK (`ONTKKB9L7PEUX4Z5`) on 2026-11-15 and stays the default. The SDL profile applies only to `portrait_sdl_pointer_packages`. Tuning one must leave the other alone.

### Homescreen / manual portrait mouse

| | |
|--|--|
| How it turns on | Left soft (139) hold ≥ 1 s from passive. Sets `mouse_manual` |
| Speed | **20** (`FLIPMOUSE_DEFAULT_SPEED`, file `/data/local/flip2/flipmouse-speed`) |
| First tap | full `mouse.speed` REL |
| Repeat | **200 ms** delay, then every **50 ms** |
| OK | one `BTN_LEFT` press (value forced to 1); the key release is swallowed |
| Star | release exits manual mouse; **hold Star + Vol up/down** adjusts cursor speed |
| Vol alone (mouse) | pass through to the system (no accidental speed change in ScummVM etc.) |

The speed file is read at daemon start. **Star + Vol up** / **Star + Vol down** change live speed and write `/data/local/flip2/flipmouse-speed` (all portrait/landscape mouse modes, including ScummVM SDL auto-mouse). Plain volume keys pass through while the cursor is grabbed. Repeat timing is compiled into the Arcade binary.

Base FlipMouse (`pipeline/flipmouse`, the other daemon) is still 400 ms / 100 ms. Leave those defines there.

### Portrait SDL pointer

Active when wanted mode is mouse and the foreground app is in `portrait_sdl_pointer_packages` (portrait only). ONTK-verified 2026-11-15 on ScummVM.

| | |
|--|--|
| Repeat step | `max(1, speed / 3)`. Speed 20 → **6** |
| First tap | half of that step. Speed 20 → **3** |
| Repeat | **80 ms** delay, then every **32 ms** |
| OK | `BTN_LEFT` press and release on the virtual mouse, muted key, **280 ms** debounce |
| After you leave | `mouse_manual` stays clear, so the launcher is a D-pad again |
| Poll | **4000 ms** while that app is foreground, otherwise **1500 ms** |
| Held direction | Skip the dumpsys poll. `select()` does not wake for an overdue poll. With no repeat deadline, sleep **50 ms** |

A 1-pixel negative half step truncates to 0 in integer division. At speed 20 the half step is 3 either sign. Leave that truncation alone.

Speed changes use the same **Star + Vol** combo as homescreen mouse; plain volume passes through.

Star release calls `mouse_deactivate()`, which clears `mouse_manual`. While the package is still foreground, `mode_wanted()` returns mouse again, so the cursor stays. BACK is passed through on the matrix clone (ScummVM uses it to skip the opening movie).

Foreground cache, once per poll: the first `ResumedActivity` / `topResumedActivity` line. If that line is empty, a non-null `mCurrentFocus` line that names a portrait SDL pointer package is the fallback. The key path reads the cache and does not call `popen`.

## Add another portrait SDL app

1. On the component in `pipeline/deploy/manifest.json`, set `image_policy.portrait_sdl_pointer` to `true`. The tier has to be one the emitter includes (`full` or `wizard` for the installer; `image` or `full` for first-boot).
2. Leave `native_keypad_bypass` unset. Bypass detaches the keypad, so Arcade cannot inject REL.
3. A new package does not need an Arcade rebuild. Add it to `portrait_sdl_pointer_packages` (comma-separated, no spaces) and the next poll picks it up, or regenerate first-boot and flash.
4. If the app binds Flip2 Null Keyboard and still needs D-pad, OK, BACK, or Star delivered to the activity, add the same package to `SDL_POINTER_PACKAGES` in `NullKeyboardService.java` and reinstall the IME. The IME does not read `gamepad.conf`. Launcher DecorView and SystemUI are `TYPE_NULL` and stay off that list.
5. Rebuild Arcade only when the step profile or the mode rules change (`pipeline/flipmouse-arcade/build.sh`, then `install.sh`).

## ScummVM

`org.scummvm.scummvm` is the first portrait SDL pointer package. Its launcher is a software cursor, and injected REL moves it. The in-app Direct mouse control is a touch setting; Flip2 injects a REL mouse.

Game data, `scummvm.ini`, and scaling: memory `project-flip2-scummvm`.

Landscape play uses the normal `landscape_auto` gamepad. The blocklist is for Bouncy-style pinball only.

`./build.sh --debug` logs keypad detach/reattach to `/cache/FlipMouse.log`.

## Shattered Pixel Dungeon (portrait)

Set `portrait_gamepad_packages=com.shatteredpixel.shatteredpixeldungeon`. D-pad / numpad cross map to `AXIS_X`/`AXIS_Y`; **5** = `BTN_SOUTH`. Expect `mode -> 1` and `portrait_gp=1` in `/cache/FlipMouseArcade.log` when the app is foreground.

## Landscape stick rotation

In **landscape** gamepad, D-pad and numpad use **90° CCW** mapping (phone top to your left). In **portrait gamepad** profile, mapping is **standard** (Up = −Y, etc.). Details: [landscape-gamepad README](../pipeline/landscape-gamepad/README.md).

## Commands

```bash
flip2 flipmouse-arcade build
flip2 flipmouse-arcade install   # needs authorized adb + Magisk
flip2 flipmouse-arcade status
flip2 flipmouse-arcade rollback
```

Log: `/cache/FlipMouseArcade.log` (and legacy `/cache/FlipMouse.log` on some builds).

## Related

- [FLIPMOUSE-SYSTEM.md](FLIPMOUSE-SYSTEM.md) — base FlipMouse (passive + portrait mouse only)
- [pipeline/flipmouse/VENDORED.md](../pipeline/flipmouse/VENDORED.md) — upstream toggle semantics
