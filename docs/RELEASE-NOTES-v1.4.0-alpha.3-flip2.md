# flip2 toolkit v1.4.0-alpha.3-flip2

## Highlights

- **The project moved off GitHub.** The account was suspended on 2026-11-13, so every `github.com/MRsmallAgain` URL 404s. Files are now served from the package mirror under `https://flip2burn.online/packages/`, pinned in `catalog.json`; source is on GitLab. Filenames and SHA-256 pins are unchanged in spirit — same bytes, new home. See `docs/marketing/MOVED.md` and <https://flip2burn.online/pages/moved.html>.
- **`flip2 release` publishes on GitLab.** Assets are published as **release links into the mirror** rather than ~1.4 GB of uploads, so a release cannot duplicate bytes that are already hosted. Anything the mirror lacks is copied to the site bucket and polled until it serves the right byte count *before* the release is created; every link is then read back and re-probed, so a release page with a dead link fails the run instead of shipping.
- **Device-free gates run on every push.** `flip2 ci` runs shell syntax across every tracked script, ES-module syntax across the wizard and Companion, JSON validity, and both generator drift checks. `.gitlab-ci.yml` runs the identical script; `pipeline/ci/install-hooks.sh` runs it before every commit. A real syntax error is now blocked at commit time rather than at flash time.
- **License added: GPL-3.0.** The bouncy / forkgram / astro-loop / FlipMouse-Arcade patches diff into GPL-3.0 apps, so the combination is GPL-3.0 regardless — this release states it.

## Wizard

- **Base and Arcade now genuinely diverge.** The Base profile ships FlipMouse (not Arcade) and no Astro Loop APK, matching the `base` installer flavor instead of silently installing the full set.
- **Download pins check themselves.** `pins.json` is regenerated from `catalog.json` and `flip2 wizard pins --check` fails on drift, so a stale snapshot can no longer override good pins and fail every download verification.
- **A wallpaper is a preference, not a requirement.** The install no longer replaces a wallpaper you already chose, and no longer fails when it finds one.
- **Robust device staging.** Files are staged in a shell-writable directory and ingested as root, because adbd's `shell` user is denied file creation under `data/local/flip2` even at 0777.
- **WebUSB fixes:** handshake serialised, AUTH loop fixed, durable authorization after revoke, "New browser ADB key", RSA pubkey sent after the first AUTH signature, read-before-CNXN, timeouts instead of a stuck "connecting…", and a `flip2 wizard debug-usb` host diagnosis.

## Forkgram

`flip2 forkgram release` now reads its expected size and SHA-256 from `wizard/catalog.json` at runtime instead of carrying a copy. The old duplicate pin is exactly what drifted and broke verification; the fix has been tested against a missing entry, a tampered hash, and a missing catalog.

## Fixed: SHA256SUMS

`SHA256SUMS` is now derived from the assets being published on every run. `v1.4.0-alpha.2-flip2` shipped sums for 2026-11-11 installers while `catalog.json` pinned 2026-11-13 rebuilds, so every `sha256sum -c` against that release failed even though the mirror was fine. That class of skew is now impossible.

## Verify downloads

```sh
cd pipeline/deploy/dist
sha256sum -c SHA256SUMS
```

## Release assets

| Asset | Tier |
|-------|------|
| flip2-installer-base-magisk.zip | B — wizard Base (FlipMouse, no Arcade/Astro Loop) |
| flip2-installer-full-magisk.zip | B — full stack + Sherpa voices in installer |
| flip2-installer-slim-magisk.zip | B — full without bundled Sherpa |
| flip2-installer-clean-magisk.zip | B — reduced APK/module set |
| flip2-installer-image-post-magisk.zip | B — after image merge / first-boot |
| flip2-packages-1.4.0-alpha.3-flip2.zip | D — per-component zips + APKs + inner SHA256SUMS |
| flip2-system-tree-1.4.0-alpha.3-flip2.zip | A — system/product merge tree |
| SHA256SUMS | sums for the seven files above |

All assets are published as links to `https://flip2burn.online/packages/<name>`.

## Install

1. Root with **neutron.img** (catalog pin) after bootloader unlock. Unlocking **erases the phone**.
2. Magisk → Install from storage → **`flip2-installer-full-magisk.zip`** for a conservative first install (or `base` to match the wizard's Base profile).
3. Reboot; check `/cache/flip2-installer.log`. The de-root helper lands at `/data/local/flip2/deroot.sh`.

Never write `super`, `vbmeta`, `system`, `product`, or the preloader, and never touch the `EMMC_BOOT` header. There is no verified boot on this device and no way to restore it; a backup you have not tested is not a backup. Read `docs/SAFETY.md` first.

## Not included

- Third-party binaries are not in this repo and not attached to the release: `neutron.img`, the Forkgram APK, Sherpa-ONNX tarballs, F-Droid APKs. `catalog.json` pins their URLs and hash-and-size; the browser fetches and verifies them.
- **No prebuilt Windows Companion `.exe`.** Build it with `npm run pack:win`.
- The browser **Put on phone** step is still **experimental**. For a first install prefer the installer zip.
