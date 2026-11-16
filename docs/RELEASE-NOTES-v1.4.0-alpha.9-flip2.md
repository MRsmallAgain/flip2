# flip2 toolkit v1.4.0-alpha.9-flip2

## Highlights

- **Bundled Apps include toggles** — Per-component **Include on Apply** checkboxes; settings rows (home keys, display, wallpaper, Sherpa) are flat rows instead of empty collapsibles. Unchecked components drop out of `profile.list` and the download gate.
- **Get files: Files panel** — Required downloads nest under a collapsible **Files** heading with **N / M** on the summary; collapsed by default.
- **Companion parity** — Rebuilt Linux AppImage embeds the same wizard as [flip2burn.online](https://flip2burn.online/pages/).

## Verify downloads

```sh
cd pipeline/deploy/dist
sha256sum -c SHA256SUMS
```

## Release assets

Same Magisk installer payload as v1.4.0-alpha.8-flip2 unless repacked at this tag; version strings and bundle names use `1.4.0-alpha.9-flip2`. Linux Companion AppImage at this release.
