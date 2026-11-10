# flip2 toolkit v1.3.0-alpha.4-flip2

## Highlights

- **Wizard:** **Arcade** profile is visible but **disabled** (grayed out) until FlipMouse Arcade mode is reliable again; **Base**, **Full**, **Slim**, and **Secure** unchanged.
- **Pack on Windows:** installer zips fall back to **7-Zip** when `zip` is not on PATH; deploy scripts strip CR from jq-parsed manifest fields (CRLF-safe packs).

## Verify downloads

```sh
cd pipeline/deploy/dist
sha256sum -c SHA256SUMS
```

## Release assets

| Asset | Tier |
|-------|------|
| flip2-installer-full-magisk.zip | B — full stack + Sherpa voices in installer |
| flip2-installer-slim-magisk.zip | B — full without bundled Sherpa (~same modules; fetch sherpa-en/uk separately) |
| flip2-installer-clean-magisk.zip | B — reduced APK/module set |
| flip2-installer-image-post-magisk.zip | B — after image merge / first-boot |
| flip2-packages-1.3.0-alpha.4-flip2.zip | D — per-component zips + APKs + inner SHA256SUMS |
| flip2-system-tree-1.3.0-alpha.4-flip2.zip | A — system/product merge tree |

## Not included in the toolkit zip

- **Forkgram** — separate GPL release ([TelegramAndroid](https://github.com/MRsmallAgain/TelegramAndroid) tag `flip2-13.0.2.0-r1`); full installer can prefetch when sources are present at pack time.
- **Sherpa ONNX models** — download via wizard catalog (`sherpa-en`, `sherpa-uk`) or `flip2 ime sherpa`.

## Install

1. Root with **neutron.img** (wizard catalog pin) after bootloader unlock.
2. Magisk → Install from storage → **flip2-installer-full-magisk.zip** (or slim/clean per profile).
3. Reboot; check `/cache/flip2-installer.log`.

De-root helper: `sh /data/local/flip2/deroot.sh` after install.
