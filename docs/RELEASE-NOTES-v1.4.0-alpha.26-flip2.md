# flip2 toolkit v1.4.0-alpha.26-flip2

## Highlights

- **flip2burnMouse** — unified Magisk module: landscape gamepad, rotated landscape cursor, portrait mouse, star IME handoff. Wizard **Arcade** profile installs this stack; **Base**, **Slim**, and **Managed** stay on deprecated **FlipMouse** (portrait only, maintenance freeze).
- **Installer payload** — full installer bundles both `FlipMouse.zip` and `flip2burnMouse.zip`; Magisk flash (base/full) unpacks FlipMouse only; Arcade Apply uses flip2burnMouse from the wizard push set.
- **CLI** — `flip2 flip2burn-mouse` (Arcade); `flip2 flipmouse` (legacy Base); `flipmouse-arcade` redirects to flip2burn-mouse.

## Verify downloads

```sh
cd pipeline/deploy/dist
sha256sum -c SHA256SUMS
```

## Release assets

Magisk installers repacked at `1.4.0-alpha.26-flip2`; component bundle `flip2-packages-1.4.0-alpha.26-flip2` includes FlipMouse and flip2burnMouse zips. Companion remains at catalog-pinned `1.4.0-alpha.25` until a companion bump ships.
