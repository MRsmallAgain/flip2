# flip2 toolkit v1.4.0-alpha.25-flip2

## Highlights

- **Companion v1.4.0-alpha.25** — Neutron flash progress bar, bundled VCOM USB driver fetch for Windows pack, Magisk/`su` launch anti-spam (single-flight refresh, host-root probe, strip auto-refresh noise).
- **Toolkit installers** — Repacked at `1.4.0-alpha.25-flip2` with catalog/pins aligned.

## Verify downloads

```sh
cd pipeline/deploy/dist
sha256sum -c SHA256SUMS
```

## Release assets

Magisk installers repacked at `1.4.0-alpha.25-flip2`; component bundle `flip2-packages-1.4.0-alpha.25-flip2.zip` and system tree zip. Windows and Linux Companion builds pinned in `wizard/catalog.json` (mirror via `sync-site-packages.sh` or `flip2 release`; not in Magisk `SHA256SUMS`).
