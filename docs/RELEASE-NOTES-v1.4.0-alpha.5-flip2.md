# flip2 toolkit v1.4.0-alpha.5-flip2

## Highlights

- **The cursor is half as fast by default.** `FLIPMOUSE_DEFAULT_SPEED` went from `39` to `20`. On a 240x320 panel `39` overshot small UI targets — ScummVM's launcher buttons were the clearest case, where a single D-pad nudge could jump two or three buttons. `20` was tuned by hand on the 4058G (volume-down in mouse mode, one step per press) and is the new shipped default.
- **No new features.** This is a tuning release; every component except FlipMouse is unchanged from v1.4.0-alpha.4-flip2.

## FlipMouse (`1.4.1-flip2` -> `1.4.2-flip2`)

`FLIPMOUSE_DEFAULT_SPEED` is only a *fallback* — it is used when
`/data/local/flip2/flipmouse-speed` does not exist, or holds something below
`MIN_MOUSE_SPEED`. It had to change in three places, because any one of them
alone leaves a `39` in a path:

| File | Why it matters |
|------|----------------|
| `pipeline/flipmouse/main.c` | The mouse daemon's compiled fallback |
| `pipeline/flipmouse-arcade/main.c` | The arcade daemon's compiled fallback |
| `pipeline/image/build-tree.sh` | Bakes the seed into `first-boot.sh`, which is what a fresh image actually writes |

The speed file persists across reboots, and pressing volume-down/volume-up in
mouse mode writes it back immediately, so this only affects a *fresh* install
(or a reflash). Devices already tuned keep their value.

## FlipMouse Arcade (`0.3.0-flip2` -> `0.3.1-flip2`)

Same one-line default change; no behaviour changes to the gamepad, the
landscape rotation, or the trigger axes.

## Verify downloads

```sh
cd pipeline/deploy/dist
sha256sum -c SHA256SUMS
```

## Release assets

| Asset | Tier |
|-------|------|
| flip2-installer-base-magisk.zip | B - wizard Base (FlipMouse, no Arcade/Astro Loop) |
| flip2-installer-full-magisk.zip | B - full stack + Sherpa voices in installer |
| flip2-installer-slim-magisk.zip | B - full without bundled Sherpa |
| flip2-installer-clean-magisk.zip | B - reduced APK/module set |
| flip2-installer-image-post-magisk.zip | B - after image merge / first-boot |
| flip2-packages-1.4.0-alpha.5-flip2.zip | D - per-component zips + APKs + inner SHA256SUMS |
| flip2-system-tree-1.4.0-alpha.5-flip2.zip | A - system/product merge tree |
| SHA256SUMS | sums for the seven files above |

All assets are published as links to `https://flip2burn.online/packages/<name>`.

## Install

1. Root with **neutron.img** (catalog pin) after bootloader unlock. Unlocking **erases the phone**.
2. Magisk -> Install from storage -> **`flip2-installer-full-magisk.zip`** for a conservative first install (or `base` to match the wizard's Base profile).
3. Reboot; check `/cache/flip2-installer.log`. The de-root helper lands at `/data/local/flip2/deroot.sh`.
4. For a slower cursor without reflashing: in mouse mode press volume-down (one step each), or set `/data/local/flip2/flipmouse-speed` and bounce the daemon with `su -c 'kill $(pidof mouse)'`.

## Not included

- **Forkgram** stays a separate GPL release (`flip2-13.0.2.0-r1`); the full installer downloads it at install time.
- **Sherpa-ONNX** tarballs (EN + UK) are not bundled in the zip - fetch via the wizard catalog or `flip2 ime sherpa` / `--sherpa-url` on pack.
