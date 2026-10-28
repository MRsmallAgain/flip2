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

## Recovery: a `super` write that stalls mid-image

Measured on the reference 4058G, 2026-10-28. A full 2 GiB `super` write can
die partway through even with a good cable and A/C power, and the on-device
partition is then a **torn mix of two images**. Do not boot the phone in that
state; finish the write first.

**How it looks.** `fastboot flash super` stops printing progress. The host
`fastboot` process sits in state `D` inside `usbfs_start_wait_urb`, and the
device stops answering `getvar`. That is a dead USB transfer, not disk IO and
not a host fault — two attempts on different chunk sizes stalled in the same
region of the image (885.8 MiB at the default ~128 MiB chunk; 43.08% at
`-S 64M`).

**Only a physical power cycle clears it.** `USBDEVFS_CLEAR_HALT` on the two
bulk endpoints woke the channel for exactly one command and then it died again;
it is not a port reset and is not permission to retry a 2 GiB transfer.
`USBDEVFS_RESET`, sysfs `unbind`, `sudo` and `chmod` on the device node are not
part of this procedure.

**Write only the missing tail.** Stock `super` data stops at the last non-zero
4 KiB block — on this build that is 1,689,915,392 bytes (1611.63 MiB) of a
2,147,483,648-byte partition — so the remaining ~436 MiB is zeros and never
needs writing. Resume below the stall point (864 MiB here, deliberately
re-covering the uncertain boundary) and emit an Android sparse image:

- 28-byte header, `<IHHHHIIII` = magic `0xED26FF3A`, major 1, minor 0,
  file-header 28, chunk-header 12, block size 4096, total blocks, chunk count,
  checksum 0
- per chunk, `<HHII` = type, reserved, block count, total byte size
- type `0xCAC1` raw (payload follows), type `0xCAC3` don't-care (no payload)

Prefix and suffix are don't-care; the middle is raw chunks read from the stock
image. Re-read the file before flashing and assert that the chunk block counts
sum to the total block count and that there are no trailing bytes. Then
`fastboot flash super <tail>.sparse` — roughly 748 MiB instead of 2 GiB, and on
this hardware it completed in 104.5 s where both full pushes had died.

Two things bite here:

- **`fastboot` re-sparsifies at transport time**, so the `Sending sparse
  'super' N/M` counts in its output do not match the chunk count you built. Do
  not use those numbers to decide whether the write finished — look for
  `Finished. Total time`.
- **Do not hash a raw `adb exec-out dd` capture of the partition.** The stream
  is CRLF-translated (`0a` becomes `0d0a`), so the file comes back ~11 MB too
  large with a wrong hash and a divergence at the first `0x0a` byte. Hash on the
  device and let only the digest cross USB:

  ```bash
  adb shell 'su -c "dd if=/dev/block/by-name/super bs=4096 count=412577 \
      2>/dev/null | sha256sum"'
  dd if=super.img bs=4096 count=412577 2>/dev/null | sha256sum   # same range, host
  ```

**A `fastboot devices` line proves nothing.** It prints the serial straight from
the USB descriptor, and this device's bootloader enumerates as `0e8d:201c` both
when it is healthy and when its command channel is dead. Test the channel with
`fastboot getvar product` and require `product: gflip6` before any write; a
`201c` that answers is a working bootloader and must not be treated as wedged.

One more thing worth knowing during a recovery: **bootloader fastboot accepts
the physical partition name `vbmeta_system`, while fastbootd rejects it with
`No such file or directory`.** With `vbmeta_system` restored and `super`
verified byte-identical to stock over its non-zero range, the device boots back
to Android normally.

## Device probes (measured on the reference 4058G, 2026-10-26)

Results from the reference device — expect the same on any 4058G:

- **`adb shell getprop ro.build.ab_update`** → *empty*. The 4058G is
  **A-only** (single boot slot, no A/B). There is no `current-slot` to
  switch; flashing boot replaces the one slot.
- **`ls /dev/block/by-name/`** → MediaTek layout, no `_a`/`_b` suffixes:
  `boot`, `super` (dynamic partitions), `dtbo`, `recovery`,
  `vbmeta`, `vbmeta_system`, `vbmeta_vendor`, `vendor_boot`, plus
  `protect1/2`, `nvdata`, `metadata`, `userdata` and the MTK firmware
  partitions (`lk`, `tee1/2`, `spmfw`, `mcupmfw`, `md1img`, …).
  **`super` is present → fastbootd (userspace fastboot) is required for
  flashing our system/product tree; the bootloader's fastboot cannot
  resize dynamic partitions.** Back up the three `vbmeta*` partitions
  before anything else.
- **`fastboot getvar current-slot` / `fastboot reboot fastboot`:** NOT
  reachable via plain `adb reboot bootloader`. Watched on the USB bus:
  the device passes through transient MediaTek IDs (`0e8d:0003` bootrom
  serial, then `0e8d:2000` MT65xx Preloader for ~2 s) and **boots
  straight back to Android** — it never sits in stock fastboot.
  Entering fastboot/fastbootd on this device requires the bootrom
  vector from the flip2 wiki (`autobooter-linux.py` + `mtk-bootseq.py`,
  wrapped by `~/flip2-enter-fastboot.sh`), not an adb reboot. The
  `0e8d:*` udev rule in
  `launcher-patch/scripts/51-android-flip2-adb.rules` makes those
  transient preloader nodes accessible to plugdev on Linux.

Note for Linux hosts: `adb reboot bootloader`-style reboots re-enumerate
the USB device with a fresh node. If `/etc/udev/rules.d/` is empty (no
persistent rule), the new node loses its ACL and adb reports "no
permissions" — install the rule from
`launcher-patch/scripts/51-android-flip2-adb.rules` (covers both
`1bbb:0c01` adb and `0e8d:*` preloader/fastboot) rather than re-chmodding
each session.
