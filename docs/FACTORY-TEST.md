# Boot destroy and restore drill — 2026-10-28

Run on donor `MRV8IJJVPRYTS4UG` while a replacement phone was already on its way, so
the donor was expendable. The point was to test the one claim the return-to-factory
slice rests on: **a phone whose `boot` partition has been destroyed can be brought
back from a copy the wizard saved earlier.**

This is not the full factory flow. Only `boot` was written: no wipe and no recovery
menu. The recovery steps 1–3 of [RETURN-TO-FACTORY.md](RETURN-TO-FACTORY.md) were
exercised at the fastboot level, with the same payload and the same `flash:boot`
command the slice uses.

The rest of this document is two later runs on the same phone:

- a **read-only probe** that drove the wizard page through stages 1, 2 and 6 without
  being able to reach a write;
- a **full cycle** driven from the same page, which did reach the write stages —
  save, choose, check, install, restart, walk the wipe instructions, confirm state.

Two limits on that full cycle, stated up front so nothing below overstates it. The
copy written back was byte-identical to what was already on the phone, so it proves
the page's write path works end to end but was not a recovery from a destroyed
partition. And the wipe stage was walked, not performed: no userdata was erased on
this phone during these runs.

## Device before the test

| | |
|---|---|
| serial | `MRV8IJJVPRYTS4UG` |
| model / device | `4058G` / `Gflip6_NA_OM` |
| build fingerprint | `TCL/4058G/Gflip6_NA_OM:11/RP1A.200720.011/UPEN:user/release-keys` |
| security patch | `2021-09-05` |
| bootloader | unlocked (`ro.boot.flash.locked` = `0`) |
| verified boot | `orange` |
| root | yes — `su -c id` → `uid=0(root) context=u:r:magisk:s0` |
| Magisk | `25.2:MAGISK:R` (25200) |
| packages installed | 167 |
| live `boot` sha256 | `40ef8d5657bb1e95f265c36a04871de83c506320204f8c19b3683bcb7cedd6a5` |

Snapshot of props and the package list, taken before anything was written, is at
`~/flip2-backups/donor-destroy-2026-10-28/` (`props-before.txt`,
`packages-before.txt`). That directory is outside the repo and stays there.

## The copy that was held as the way back

The dump command the companion runs (`dd if=/dev/block/by-name/boot` over `su`,
then `adb pull`) was run on this phone earlier the same day:

| | |
|---|---|
| file | `~/flip2-backups/dump-test-2026-10-28/boot-test.img` |
| size | 25,165,824 bytes |
| header | `ANDROID!` |
| sha256 | `40ef8d56…7cedd6a5` — byte-identical to the live partition above |

## Getting into fastboot

`adb reboot bootloader` does not stop at the bootloader on this hardware: it shows a
preloader for about two seconds and boots Android again. The route that works is the
preloader vector — watch for `/dev/ttyACM*` and write `FASTBOOT` to it. The donor
answered `READYTOO` and enumerated as `0e8d:201c`.

Health gate before every write, in this order, all on the device itself:

```
product: gflip6
serialno: MRV8IJJVPRYTS4UG
partition-size:boot: 1800000        (hex — 25,165,824 bytes)
unlocked: yes
```

## Attempt 1 — 24 MiB of zeros was refused

```
Sending 'boot' (24576 KB)     OKAY [  1.491s]
Writing 'boot'                FAILED (remote: 'image is not a boot image')
```

Nothing was written. The bootloader reads the image header before it writes, so
fastboot cannot be used to simply blank `boot`. That is a real safety property worth
knowing: a plain `dd`-style corruption is not reachable through this path.

## Attempt 2 — a valid header with a dead body was accepted

`header-only.img`: the first 2048 bytes of the good copy (a valid v2 `ANDROID!`
header: kernel 8,082,472 bytes, ramdisk 971,365 bytes, page size 2048) followed by
zeros, exactly 25,165,824 bytes, sha256 `b1218d05…`.

```
Sending 'boot' (24576 KB)     OKAY [  1.496s]
Writing 'boot'                OKAY [  0.511s]
```

**The validation is header-deep only.** A correct header over a zeroed body passes,
and the phone is left unbootable. This is the destroy.

## Result — unbootable, as intended

After `fastboot reboot` the phone left the USB bus entirely, then settled into a
bootloop: BROM `0e8d:0003` → preloader `0e8d:2000`, repeating, with no adb, no
fastboot, and no `/dev/ttyACM*` node at the moments sampled.

## Recovery

Started the preloader watcher; it caught a window within about 4 seconds — the
bootloop keeps offering them, so a destroyed `boot` is easier to catch than a
healthy phone rebooting. The fastboot health gate was re-checked
(`product: gflip6`, `serialno: MRV8IJJVPRYTS4UG`, `unlocked: yes`) and the copy was
written back:

```
Sending 'boot' (24576 KB)     OKAY [  1.495s]
Writing 'boot'                OKAY [  0.513s]
```

## After the restore

| | |
|---|---|
| `sys.boot_completed` | `1` |
| build fingerprint | `TCL/4058G/Gflip6_NA_OM:11/RP1A.200720.011/UPEN:user/release-keys` |
| security patch | `2021-09-05` |
| root | yes — `uid=0(root) context=u:r:magisk:s0` |
| Magisk | `25.2:MAGISK:R` (25200) |
| live `boot` sha256 | `40ef8d56…7cedd6a5` — equals the copy |
| bootloader | unlocked (`flash.locked` = `0`), `orange` |
| packages installed | 167 — same as the snapshot |
| crash buffer | empty |

## What this proves

- A destroyed `boot` on this phone is recoverable from a copy, over fastboot, with
  no vendor tool and no downloaded firmware. The restored phone is byte-identical on
  `boot` to what it was before.
- **Root came back with the copy.** The phone was rooted before and rooted after,
  from the same image, with nothing else done. That is direct evidence for the
  design note that root is a property of the boot image's ramdisk rather than
  something separate — which is why the slice's final check compares against the
  copy's recorded root state instead of demanding an unrooted phone.
- Only `boot` changed. The build, the security patch and all 167 packages were
  untouched, which is what a single-partition write should do.
- The fastboot write path tolerates a valid-header image and refuses a headerless
  one, so a restore cannot be "helpfully" blocked by a checksum mismatch, and a
  blank image cannot be written by accident.

## What this does not prove

- **This particular write was not driven from the page.** It was `fastboot flash boot`
  from the host. The full-cycle run further down does make the page's own
  `FASTBOOT.flashBoot()` do the write, so the page's write path is exercised — just
  not as part of this drill.
- **The wipe stage was not run.** The instructions were walked in the full-cycle run,
  but no userdata was erased, so the recovery and Settings routes are still untested
  on this hardware.
- **The earlier-visit path was not run.** The copy used was dumped by the same
  command, so it is the same code, but the sidecar/list path was not used to reach a
  copy on a phone that was already unbootable — the phone was unbootable *after* the
  copy was chosen.
- A restore to a *different* root state (unrooted copy onto a rooted phone, or the
  reverse) was not exercised.

## The empty `/data/adb/modules`

After the restore, `/data/adb/modules` is empty. That was **not** caused by the
flash: the directory carries a never-modified timestamp (2009-12-31, the RTC
baseline before first boot), and the only modules snapshot on this machine
(`~/flip2-backups/pre-flash-2026-10-27/modules-pre.txt`) belongs to the other phone —
17 packages against 167 here. The donor had no modules installed before the test.
Magisk itself is intact and `su` works, which is the part the boot image carries;
modules live on userdata and were simply never there.

## Page-level run — read-only stages 1, 2 and 6

Same phone, later the same night. This one drives the real page inside the Electron
companion, so the gate, the handlers, the companion IPC and the status text are the
ones a person would touch. It stops before anything can be written.

```
cd ~/.local/share/flip2/companion
npx electron . --factory-probe
```

The probe (`companion/factory-probe.js`) runs on the page's own JavaScript: it clicks
`#factory-link`, types the word and ticks the three acknowledgements with real
`input`/`change` events, then clicks through save → choose → check → confirm state.
It reaches the write stages only far enough to read whether their buttons are
enabled; `flash`, `reboot` and `wipe` are not callable from it at all.

What it recorded, on the donor `MRV8IJJVPRYTS4UG`:

| stop | result |
|---|---|
| gate, before typing | Continue is disabled |
| gate, word + 3 acks | Continue unlocks; only `fac-stage-backup` is on screen |
| save a copy | "Saved. That is the image step 3 puts back…" |
| — facts shown | serial, 25,165,824 bytes, `40ef8d56…`, header `ANDROID!` |
| — root line | "Root right now: rooted — a copy taken now comes back rooted" |
| copies on this computer | 2 listed, the picker visible |
| choose the copy | "Root in that copy: yes — the phone comes back rooted" |
| check the copy | "Checked. This is the copy that was saved, unchanged." |
| — check log | header ok, size within the partition, both hashes equal, `build: matches this phone` |
| continue | step 3 reached (`#fac-verify-next` enabled) |
| confirm state | "The phone came back as the copy that was saved." |
| — state rows | root `rooted`, root in the copy `rooted`, 167 apps, bootloader `unlocked (expected)`, verified boot `orange` |

Screenshots of each stop are in
[`screenshots/factory-test-2026-10-29/`](screenshots/factory-test-2026-10-29/) —
`01-gate.png` through `08-step6-checked.png`. They were captured with
`webContents.capturePage()` at the window's own 1020×800.

### The bug this run caught

On the first pass, stage 6 reported `Root in that copy: (not recorded)` even though
the copy had been dumped and the sidecar had `rooted: true` in it. The companion's
`listBootBackups()` built each row without carrying `rooted` through, so the field
was always missing when a copy came from the list rather than from a fresh dump.
That mattered: the stage-6 verdict compares the phone's root state against the
copy's, and a silently missing value would have made the comparison skip instead of
pass or fail.

Fixed in `companion/main.js` by passing it through as a boolean or `null` — `null`
when there is genuinely no record, so "not recorded" and "recorded as unrooted" stay
distinguishable. The table above is from the second, clean run.

### What it deliberately does not reach

- The flash stage: the probe never calls `FASTBOOT.flashBoot()`. The full-cycle run
  below does, from the same page.
- Reboot and the wipe: it does not touch either.
- Choosing a copy on a phone that was *already* unbootable. Here the phone was healthy
  the whole time; the drill above only made it unbootable after the copy was picked.

## Full cycle — all six stages driven from the page

Still the donor `MRV8IJJVPRYTS4UG`, after the probe run. This one goes all the way
through, including the write, with the page doing the work rather than a host command.
The page was driven over the Electron debug port with a throwaway script
(`/tmp/fac-cycle.js`, not committed) that clicks the real elements, so every gate and
handler below is the one a person touches.

| stage | what the page said |
|---|---|
| gate | locked until the word and all three acks; then opens on stage 1 only |
| 1 save a copy | "Saved. That is the image step 3 puts back…" |
| — copies listed | 3, the new one chosen automatically |
| 2 check the copy | "Checked. This is the copy that was saved, unchanged." |
| — check log | `ANDROID!`, 25,165,824 bytes, both hashes equal, `build: matches this phone` |
| 3 connect | "Connected to MRV8IJJVPRYTS4UG. The copy can be installed now." |
| — flash log | `Claimed fastboot interface.` / `serialno: MRV8IJJVPRYTS4UG` / `download:01800000 (25165824 bytes)` |
| 3 install | "The copy is installed." |
| 4 restart | "Restarted." |
| 5 wipe | instructions shown; the continue button was clicked, nothing erased |
| 6 check | "The phone came back as the copy that was saved." |
| — state rows | root `rooted`, root in the copy `rooted`, 167 apps, `unlocked (expected)`, `orange` |

Before the write, the fastboot health gate was re-checked from the host: `product:
gflip6`, `serialno: MRV8IJJVPRYTS4UG`, `partition-size:boot: 1800000`, `unlocked:
yes`. After the reboot the phone came back on adb in about 30 seconds with `boot`
hashing to `40ef8d56…7cedd6a5`, the same copy, `sys.boot_completed=1`, root intact and
167 packages — so the page's write path did not damage the boot image.

Screenshots: `09-stage-flash-after-run.png` and `09-stage-reboot-after-run.png` in
[`screenshots/factory-test-2026-10-29/`](screenshots/factory-test-2026-10-29/),
captured straight after each stage came back. Stage 6's pixels are identical to
`08-step6-checked.png` because both runs ended with the same verdict and the same
nine rows; that is sameness, not a stale frame.

### What this run actually proves, and what it does not

It proves the page's write path works end to end: the gate, the disk re-check, the
WebUSB handshake, `FASTBOOT.flashBoot()` sending 24 MiB with the legacy `DATA` size
header, the reboot, and the final comparison — all as a person would drive them.

It does **not** prove a recovery. The copy written back was byte-identical to what
was already on the partition, so a failure anywhere in the write would have been
invisible in the outcome. The destructive half — writing a *different* image and
recovering from it — was drilled at the host level earlier in this document, and the
combination of the two (destroy from the page, restore from the page) has not been
run. That is the remaining gap, and the replacement phone is the place to close it.

No userdata was erased. The wipe stage was walked to its continue button so the
hand-off into stage 6 could be exercised, but step 5's instructions are still
instructions rather than something performed on this hardware.

## Artefacts

Host only, never committed:

- `~/flip2-backups/dump-test-2026-10-28/boot-test.img` — the working copy.
- `~/flip2-backups/donor-destroy-2026-10-28/` — `header-only.img`,
  `zeros-24MiB.img`, `props-before.txt`, `packages-before.txt`,
  `destruction-log.txt`.
- `~/flip2-backups/factory-probe-2026-10-29T00-29-52-239Z/` — the probe's eight
  screenshots and its report. The copies that matter are committed under
  `docs/screenshots/factory-test-2026-10-29/`.

**Do not flash `header-only.img` or `zeros-24MiB.img` anywhere.** They exist to
prove the failure mode and nothing else.

Timeline from `destruction-log.txt`:

```
start:                    2026-10-29T00:22:10Z
zeros refused:            2026-10-29T00:22:22Z
destroy written:          2026-10-29T00:22:40Z
reboot, no boot:          2026-10-29T00:22:44Z
restore written:          2026-10-29T00:24:27Z
reboot, Android up:       2026-10-29T00:24:32Z
```
