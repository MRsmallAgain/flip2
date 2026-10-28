# Return to factory (gated, wizard step)

Design for a third wizard slice that puts a rooted Flip 2 back to a stock boot
and wipes userdata, with the same "nothing happens until you type the word"
gate the other destructive slices use. Written 2026-10-28 for the run on
`ONTKKB9L7PEUX4Z5`.

**Status: design only.** No code for this slice exists yet, and nothing has
been flashed, wiped or relocked. The plan is to build it, then prove it on
this phone as the guinea pig.

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
- **Build match:** the phone's `ro.build.display.id` (and fingerprint) matches
  the value recorded from the donor phone. Mismatch stops the flow.

## Stages

1. **Back up the current boot.** Escape hatch back to the rooted phone.
2. **Verify the stock image.** Magic, size, user-pasted sha256, build match.
3. **Flash it to `boot`.** `flashBoot()` only, guarded by `STOCK_VERIFIED`.
4. **Reboot** into the now-stock boot.
5. **Wipe userdata**, guided on the keypad: stock recovery
   `wipe data/factory reset`, with the live phone-status panel and countdown,
   and Settings → System → Reset options as the fallback if the recovery
   keys misbehave.
6. **Confirm factory state.** Build id equals the donor's, `su` absent, package
   list is the stock set, `ro.boot.verifiedbootstate` is still `orange` because
   the bootloader is still unlocked — the page states that plainly rather than
   claiming the phone is factory-fresh.

## Known gap: backing up the boot image from the page

The page's ADB client (`wizard/pages/js/adb.js`) has `shell()` and
`pushFile()`. It has **no SYNC `RECV`**, so the page cannot pull a file off the
phone today. `dd if=/dev/block/by-name/boot of=/sdcard/...` over `shell()` can
create the image on the phone, but nothing in the page can read it back.

Three ways to close it, to be chosen when the slice is built:

- **Companion-side pull** (preferred): add an `ipcMain` handler that runs
  `adb pull` on the host and returns the sha256. The companion already shells
  out for udev, and the host `adb` server is the thing holding the USB
  interface anyway. The page keeps its own hash check on the returned bytes.
- **Base64 over shell** with `toybox base64` in one stream, verified by size and
  hash. No new ADB plumbing, but it is slow for a 24 MB image and the output
  passes through a text stream that truncates badly if anything goes wrong.
- **Host-only backup**: the operator runs `adb pull` themselves and pastes the
  sha256 into the page. Honest, but it moves the safety-critical step outside
  the gate.

Whichever wins, the rule stands: the flow will not enable the flash until the
page holds a sha256 for a backup it has actually read.

## Donor phone: getting the stock image

Survey the donor first — reachable over adb? rooted? what build?

- **Rooted donor:** `su -c dd if=/dev/block/by-name/boot of=/sdcard/boot-stock.img`
  then `adb pull`. Cleanest.
- **Unrooted donor:** SP Flash Tool readback. Heavier, and the driver/download
  mode requirements are its own project.

Then compare builds before treating the image as usable:

| property | must match |
|----------|-----------|
| `ro.product.model` | `4058G` |
| `ro.build.display.id` | exact |
| `ro.build.fingerprint` | exact |
| `ro.build.version.security_patch` | exact |

A boot image from a different build is archived but never flashed.

## What this slice does not do

- Does not relock, and does not touch `unlock_critical`.
- Does not flash `super`, `vbmeta`, system, product, or the preloader, and does
  not write the EMMC_BOOT header.
- Does not re-root. Re-rooting is the existing rooting slice, run afterwards.
- Does not promise a factory-fresh security state: the bootloader is still
  unlocked, so verified boot stays `orange`.
