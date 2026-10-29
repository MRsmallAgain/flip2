# Return to factory (gated, wizard step)

Design for a third wizard slice that puts a Flip 2 back to the boot image it was
last saved on, then wipes userdata, with the same "nothing happens until you
type the word" gate the other destructive slices use.

**Status: built, and its restore path is proven on hardware.** The slice exists
in `wizard/pages/` and the companion. On 2026-10-28 donor `MRV8IJJVPRYTS4UG`
had its `boot` partition deliberately destroyed and then restored from a saved
copy, byte-identical, with root coming back with it — see
[FACTORY-TEST.md](FACTORY-TEST.md).

What has **not** been run: the wizard page itself end to end (the drill used
`fastboot flash boot` from the host, not `FASTBOOT.flashBoot()`), the wipe
stage, and the path of choosing a copy on a phone that was already unbootable
before the copy was picked. Nothing has been wiped or relocked.

## What it restores: the phone's own boot image, not downloaded firmware

The source is a copy of the phone's own `boot` partition that the wizard saved
earlier — this visit, or an earlier one. Nothing is downloaded and no second
phone is needed.

This matters for two reasons.

**There is nothing to download.** No stock image for build `UPEN`
(`TCL/4058G/Gflip6_NA_OM:11/RP1A.200720.011/UPEN:user/release-keys`) exists
online, and both phones on hand carry modified boot images, so the only honest
source for a particular phone's boot is that phone.

**It is also the only revive path.** A phone that will not start cannot be
dumped now, but a copy saved on an earlier visit can still be put back. That
turns the slice from a restore button into a recovery tool.

### What that means about root

Root lives in the boot image's ramdisk. A restored copy therefore brings back
the root state that copy was taken in — it is not a separate thing that gets
reset. If the copy was taken on a rooted phone, the phone comes back rooted.

So this is not factory firmware in the security sense, and the slice does not
pretend otherwise:

- the gate has a box for it — "I accept that the phone comes back in whatever
  root state that copy was taken in";
- step 2 shows the root state recorded with the copy;
- step 6 compares the phone's root state against the copy's instead of
  demanding "no root", and says "the phone came back as the copy that was
  saved" when they agree.

What the wipe still gives you is a clean userdata partition: no accounts, no
apps, no photos. That is the part "factory reset" normally means.

## Why it is not just another catalog entry

`neutron.img` is flashable because it has an upstream pin in
`wizard/catalog.json` (25,165,824 bytes, sha256
`31237917ef51fa6e7ee588da1cfc84bb378859de2d49681fdd4f84290841d3c1`). The page
sets `VERIFIED['neutron']` only on an exact size + SHA-256 match, and
`flashBoot()` refuses to run without it.

A copy of the phone's own boot has no upstream pin and cannot get one. So it is
a **separate** gate with separate state (`FACTORY_PICKED` / `FACTORY_VERIFIED`),
and the two must not cross-feed: a neutron image must never satisfy this path
and this path must never satisfy the neutron one.

## Hard constraints

- **`boot` only.** The only write path stays `FASTBOOT.flashBoot()`, which
  sends `download:` followed by `flash:boot` and cannot address another
  partition. No new flash function, no partition parameter.
- **No `erase`, no `-w`, no `fastboot format`.** Userdata is wiped on the
  phone, in recovery or in Settings, by the person holding it.
- **No relock, no `flashing unlock_critical`.** Relocking a 4058G whose boot
  image is not the exact stock build is the single most reliable way to
  hard-brick this hardware. The bootloader stays unlocked and the page says so.
- **No write of a copy from another build.** When the phone can be read and its
  fingerprint differs from the copy's, the copy is refused.
- **Nothing auto-runs.** Every write is its own click, and the page shows one
  stage at a time (`facStage()`), kept separate from the rooting step's stage
  machinery so a half-finished run in either slice cannot leak across.

## Gate before the slice opens

The slice is reachable from the footer next to the rooting link and is gated by
typing **`factory`** — a different word from `yes` (allowed to download) and
`erase` (allowed to unlock and root), so a habit cannot carry someone across.

Three acknowledgements, each a separate checkbox, all required:

1. I understand the phone is restored from a copy of its own boot image, not
   from downloaded firmware.
2. I accept that every app, photo and setting on this phone is erased.
3. I accept that the phone comes back in whatever root state that copy was
   taken in.

## Stages

1. **Save a copy, or choose one.**
   - *Save a copy from the phone* runs in the companion (`factory-backup-boot`),
     because the page's ADB client has no SYNC `RECV`. It runs
     `su -c dd if=/dev/block/by-name/boot of=/sdcard/…`, pulls the file to
     `~/Downloads/flip2-wizard/backups/`, hashes it on the host with `crypto`,
     records the build fingerprint, model and whether the phone was rooted at
     that moment, writes a JSON sidecar beside it, and deletes the sdcard copy.
     Read-only on the phone: nothing is written to any partition.
   - *Look for saved copies* calls `factory-list-backups`, which lists the
     `.img` files in that folder newest first. The hash comes from the sidecar
     when it is well-formed and is recomputed from disk when it is not, so a
     copy with no sidecar is still usable.

   Either way the result lands in `FACTORY_PICKED`, which is what step 2 checks.
2. **Check the copy.** `factory-read-backup` re-reads the file off disk and
   re-hashes it *now*; the page refuses unless the first eight bytes are
   `ANDROID!`, the size fits the 24 MiB `boot` partition, and the fresh SHA-256
   equals the one recorded when it was saved. When the phone can be read, its
   `ro.build.fingerprint` must also equal the copy's — that comparison is
   skipped when the phone will not boot, which is exactly the case this exists
   for. Passing sets `FACTORY_VERIFIED`.
3. **Flash it to `boot`.** `flashBoot()` only, guarded by `FACTORY_VERIFIED`.
   Before writing, `getvar serialno` must equal the serial recorded in the
   copy, so a second phone on the bus cannot be written. A copy with no serial
   recorded says so in the log instead of guessing.
4. **Reboot** into the restored boot image.
5. **Wipe userdata on the phone.** Settings → System → Reset options, or
   recovery (`Volume up + Power`) if it will not start. The wizard refuses to
   do this over the cable. Then USB debugging is turned back on.
6. **Confirm what came back.** The companion reads the phone back
   (`factory-state`): fingerprint against the copy's, `su` state against the
   copy's recorded `rooted` flag, package count, and `verifiedbootstate`. The
   bootloader is still unlocked, so verified boot stays `orange`; the page
   states that plainly rather than claiming a factory-fresh security state.

## Where the copies live, and why the page cannot reach anything else

Copies and their sidecars are written under
`app.getPath('downloads')/flip2-wizard/backups/` — never inside the repo.

`readBootBackup()` resolves both the folder and the requested file with
`realpath` and refuses anything that is not inside that folder, so a path
invented by the page cannot read arbitrary files off the host. The hash is
recomputed from the bytes being returned rather than taken from the sidecar, so
an edited sidecar cannot smuggle a different image through step 2.

Each sidecar records `serial`, `path`, `size`, `sha256`, `magic`, `takenAt`,
`fingerprint`, `model` and `rooted`.

## The gate on the hash, restated

The rule is: the flow does not enable the flash until the page holds a SHA-256
for a copy it actually read off the disk during this run. Nothing is written on
the strength of a hash typed in by hand, and there is no field where a person
could paste one.

## What this slice does not do

- Does not relock, and does not touch `unlock_critical`.
- Does not flash `super`, `vbmeta`, system, product, or the preloader, and does
  not write the EMMC_BOOT header.
- Does not download anything, and does not use another phone's boot image.
- Does not un-root. A copy taken on a rooted phone comes back rooted, by
  design; re-rooting after an unrooted copy is the existing rooting slice.
- Does not promise a factory-fresh security state: the bootloader is still
  unlocked, so verified boot stays `orange`.

## History: why the stock-image route was abandoned

This slice was first designed around flashing a stock `boot.img` from a donor
phone of the same build. That route was dropped on 2026-10-28:

- No stock `UPEN` image is published online, and neither on-hand phone has one
  on its `boot` partition — both were rooted by flashing a modified image, so
  `dd` returns that modified image, not stock.
- A synthesized stock-equivalent `boot.img` was built and boot-tested on donor
  `MRV8IJJVPRYTS4UG` twice. Both attempts failed identically at the preloader,
  and the donor was recovered and verified both times. That image is marked
  **do not flash again**.
- The donor's `boot` is not even this build: it carries an AT&T 4058R image
  (`patch2019-06-06`), so it would be refused by the fingerprint check.

The dump-based design removes the dependency entirely. Detail of the synthesis
attempts is in `docs/IMAGE-BUILD.md`.
