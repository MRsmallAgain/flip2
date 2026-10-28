# Return to factory (gated, wizard step)

Design for a third wizard slice that puts a rooted Flip 2 back to a stock boot
and wipes userdata, with the same "nothing happens until you type the word"
gate the other destructive slices use. Written 2026-10-28 for the run on
`ONTKKB9L7PEUX4Z5`.

**Status: built, not yet run.** The slice exists in `wizard/pages/` and the
companion, and it has never been used to write a partition. Nothing has been
flashed, wiped or relocked. The next step is to prove it on this phone as the
guinea pig, then record the run in `docs/FACTORY-TEST.md`.

## Why it is not just another catalog entry

`neutron.img` is flashable because it has an upstream pin in
`wizard/catalog.json` (25,165,824 bytes, sha256
`31237917ef51fa6e7ee588da1cfc84bb378859de2d49681fdd4f84290841d3c1`). The page
sets `VERIFIED['neutron']` only on an exact size + SHA-256 match, and
`flashBoot()` refuses to run without it.

A stock boot image pulled from the user's own phone has no upstream pin and
cannot get one. Adding it to the catalog would dilute what that file means and
would still leave the hash attacker-controlled. So the stock path is a
**separate** gate with separate state: `STOCK_VERIFIED`, not `VERIFIED`.

The two gates must not cross-feed. A neutron image must never satisfy the
stock path and vice versa, even on a hash collision of the user-pasted value.

## Hard constraints

- **`boot` only.** The only write path stays `FASTBOOT.flashBoot()`, which
  sends `download:` followed by `flash:boot` and cannot address another
  partition. No new flash function, no partition parameter.
- **No `erase`, no `-w`, no `fastboot format`.** Userdata is wiped on the
  phone, in recovery or in Settings, by the person holding it.
- **No relock, no `flashing unlock_critical`.** Relocking a 4058G whose boot
  image is not the exact stock build is the single most reliable way to
  hard-brick this hardware. The bootloader stays unlocked and the page says so.
- **No write without a same-build match.** If the stock image's build id does
  not match the phone's, the image is archived and the flow stops.
- **Nothing auto-runs.** Every write is its own click, and the page shows one
  stage at a time (the same `renderStage()` / `setStage()` machinery the
  rooting step uses, so the two slices cannot fight over the screen).

## Gate before the slice opens

The slice is reachable from the footer next to the rooting link and is gated by
typing **`factory`** — a different word from `yes` (allowed to download) and
`erase` (allowed to unlock and root), so a habit cannot carry someone across.

Three acknowledgements, each a separate checkbox, all required:

1. I have the stock `boot.img` for *this* build, from a phone of the same build.
2. I understand userdata is erased: apps, photos, settings.
3. I understand root is gone afterwards and re-rooting is a separate run.

## Gate before the write

Enforced in code, not in prose:

- **Exactly one USB device**, serial read from the phone and displayed. Never
  hardcoded; a second phone on the bus stops the flow.
- **Image sanity:** file size not larger than the boot partition size, and the
  first eight bytes are the `ANDROID!` boot header magic.
- **Hash agreement:** the page computes SHA-256 in WebCrypto and compares it
  with a value the user pastes in from wherever they got the image. The pasted
  value is printed into the run log so the record says what was trusted.
- **Backup already taken:** the current boot must have been backed up in this
  session, with its sha256 shown. No backup, no write.
- **Build match:** the phone's `ro.build.fingerprint` equals the fingerprint
  the user pastes in from the donor phone. Mismatch refuses the image before
  fastboot is even opened.
  
  **`ro.build.display.id` is not usable on this hardware — it is empty.** The
  gate keys on `ro.build.fingerprint`, which is populated
  (`TCL/4058G/Gflip6_NA_OM:11/RP1A.200720.011/UPEN:user/release-keys`) and
  identifies the build exactly. `ro.build.description` and
  `ro.build.version.security_patch` are recorded with it for the run record,
  but the automated comparison is the fingerprint.

## Stages

Each stage is its own screen, enforced by `facStage()`, which is deliberately
separate from the rooting step's `setStage()` so a half-finished run in one
slice cannot leak into the other.

1. **Back up the current boot.** Escape hatch back to the rooted phone. Runs in
   the companion (`factory-backup-boot`), because the page has no ADB `RECV`.
   Shows serial, model, build, file path, size and sha256, and requires the user
   to confirm the serial is the phone they mean.
2. **Verify the stock image.** Magic, size against the saved backup's size (the
   real boot partition), user-pasted sha256, and donor fingerprint match.
3. **Flash it to `boot`.** `flashBoot()` only, guarded by `STOCK_VERIFIED`.
   Before writing, `getvar serialno` must equal the serial recorded in the
   backup — a second phone on the bus cannot be written.
4. **Reboot** into the now-stock boot.
5. **Wipe userdata on the phone.** Settings → System → Reset options, or
   recovery (`Volume up + Power`) if it will not start. The wizard refuses to
   do this over the cable. Then USB debugging is turned back on.
6. **Confirm factory state.** The companion reads the phone back
   (`factory-state`): fingerprint must match the donor's, `su` must not answer,
   the package count is reported, and `verifiedbootstate` is still `orange`
   because the bootloader stays unlocked. The page states that plainly rather
   than claiming the phone is factory-fresh.

## The boot backup, and the gap it used to leave

The page's ADB client (`wizard/pages/js/adb.js`) has `shell()` and
`pushFile()` but **no SYNC `RECV`**, so the page cannot pull a file off the
phone. That was the one real gap in this design.

It is closed companion-side: `backupBoot()` in `companion/main.js` runs
`su -c dd if=/dev/block/by-name/boot of=/sdcard/...`, `adb pull`s the result to
`~/Downloads/flip2-wizard/backups/`, hashes it on the host with `crypto`, and
deletes the sdcard copy. The page receives `{serial, path, size, sha256,
magic}` and refuses to continue unless `magic === 'ANDROID!'`.

The rule stands: the flow does not enable the flash until the page holds a
sha256 for a backup that was actually read.

## Donor phone: getting the stock image

Survey the donor first — reachable over adb? rooted? what build?

- **Rooted donor:** `su -c dd if=/dev/block/by-name/boot of=/sdcard/boot-stock.img`
  then `adb pull`. Cleanest.
- **Unrooted donor:** SP Flash Tool readback. Heavier, and the driver/download
  mode requirements are its own project.

Then compare builds before treating the image as usable:

| property | must match | checked by |
|----------|-----------|------------|
| `ro.product.model` | `4058G` | run record |
| `ro.build.fingerprint` | exact | **the gate** |
| `ro.build.description` | exact | run record |
| `ro.build.version.security_patch` | exact | run record |
| `ro.build.display.id` | *not used — empty on this build* | — |

A boot image from a different build is archived but never flashed. The
fingerprint is the one the wizard compares automatically, because it is the
only property on this phone that names the build unambiguously.

## What this slice does not do

- Does not relock, and does not touch `unlock_critical`.
- Does not flash `super`, `vbmeta`, system, product, or the preloader, and does
  not write the EMMC_BOOT header.
- Does not re-root. Re-rooting is the existing rooting slice, run afterwards.
- Does not promise a factory-fresh security state: the bootloader is still
  unlocked, so verified boot stays `orange`.
