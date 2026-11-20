# flip2 toolkit v1.4.0-alpha.36-flip2

## Highlights

- **TCL Flip2 Manager 1.4.0-alpha.36** — Linux AppImage and Windows portable (CI-built) on the [package mirror](https://flip2burn.online/packages/); pins in [`catalog.json`](https://flip2burn.online/catalog.json).
- **flip2burn.online** — experimental disclaimer, download/repo footer (full installer + Companion links), no “moved from GitHub” note.
- **Wizard** — WebUSB strip poller no longer clobbers connect after Allow on the phone; **Connect phone** hides in the Get ready banner when the device is ready.
- **Windows CI** — portable-only build (NSIS/Wine workaround); VCOM `flip2_preloader_vcom.inf` tracked for prepack.

## Verify downloads

```sh
cd pipeline/deploy/dist
sha256sum -c SHA256SUMS
```

Companion and installers are also listed in `https://flip2burn.online/catalog.json` with SHA-256 pins.

## Start here

- Wizard: [https://flip2burn.online/](https://flip2burn.online/)
- Safest first install: [`flip2-installer-full-magisk.zip`](https://flip2burn.online/packages/flip2-installer-full-magisk.zip)
