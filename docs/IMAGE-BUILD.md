# Building and flashing a flip2 base image (Tier A)

This is the **Tier A** path: bake the flip2 OSS set into *your own* stock
firmware as system/product files, so the components survive even with no
Magisk module. Everything else (FlipMouse, Forkgram, IME settings, Vosk
models) still comes from the Tier B installer zip after first boot.

**We do not distribute TCL firmware or boot images.** You dump your own
firmware; the root vector is [neutronscott's flip2
releases](https://github.com/neutronscott/flip2/releases) (`neutron.img` /
`neutron-noavb.img` — patched boot with Magisk baked in). See the
[flip2 wiki](https://github.com/neutronscott/flip2/wiki) for the fastboot
entry sequence (`autobooter-linux.py`, `mtk-bootseq.py`,
`~/flip2-enter-fastboot.sh`).

## 0. Warnings — read first

- **Never overwrite the 2048-byte EMMC_BOOT preloader header.** If the
  preloader is corrupted, the device will not enter boot ROM download mode
  and cannot be recovered by SP Flash Tool.
- **Back up `vbmeta`, `vbmeta_system`, `vbmeta_vendor` before flashing**
  anything (`fastboot fetch` under fastbootd, or the SP Flash Tool readback).
  If a flash goes wrong, restore vbmeta first.
- Have the [flip2 wiki](https://github.com/neutronscott/flip2/wiki) recovery
  notes at hand (`launcher-patch/EMERGENCY-unresponsive.md` in this repo).
- Do this on A/C power, with a good USB cable, and never interrupt a
  fastbootd write.

## 1. Get your stock firmware

Either:

- **SP Flash Tool readback** of your own device (full `super` + boot), or
- a TCL update package you downloaded for *your* device, unpacked with the
  tools from the wiki.

You need at minimum: `super` (dynamic partitions: system / product / vendor)
and `boot`.

## 2. Assemble the flip2 system tree

```bash
flip2 image build-tree
# -> pipeline/deploy/dist/flip2-system-tree/
```

The tree contains (see its `MANIFEST.txt` + `SHA256SUMS`):

| File | Purpose |
|------|---------|
| `system/app/PixelTagDrawer/PixelTagDrawer.apk` | D-pad Up tags (system placement survives de-root) |
| `system/app/Launcher4/Launcher4.apk` | flip2 launcher as a normal system app |
| `system/app/Flip2NullKeyboard/Flip2NullKeyboard.apk` | preloaded IME |
| `system/usr/keylayout/matrix-keypad.kl` | backspace remap (no Magisk needed) |
| `product/overlay/Flip2NavOverlay.apk` | hide the 30px nav bar |
| `product/overlay/Flip2LauncherOverlay.apk` | stock Launcher3 menu RRO |

Notes:

- APKs are **debug-signed** — that is fine for `system/app` preloads, but
  do **not** put them in `priv-app` and do **not** replace
  `/system/priv-app/Launcher3` (bootloop risk; platform signature needed).
- FlipMouse is **not** in the tree: it needs runtime root to read
  `/dev/input`. Forkgram is never bundled (GPL). Both arrive via the
  Tier B installer.

## 3. Merge the tree into the stock images

Mount the `system` / `product` partitions from your unpacked `super.img`
(on Linux: `simg2img` then loop-mount, or use `lpunpack`) and copy the tree
over:

```bash
sudo cp -a pipeline/deploy/dist/flip2-system-tree/system/.   /mnt/system/
sudo cp -a pipeline/deploy/dist/flip2-system-tree/product/.  /mnt/product/
```

Rebuild `super.img` (`lpmake`), keeping the original partition sizes and
group layout. Check the rebuilt image against the `SHA256SUMS` of the files
you added.

## 4. Flash via fastbootd

fastbootd (userspace fastboot running in recovery) is what handles dynamic
partitions — the 1.5G `super` image included. Enter fastbootd per the wiki
(`~/flip2-enter-fastboot.sh`), then:

```bash
fastbootd boot sequence per flip2 wiki
fastboot flash boot neutron.img          # or neutron-noavb.img — root vector
fastboot flash super  super-rebuilt.img  # our merged system/product
fastboot reboot
```

First boot takes longer than usual (odex/dexopt of the preloaded apps).
If boot loops: reflash the stock `super` from your backup and debug via the
emergency notes — do **not** reflash EMMC_BOOT.

## 5. Complete Magisk, then run the Tier B installer

The neutronscott boot image leaves Magisk partially installed. On the
device, dial `*#*#217703#*#*` to trigger the full Magisk download/setup,
reboot, and confirm the Magisk app shows installed.

Then push the installer zip and flash it in the Magisk app
(Install from storage), or sideload:

```bash
flip2 installer pack --flavor full
adb push pipeline/deploy/dist/flip2-installer-full-magisk.zip /sdcard/Download/
# Magisk app -> Install -> /sdcard/Download/flip2-installer-full-magisk.zip
# reboot
adb logcat -b all -d | grep -i flip2 || adb shell cat /cache/flip2-installer.log
```

The one-shot installer installs Forkgram (downloaded at install time),
applies IME/home-keys settings, starts FlipMouse, writes
`/data/local/flip2/deroot.sh`, and removes itself.

## 6. Verification gate

Before trusting the image, run the checklist in
[IMAGE-BUILD-READINESS.md](IMAGE-BUILD-READINESS.md): menu grid + slot 5 +
icons, bar labels, Shortcuts soft key, stock Launcher3 fallback HOME.

Tier-level checks after step 5:

- `flip2 flipmouse status` — mouse daemon alive after reboot
- `flip2 ime status` — Null Keyboard is default, models present
- d-pad Up opens PixelTagDrawer; ⌫ deletes in chat (keypad KL)
- no 30px nav bar (nav overlay RRO active)

## Device probes (fill in from your device)

These need adb once the udev rule is installed
(`launcher-patch/scripts/51-android-flip2-adb.rules`); record what your
4058G reports:

```bash
adb shell getprop ro.build.ab_update          # A/B slots?
adb shell ls /dev/block/by-name/              # partition map (super, boot_a/b, vbmeta*)
fastboot getvar current-slot
fastboot reboot fastboot                      # fastbootd availability
```

Document the answers here before the first real flash.
