# Flip2 Launcher3 RRO overlay + in-browser editor

Static **Runtime Resource Overlay** for `com.android.launcher3` on TCL Gflip6 / Flip2 (Android 11). Menu grid **slots 1–9** come from **`slots.json`** (see repo root [README](../README.md) and [docs/PIPELINE.md](../docs/PIPELINE.md)).

## Quick start (pipeline)

```bash
export PATH="$HOME/.local/share/flip2/bin:$PATH"
adb devices

flip2 apply
flip2 slot 5 com.android.music
flip2 editor   # http://127.0.0.1:8765
```

Legacy: `./scripts/apply-slots.sh` → same as `flip2 apply`.

## Quick start (strings / pull reference)

```bash
cd ~/.local/share/flip2/launcher-overlay
./scripts/pull-launcher-strings.sh   # optional
flip2 editor
```

Edit `strings.xml` in the page → **Save to PC** → **Build + install (adb)** → **Restart launcher**.

## In-phone editing (Vivaldi on the phone)

The editor runs on your **Linux PC**; the phone reaches it through USB reverse port forwarding:

```bash
adb reverse tcp:8765 tcp:8765
./scripts/serve-editor.py   # on PC, keep running
```

On the phone, open Vivaldi: **http://127.0.0.1:8765** (same as localhost on device after reverse).

Save/build still runs **adb on the PC** (reverse only tunnels HTTP to the editor).

## Web console / remote shell (what you use today)

If you debug via a **browser shell on the device** (e.g. WebADB, OEM debug page, or a tab that runs `adb shell` remotely), use it for discovery; use this editor for overlay XML:

| On device (shell) | Purpose |
|-------------------|--------|
| `pm path com.android.launcher3` | APK path to pull |
| `cmd overlay list` | See enabled overlays |
| `cmd overlay enable --user 0 com.tim.flip2.launcheroverlay` | Enable after install |
| `am force-stop com.android.launcher3` | Apply resource changes |

Pull/install from **PC** when USB adb works:

```bash
./scripts/sign-and-install.sh
```

## Overlay limits

- **Works well:** `@string` overrides in `res/values/strings.xml` (names must match Launcher3 exactly).
- **Maybe:** `@bool` / `@integer` in `res/values/config.xml` if those names exist in Launcher3.
- **Hard:** app grid layout, which apps appear, key-driven “menu” structure → needs full Launcher3 fork or Magisk replace, not RRO alone.

## Install requirements

- **adb** + device authorized
- **apktool** — build overlay APK
- **apksigner** + **keytool** (Android build-tools) — sign with debug key
- **User-installed overlays** often need **root** or a **userdebug** build that allows `adb install` of overlay packages. If install fails, use a Magisk module that places the signed APK in `/product/overlay/` or `/vendor/overlay/` (after root/neutron boot).

## Fix wrong overlay target (Android 11)

If overlay does not apply after enable:

```bash
adb shell dumpsys package com.android.launcher3 | grep -i overlayable
aapt dump xmltree /product/priv-app/Launcher3/Launcher3.apk AndroidManifest.xml | grep -i overlay
```

Adjust `android:targetName` in `AndroidManifest.xml` to match the launcher’s `<overlayable android:name="...">` (sometimes omit `targetName` entirely).

## Example string override

After `pull-launcher-strings.sh`, pick a real name, e.g.:

```xml
<string name="all_apps_button_label">Apps</string>
```

(Use the exact `name` from stock Launcher3.)

## Files

| Path | Role |
|------|------|
| `AndroidManifest.xml` | RRO manifest |
| `res/values/strings.xml` | Labels + `def_appmenu_position_five` (package name) |
| `res/values/bools.xml` | TCL menu/tool toggles (`def_toolsshow_*`, etc.) |
| `scripts/serve-editor.py` | Local web UI + adb API |
| `scripts/sign-and-install.sh` | Build, sign, install |
| `scripts/pack-magisk-module.sh` | Zip for Magisk → `dist/flip2_launcher_overlay-magisk.zip` |
| `scripts/after-root-enable.sh` | Try enable + restart launcher after root |
| `reference/tcl-overlay/` | Pulled stock `Launcher3-overlay.apk` for comparison |
| `www/index.html` | Editor (strings + bools) |

## Built-in menu (TCL fork)

Stock Launcher3 on Gflip6 includes TCL-only resources:

| Resource | Type | Effect |
|----------|------|--------|
| `def_appmenu_position_five` | string (package) | App in built-in menu slot 5 (stock: `com.android.music`; overlay default: `com.android.settings`) |
| `def_toolsshow_stk` / `vvm` / `rsuapk` | bool | Show/hide tools menu entries |
| `def_upkey_openmysite` | bool | Up-key behavior |

TCL’s enabled overlay is `com.android.launcher3.tct_overlay_product__` at `/product/overlay/Launcher3-overlay.apk`. Yours is `com.tim.flip2.launcheroverlay` (user install, **disabled** until root).

## After Magisk is installed

1. Boot flash is not on this branch. It lives on `feature/rooting-slice`. Do not unlock an already-rooted Flip 2 — that erases the phone. Upstream notes: [flip2 wiki](https://github.com/neutronscott/flip2/wiki).
2. Copy to phone: `adb push dist/flip2_launcher_overlay-magisk.zip /sdcard/Download/`
3. Magisk → Modules → Install from storage → select zip → **reboot**.
4. On PC: `scripts/after-root-enable.sh` (or enable in overlay list if still needed).
5. Edit at http://127.0.0.1:8765 → Save → Build + install, or repack Magisk and reboot.

Retail ROM blocks `adb shell cmd overlay enable` for Launcher3 (`SecurityException`). User-installed RRO stays `---` until Magisk product overlay or root enable.
