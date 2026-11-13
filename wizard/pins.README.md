# Wizard download pins (`pins.json`)

`pins.json` is a sha256/size gate list derived from `catalog.json` for tooling and CI. The browser still loads **`catalog.json`** for the setup wizard (URLs, license text, purpose).

Regenerate after catalog changes:

```bash
./bin/flip2 wizard pins           # writes wizard/pins.json
./bin/flip2 wizard pins --check   # exit 1 if it drifted from catalog.json
```

`flip2 site deploy` runs the regeneration itself (unless `--skip-gen`), because
`pages/js/catalog.js#mergePinFields` lets a pin `sha256`/`size` **override**
`catalog.json`: a stale `pins.json` silently breaks every verified download.

Every `sha256` must match a real upstream file (`sha256sum` on the downloaded bytes), not a guess.
