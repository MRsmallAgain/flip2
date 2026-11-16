# flip2 toolkit v1.4.0-alpha.8-flip2

## Highlights

- **TCL Flip2 Manager UI** — Collapsible step sections (**Start · Bundled Apps · Device · Set up**); active step opens as you navigate; **Start** and **Device** stay pinned open. **Device** moved to bottom of the flow. Per-app collapsibles on **Bundled Apps** (renamed from Apps).
- **GitHub migration copy** — Footer: **We moved on 2026-11-13** with link to [moved](https://flip2burn.online/pages/moved.html).
- **Companion parity** — Desktop Companion embeds the same `wizard/` as [flip2burn.online](https://flip2burn.online/pages/). Rebuild **Linux AppImage** from this release; **Windows** `pack:win` on a PC with this tag for matching UI.
- **CI** — GitLab builds **companion:linux** + headless **companion:smoke** (Bundled Apps pill verified).

## Verify downloads

```sh
cd pipeline/deploy/dist
sha256sum -c SHA256SUMS
```

## Release assets

Same Magisk/installer asset set as v1.4.0-alpha.7-flip2 with versioned bundle names `1.4.0-alpha.8-flip2` where repacked. Linux Companion AppImage: build from `companion/` at this tag (`flip2 companion` pack or CI artifact).
