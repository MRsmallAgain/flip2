# flip2 toolkit v1.3.0-alpha.5-flip2

## Highlights

- **Installer `base` flavor:** `flip2 installer pack --flavor base` → `flip2-installer-base-magisk.zip`. Matches wizard **Base** profile: Magisk modules + Sherpa like **full**, but **no** FlipMouse Arcade module and **no** Astro Loop APK.
- **Pipeline:** `manifest.json` `base` tier, `emit.sh` / `pack-installer.sh` / `service.sh` (module unpack for `base` or `full`), `release.sh` asset list.
- **Companion:** window/taskbar icon from `companion/icons/icon.png` (fallback branding assets).

## Verify downloads

```sh
cd pipeline/deploy/dist
sha256sum -c SHA256SUMS
```

## Release assets

| Asset | Tier |
|-------|------|
| flip2-installer-base-magisk.zip | B — wizard Base (no Arcade/Astro Loop) |
| flip2-installer-full-magisk.zip | B — full stack + Sherpa voices in installer |
| flip2-installer-slim-magisk.zip | B — full without bundled Sherpa |
| flip2-installer-clean-magisk.zip | B — reduced APK/module set |
| flip2-installer-image-post-magisk.zip | B — after image merge / first-boot |
| flip2-packages-1.3.0-alpha.5-flip2.zip | D — per-component zips + APKs + inner SHA256SUMS |
| flip2-system-tree-1.3.0-alpha.5-flip2.zip | A — system/product merge tree |

## Install

1. Root with **neutron.img** (wizard catalog pin) after bootloader unlock.
2. Magisk → Install from storage → **flip2-installer-base-magisk.zip** (recommended for Base profile) or **full** / **slim** as needed.
3. Reboot; check `/cache/flip2-installer.log`.
