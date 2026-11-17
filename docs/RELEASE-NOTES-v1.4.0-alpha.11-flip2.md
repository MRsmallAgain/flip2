# flip2 toolkit v1.4.0-alpha.11-flip2

## Highlights

- **Mouse cursor speed (Manager + Companion)** — Portrait and landscape sliders under Get ready → **Mouse cursor speed**. Writes `/data/local/flip2/flipmouse-speed-portrait` and `flipmouse-speed-landscape` (root staging); Arcade reloads on poll.
- **FlipMouse Arcade** — Orientation-specific speed files; legacy `flipmouse-speed` fallback for portrait; ScummVM right-soft right-click retained. Star+Vol speed adjustment removed.
- **Image first-boot** — Seeds portrait/landscape speed files alongside legacy `flipmouse-speed`.

## Verify downloads

```sh
cd pipeline/deploy/dist
sha256sum -c SHA256SUMS
```

## Release assets

Magisk installers repacked at `1.4.0-alpha.11-flip2`; catalog pins updated. Linux Companion AppImage `1.4.0-alpha.11` includes Manager mouse-speed UI.
