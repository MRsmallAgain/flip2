# Building a flip2 system tree (Tier A)

This is the **Tier A** path: bake the flip2 OSS set into *your own* stock
firmware as system/product files, so the components survive even with no
Magisk module. Everything else (FlipMouse, Forkgram, IME settings, Vosk
models) still comes from the Tier B installer zip after first boot.

**We do not distribute TCL firmware or boot images.** You dump your own
firmware. Unlock and boot flash are not on this branch; they live on
`feature/rooting-slice`. Do not use that path on an already-rooted Flip 2 —
unlocking the bootloader erases the phone. Upstream notes:
[flip2 wiki](https://github.com/neutronscott/flip2/wiki).

## 0. Warnings — read first

- **Never overwrite the 2048-byte EMMC_BOOT preloader header.** If the
  preloader is corrupted, the device will not enter boot ROM download mode
  and cannot be recovered by SP Flash Tool.
- **Back up `vbmeta`, `vbmeta_system`, and `vbmeta_vendor` before any
  partition write.** If a write goes wrong, restore vbmeta first.
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

## 4. Partition writes

fastbootd (userspace fastboot in recovery) is what handles dynamic
partitions, including `super`. The commands that enter fastbootd and write
partitions are not on this branch; they live on `feature/rooting-slice`.
Do not flash this already-rooted phone — unlocking it would erase the phone.
Never interrupt a fastbootd write. If a write on another device goes wrong,
restore from your stock backup and follow the emergency notes — do **not**
reflash the EMMC_BOOT preloader header.

## 5. Tier B installer, once Magisk is already installed

Finishing a custom boot image belongs to the rooting path on
`feature/rooting-slice`. Do not do that on this already-rooted phone.

Push the installer zip and install it from storage in the Magisk app,
or sideload:

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

## Device probes (measured on the reference 4058G, 2026-10-26)

Results from the reference device — expect the same on any 4058G:

- **`adb shell getprop ro.build.ab_update`** → *empty*. The 4058G is
  **A-only** (single boot slot, no A/B). There is no `current-slot` to
  switch; a boot-partition write would replace the only slot, and that write is not on this branch.
- **`ls /dev/block/by-name/`** → MediaTek layout, no `_a`/`_b` suffixes:
  `boot`, `super` (dynamic partitions), `dtbo`, `recovery`,
  `vbmeta`, `vbmeta_system`, `vbmeta_vendor`, `vendor_boot`, plus
  `protect1/2`, `nvdata`, `metadata`, `userdata` and the MTK firmware
  partitions (`lk`, `tee1/2`, `spmfw`, `mcupmfw`, `md1img`, …).
  **`super` is present, so any dynamic-partition write would need
  fastbootd (userspace fastboot); the bootloader fastboot cannot resize
  dynamic partitions.** That write is not on this branch. Back up the
  three `vbmeta*` partitions before any partition write.
- **`fastboot getvar current-slot` / `fastboot reboot fastboot`:** NOT
  reachable via plain `adb reboot bootloader`. Watched on the USB bus:
  the device passes through transient MediaTek IDs (`0e8d:0003` bootrom
  serial, then `0e8d:2000` MT65xx Preloader for ~2 s) and **boots
  straight back to Android** — it never sits in stock fastboot.
  `adb reboot bootloader` does not stay in fastboot. The bootrom entry
  sequence is not on this branch; it lives on `feature/rooting-slice`.
  Do not use it on an already-rooted Flip 2 — unlocking erases the phone.
  The `0e8d:*` udev rule in
  `launcher-patch/scripts/51-android-flip2-adb.rules` only grants
  permission on those transient nodes. It does not send a command.

Note for Linux hosts: `adb reboot bootloader`-style reboots re-enumerate
the USB device with a fresh node. If `/etc/udev/rules.d/` is empty (no
persistent rule), the new node loses its ACL and adb reports "no
permissions" — install the rule from
`launcher-patch/scripts/51-android-flip2-adb.rules` (covers both
`1bbb:0c01` adb and `0e8d:*` preloader/fastboot) rather than re-chmodding
each session.
