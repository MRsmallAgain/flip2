# Image tiers: what bakes vs what flashes after

The **base** wizard profile is split across three delivery layers so you flash once into `super`, then run small post-flash steps instead of reinstalling everything via Magisk modules.

## One command on the host

```bash
flip2 image prepare [--with-sherpa-urls] [--skip-flipmouse-system]
```

Produces:

| Output | Role |
|--------|------|
| `dist/flip2-system-tree/` | Merge into **your** stock `system/` + `product/` (Tier A) |
| `dist/flip2-installer-image-post-magisk.zip` | One-shot Magisk zip after first boot (Tier B slim) |
| `dist/flip2-image-kit/` | Copy of tree + zip + `IMAGE-FLASH-STEPS.txt` |

We **do not** ship TCL `super.img` or merge it for you — that stays on your dump + `lpunpack`/`lpmake`. See [IMAGE-BUILD.md](IMAGE-BUILD.md).

## Tier A — baked into `super` (manifest `"image"`)

| Component | In tree |
|-----------|---------|
| navoverlay, launcher_overlay | `product/overlay/*.apk` |
| keypad | `system/usr/keylayout/matrix-keypad.kl` |
| tagdrawer | `system/app/PixelTagDrawer/` |
| launcher4, Null Keyboard | `system/app/Launcher4/`, `Flip2NullKeyboard/` |
| AppShelf, F-Droid Basic, NewPipe, VLC, Intertune, Bouncy | `system/app/*` via `image_preload` + `flip2 source fetch` |
| flipmouse (optional) | `system/bin/flip2-mouse`, `system/etc/init/` when `flip2 flipmouse build-system` ran |
| wallpaper asset | `system/media/flip2-wallpaper.png` |
| settings you cannot “file-bake” | **`first-boot.sh`** at tree root: home keys, 321×428, wallpaper → `/data`, `.image-tier` stamp, IME settings + HOME |

After merge + flash, run **`first-boot.sh`** once as root (before or instead of duplicating those steps in image-post — image-post still sets HOME/IME if you skip first-boot, but first-boot is the canonical image path).

## Tier B — post-flash only (cannot or should not package in `super`)

| Item | Why | How |
|------|-----|-----|
| **Forkgram**, **Material Files** | GPL / not in repo; policy | **image-post** zip downloads at install (Wi‑Fi) |
| **Sherpa STT** | Large ONNX tarballs | `flip2 ime sherpa`, wizard push, or `--with-sherpa-urls` on prepare |
| **neutron.img** | Boot partition, wipe-gated | Separate `fastboot flash boot` (wizard rooting slice) |
| **Magisk full modules** | Redundant after Tier A | Use **`image-post`**, not **`full`**, on a Tier A device |

## Tier B flavors

| Flavor | When |
|--------|------|
| **full** | Stock `super`, Magisk-only path (modules + user APKs) |
| **clean** | User APKs + settings, no modules |
| **image-post** | After Tier A flash: GPL sideloads + IME tuning + `deroot.sh`; skips system preloads |

## Base profile mapping

| Profile component | Tier A tree | image-post / other |
|-----------------|-------------|-------------------|
| navoverlay, keypad, tagdrawer, launcher_overlay, flipmouse | ✓ (mouse optional init) | skip modules |
| launcher4, ime, intertune, bouncy, appshelf, fdroid_basic, newpipe, vlc | ✓ system apps | skip APK install |
| home_keys, display, wallpaper | ✓ first-boot.sh | omitted from zip payload |
| forkgram, materialfiles | — | ✓ download |
| sherpa-en, sherpa-uk | — | optional URLs or manual push |
| headwind, where | — | managed profile only |

## Related docs

- [IMAGE-BUILD.md](IMAGE-BUILD.md) — merge, fastbootd, recovery
- [SHERPA-STT.md](SHERPA-STT.md) — dictation models
- [FLIPMOUSE-SYSTEM.md](FLIPMOUSE-SYSTEM.md) — system-domain mouse
