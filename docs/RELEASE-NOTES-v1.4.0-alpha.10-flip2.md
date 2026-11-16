# flip2 toolkit v1.4.0-alpha.10-flip2

## Highlights

- **Apply: APK signature conflicts** — `install.sh` surfaces Package Manager errors and retries once after `pm uninstall` when signatures mismatch (e.g. Flip2-patched **Bouncy** over an existing F-Droid install).
- **Companion downloads** — SHA-256 verified on cache hits; stale Magisk installer cache auto-cleared (from alpha.9 work, baked in this AppImage).
- **Bundled Apps toggles** and nested **Files** panel (alpha.9).

## Verify downloads

```sh
cd pipeline/deploy/dist
sha256sum -c SHA256SUMS
```

## Release assets

Magisk installers repacked at `1.4.0-alpha.10-flip2`; catalog pins updated for full/slim/base. Linux Companion AppImage at this release.
